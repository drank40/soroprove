/-
Runtime state of a wasmi 29.0.0 instance as observed by Soroban.
-/
import SorobanLean.Wasm.Compile
import SorobanLean.Wasm.Numerics
import Std.Data.TreeMap

namespace Wasm

inductive Value where
  | i32 (v : UInt32)
  | i64 (v : UInt64)
  deriving DecidableEq, Repr, Inhabited

def Value.zero : ValType → Value
  | .i32 => .i32 0
  | .i64 => .i64 0

/-- wasmi fuel: `total` and `remaining` (src: soroban-wasmi-29.0.0/src/store.rs
    `Fuel`, consume_fuel :252-258, reset :261-264). `fuel_consumed = total - remaining`. -/
structure Fuel where
  total : Nat := 0
  remaining : Nat := 0
  /-- `false` in the unmetered model: consumption is not tracked. -/
  metered : Bool := true
  deriving DecidableEq, Repr, Inhabited

namespace Fuel
/-- `Fuel::consume_fuel`: fails with OutOfFuel (leaving fuel unchanged) if insufficient. -/
def consume (f : Fuel) (delta : Nat) : Except TrapCode Fuel :=
  if !f.metered then .ok f else
  if delta ≤ f.remaining then .ok { f with remaining := f.remaining - delta } else .error .OutOfFuel
def consumed (f : Fuel) : Nat := f.total - f.remaining
end Fuel

def PAGE_SIZE : Nat := 65536
/-- `Pages::max()` for 32-bit memories. -/
def MAX_PAGES : Nat := 65536

/-- src: soroban-wasmi-29.0.0/src/engine/stack/mod.rs:23-29,86-97:
    value stack max = 1024*1024 / size_of::<UntypedValue>() (= 8), recursion depth 1024. -/
def MAX_VALUE_STACK : Nat := 1024 * 1024 / 8
def MAX_RECURSION_DEPTH : Nat := 1024

/-- Linear memory: its byte size and the bytes ever written (absent bytes are 0).
    A sparse map instead of a flat buffer keeps instantiation (a 1 MiB zeroed memory
    is the norm for Soroban contracts) and every access cheap, also under kernel
    reduction; all operations below are structurally recursive. -/
structure LinMem where
  size : Nat := 0
  bytes : Std.TreeMap Nat UInt8 := ∅
  deriving Inhabited

namespace LinMem

def zeros (n : Nat) : LinMem := { size := n }

@[inline] def get (m : LinMem) (a : Nat) : UInt8 := m.bytes[a]?.getD 0

@[inline] def set (m : LinMem) (a : Nat) (b : UInt8) : LinMem := { m with bytes := m.bytes.insert a b }

def grow (m : LinMem) (n : Nat) : LinMem := { m with size := m.size + n }

/-- Little-endian value of `m[a .. a+n)` (shift `8*i` for the `i`-th byte). -/
def readLE (m : LinMem) (a : Nat) : Nat → Nat
  | 0 => 0
  | n + 1 => (m.get a).toNat ||| (readLE m (a + 1) n <<< 8)

def writeLE (m : LinMem) (a : Nat) : Nat → Nat → LinMem
  | 0, _ => m
  | n + 1, v => writeLE (m.set a (v % 256).toUInt8) (a + 1) n (v >>> 8)

/-- `slice.fill(b)` on `[d, d+n)`. -/
def fill (m : LinMem) (d : Nat) (b : UInt8) : Nat → LinMem
  | 0 => m
  | n + 1 => fill (m.set d b) (d + 1) b n

/-- The bytes `m[a .. a+n)`. -/
def readBytes (m : LinMem) (a n : Nat) : ByteArray :=
  ⟨(List.range n).toArray.map fun i => m.get (a + i)⟩

/-- Write `src[s .. s+n)` at `d`. -/
def writeFrom (m : LinMem) (d : Nat) (src : ByteArray) (s : Nat) : Nat → LinMem
  | 0 => m
  | n + 1 => writeFrom (m.set d (src.get! s)) (d + 1) src (s + 1) n

end LinMem

structure Store where
  mem : LinMem := {}
  /-- Maximum pages from the module's memory type (`none` = `Pages::max()`). -/
  memMax : Option Nat := none
  globals : Array Value := #[]
  /-- Function table: entries are function indices or null. -/
  table : Array (Option Nat) := #[]
  /-- Data segments (dropped segments become empty). -/
  datas : Array ByteArray := #[]
  /-- Element segments (dropped segments become empty). -/
  elems : Array (Array (Option Nat)) := #[]
  fuel : Fuel := {}
  deriving Inhabited

def Store.pages (s : Store) : Nat := s.mem.size / PAGE_SIZE

/-- A trap or host error. `E` is the host's error type. -/
inductive Trap (E : Type) where
  | code (c : TrapCode)
  | host (e : E)
  deriving Repr, Inhabited

/-- Result of interpretation with an explicit step budget `gas` (a property of
    the Lean definition only; it never corresponds to runtime behaviour).
    A trap carries the state `S` at the moment of the trap: wasmi keeps the fuel
    consumed (and memory writes) of a trapping call in the store, and Soroban charges
    that fuel to the budget (soroban-env-host/src/vm.rs:327-346). -/
inductive Res (E S α : Type) where
  | ok (a : α)
  | trap (t : Trap E) (s : S)
  | gasOut
  deriving Inhabited

namespace Res
@[inline] def bind {E S α β} (r : Res E S α) (f : α → Res E S β) : Res E S β :=
  match r with
  | .ok a => f a
  | .trap t s => .trap t s
  | .gasOut => .gasOut
instance {E S} : Monad (Res E S) where
  pure := .ok
  bind := bind
@[inline] def ofExcept {E S α} (s : S) : Except TrapCode α → Res E S α
  | .ok a => .ok a
  | .error c => .trap (.code c) s
end Res

/-- What the embedder provides. `H` is the host state, `E` the host error type.
    * `call g imp args st h`: call imported function `imp` with the given arguments.
      The host may read/write `st.mem` and manipulate `st.fuel` (Soroban moves fuel in
      and out of the VM at every host call). `g` is the remaining step budget so the
      host can itself run Wasm (cross-contract calls).
    * `memoryGrowing cur desired max h`: the wasmi `ResourceLimiter::memory_growing`
      hook (src: soroban-wasmi-29.0.0/src/memory/mod.rs:211-224). `ok true` allows,
      `ok false` refuses (memory.grow returns -1), `error` makes memory.grow trap
      with GrowthOperationLimited. Sizes are in bytes. -/
structure HostIface (H E : Type) where
  call : Nat → Nat → List Value → Store → H → Res E (Store × H) (List Value × Store × H)
  memoryGrowing : Nat → Nat → Option Nat → H → Res E H (Bool × H)

/-! ## Memory access -/

namespace Mem

/-- Little-endian read of `n` bytes at `a`; caller checks bounds. -/
def readLE (m : LinMem) (a n : Nat) : Nat := m.readLE a n

def writeLE (m : LinMem) (a n v : Nat) : LinMem := m.writeLE a n v

/-- src: wasmi_core-0.13.0/src/untyped.rs:133-138 (`effective_address`: checked u32
    add, overflow traps) then the slice access traps if out of bounds. -/
def effAddr (m : LinMem) (addr : UInt32) (offset n : Nat) : Except TrapCode Nat :=
  let ea := offset + addr.toNat
  if ea ≥ 2^32 then .error .MemoryOutOfBounds
  else if ea + n > m.size then .error .MemoryOutOfBounds
  else .ok ea

def loadBytes : LoadOp → Nat
  | .i32 => 4 | .i64 => 8 | .i32_8s | .i32_8u | .i64_8s | .i64_8u => 1
  | .i32_16s | .i32_16u | .i64_16s | .i64_16u => 2 | .i64_32s | .i64_32u => 4

def storeBytes : StoreOp → Nat
  | .i32 => 4 | .i64 => 8 | .i32_8 | .i64_8 => 1 | .i32_16 | .i64_16 => 2 | .i64_32 => 4

/-- Interpret the loaded little-endian bits according to the load op. -/
def loadValue (op : LoadOp) (raw : Nat) : Value :=
  match op with
  | .i32 => .i32 raw.toUInt32
  | .i64 => .i64 raw.toUInt64
  | .i32_8s => .i32 (Num.sext8_32 raw.toUInt32)
  | .i32_8u => .i32 raw.toUInt32
  | .i32_16s => .i32 (Num.sext16_32 raw.toUInt32)
  | .i32_16u => .i32 raw.toUInt32
  | .i64_8s => .i64 (Num.sext8_64 raw.toUInt64)
  | .i64_8u => .i64 raw.toUInt64
  | .i64_16s => .i64 (Num.sext16_64 raw.toUInt64)
  | .i64_16u => .i64 raw.toUInt64
  | .i64_32s => .i64 (Num.sext32_64 raw.toUInt64)
  | .i64_32u => .i64 raw.toUInt64

def storeRaw : Value → Nat
  | .i32 v => v.toNat
  | .i64 v => v.toNat

/-- `slice.fill(byte)` on `[d, d+n)`; caller checks bounds. -/
def writeBytes (m : LinMem) (d n : Nat) (b : UInt8) : LinMem := m.fill d b n

/-- `copy_within(s..s+n, d)` (memmove semantics: the source is read first); caller
    checks bounds. -/
def copyWithin (m : LinMem) (s d n : Nat) : LinMem :=
  m.writeFrom d (m.readBytes s n) 0 n

/-- Copy `n` bytes of `src[s..]` into `m[d..]`; caller checks bounds. -/
def copyFrom (m : LinMem) (d : Nat) (src : ByteArray) (s n : Nat) : LinMem := m.writeFrom d src s n

def arrCopyWithin {α} [Inhabited α] (a : Array α) (s d n : Nat) : Array α :=
  let src := a.extract s (s + n)
  Id.run do
    let mut a := a
    for i in [0:n] do a := a.set! (d + i) (src[i]!)
    return a

def arrCopyFrom {α} [Inhabited α] (a : Array α) (d : Nat) (src : Array α) (s n : Nat) : Array α := Id.run do
  let mut a := a
  for i in [0:n] do a := a.set! (d + i) (src[s + i]!)
  return a

end Mem

/-- wasmi converts bulk-memory operands with `i32::from(x) as usize`, which
    sign-extends (src: soroban-wasmi-29.0.0/src/engine/executor.rs:1142-1146, 1164-1167,
    1188-1191). We model `usize` as 64-bit. -/
def bulkUsize (x : UInt32) : Nat := (Num.extendS x).toNat

end Wasm
