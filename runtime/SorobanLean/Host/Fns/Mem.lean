/-
Host functions that read and write the calling VM's linear memory
(src: soroban-env-host/src/host/mem_helper.rs:20-430, host/data_helper.rs:742-1034,
host.rs:1771-1811, :2010-2036, :2687-2694; wasmi `Memory::read/write`,
soroban-wasmi-29.0.0/src/memory/mod.rs: out-of-range → `MemoryError::OutOfBoundsAccess`,
mapped to (WasmVm, IndexBounds) by soroban-env-common/src/error.rs:224-227).
-/
import SorobanLean.Host.Fns.Num

namespace Soroban
open Xdr

def errArithOverflow : HErr := errV .Value .ArithDomain
def errOobLinearMemory : HErr := errV .WasmVm .IndexBounds

/-- `get_mem_fn_args` (mem_helper.rs:20-36): the current frame must be a VM frame. -/
def getMemFnArgs (pos len : Val) : HostM (Nat × Nat) := do
  checkCtxBorrow
  match (← get).contexts.back? with
  | some ctx => match ctx.frame with
    | .contractVM .. => pure (u32Of pos, u32Of len)
    | _ => hostThrow .WasmVm .InternalError
  | none => hostThrow .Context .InternalError

/-- `Vm::get_memory` (vm.rs:218-228) on the calling VM. -/
def callerMem : HostM Wasm.LinMem := do
  match (← get).vmCaller with
  | some c => if c.memExported then pure c.store.mem else hostThrow .WasmVm .MissingValue
  | none => hostThrow .Context .InternalError

def setCallerMem (m : Wasm.LinMem) : HostM Unit :=
  modify fun s => { s with vmCaller := s.vmCaller.map fun c => { c with store := { c.store with mem := m } } }

def leU64 (m : Wasm.LinMem) (a : Nat) : UInt64 := UInt64.ofNat (m.readLE a 8)
def leU32 (m : Wasm.LinMem) (a : Nat) : Nat := m.readLE a 4

/-- `metered_vm_read_bytes_from_linear_memory` (mem_helper.rs:56-69). -/
def readBytesFromLinearMemory (pos len : Nat) : HostM ByteArray := do
  charge .MemCpy (some len)
  let m ← callerMem
  if pos + len > m.size then throw errOobLinearMemory
  pure (m.readBytes pos len)

/-- `metered_vm_write_bytes_to_linear_memory` (mem_helper.rs:40-54). -/
def writeBytesToLinearMemory (pos : Nat) (b : ByteArray) : HostM Unit := do
  charge .MemCpy (some b.size)
  let m ← callerMem
  if pos + b.size > m.size then throw errOobLinearMemory
  setCallerMem (m.writeFrom pos b 0 b.size)

/-- `metered_vm_read_vals_from_linear_memory` (mem_helper.rs:110-145) with the
    relative-to-absolute decoding of each 8-byte little-endian word. -/
def readValsFromLinearMemory (pos len : Nat) : HostM (Array Val) := do
  let byteLen := len * 8
  if byteLen ≥ 2^32 then throw errArithOverflow
  if pos + byteLen ≥ 2^32 then throw errArithOverflow
  let m ← callerMem
  if pos + byteLen > m.size then throw errOobLinearMemory
  charge .MemCpy (some byteLen)
  let mut out := #[]
  for i in [0:len] do
    out := out.push (← relativeToAbsolute ⟨leU64 m (pos + 8 * i)⟩)
  pure out

/-- `metered_vm_write_vals_to_linear_memory` (mem_helper.rs:71-108). -/
def writeValsToLinearMemory (pos : Nat) (vals : Array Val) : HostM Unit := do
  let byteLen := vals.size * 8
  if byteLen ≥ 2^32 then throw errArithOverflow
  if pos + byteLen ≥ 2^32 then throw errArithOverflow
  let m ← callerMem
  if pos + byteLen > m.size then throw errOobLinearMemory
  charge .MemCpy (some byteLen)
  -- written element by element: on a conversion error the earlier ones stay written
  for h : i in [0:vals.size] do
    let r ← absoluteToRelative vals[i]
    setCallerMem ((← callerMem).writeLE (pos + 8 * i) 8 r.payload.toNat)

/-- `scan_linear_memory_slice` (mem_helper.rs:147-180): the `index`-th 8-byte
    (ptr: u32 LE, len: u32 LE) descriptor at `pos`, as a byte range. -/
def scanLinearMemorySlice (m : Wasm.LinMem) (pos index : Nat) : HostM (Nat × Nat) := do
  let sp := pos + index * 8
  if sp + 8 > m.size then throw errOobLinearMemory
  let ptr := leU32 m sp
  let len := leU32 m (sp + 4)
  if ptr + len ≥ 2^32 then throw errArithOverflow
  pure (ptr, len)

/-- `metered_vm_scan_slices_in_linear_memory` (mem_helper.rs:182-205): the bytes of
    `num` slices described at `pos`, handed to `k` in order. -/
def scanSlicesInLinearMemory {α} (pos num : Nat) (k : Nat → ByteArray → HostM α) : HostM (Array α) := do
  let m ← callerMem
  charge .MemCpy (some (satMul num 8))
  let mut out := #[]
  for i in [0:num] do
    let (p, l) ← scanLinearMemorySlice m pos i
    if p + l > m.size then throw errOobLinearMemory
    out := out.push (← k i (m.readBytes p l))
  pure out

/-! ## vec / symbol -/

/-- `HostVec::from_vec` (metered_vector.rs:83-89). -/
def hostVecFromVec (xs : Array Val) : HostM Val := do
  if xs.size ≥ 2^32 then hostThrow .Object .IndexBounds
  addHostObject (.vec xs)

/-- `vec_new_from_linear_memory` (host.rs:2010-2036). -/
def vecNewFromLinearMemory : HostFnImpl := fun _ a => do
  let (pos, len) ← getMemFnArgs a[0]! a[1]!
  chargeBulkInitCpy DS.vec DS.val len
  charge .MemCpy (some (satMul (satMul 2 len) 8))
  let vals ← readValsFromLinearMemory pos len
  for v in vals do checkValIntegrity v
  hostVecFromVec vals

/-- `ScSymbol::try_from_bytes` (host_object.rs:294-319). -/
def scSymbolTryFromBytes (b : ByteArray) : HostM ByteArray := do
  if b.size > SCSYMBOL_LIMIT then hostThrow .Value .InvalidInput
  if !(b.toList.all fun x => (SymbolSmall.encodeByte x).isSome) then hostThrow .Value .InvalidInput
  pure b

/-- `memobj_new_from_linear_memory::<ScSymbol>` (mem_helper.rs:419-430). -/
def symbolNewFromLinearMemory : HostFnImpl := fun _ a => do
  let (pos, len) ← getMemFnArgs a[0]! a[1]!
  charge .MemAlloc (some len)
  let b ← readBytesFromLinearMemory pos len
  addHostObject (.symbol (← scSymbolTryFromBytes b))

/-! ## maps -/

def hostMapOps : MMapOps Val Val := instanceMapOps

/-- `map_new_from_slices_impl` with symbol keys (data_helper.rs:744-792). -/
def mapNewFromSlices (keys vals : Array Val) (sparse : Bool) : HostM Val := do
  if keys.size != vals.size then hostThrow .Object .UnexpectedSize
  chargeBulkInitCpy DS.vec (DS.pair DS.val DS.val) keys.size
  let mut prev : Option Val := none
  let mut kvs := #[]
  for h : i in [0:keys.size] do
    let k := keys[i]
    let v := vals[i]!
    -- `sparse && compare(..)` short-circuits (data_helper.rs:768-776).
    if let some p := prev then
      if sparse then
        if (← cmpVal BIG p k) != .lt then hostThrow .Object .InvalidInput
    prev := some k
    checkValIntegrity v
    if !sparse || !v.isVoid then kvs := kvs.push (k, v)
  let m ← MMap.fromMap hostMapOps kvs
  addHostObject (.map m)

/-- `map_new_from_linear_memory_impl` (data_helper.rs:799-845). -/
def mapNewFromLinearMemory (sparse : Bool) : HostFnImpl := fun _ a => do
  let (keysPos, len) ← getMemFnArgs a[0]! a[2]!
  chargeBulkInitCpy DS.vec DS.val len   -- Vec::<Symbol>::with_metered_capacity
  let keys ← scanSlicesInLinearMemory keysPos len fun _ s => symbolFromBytes s
  let valsPos := u32Of a[1]!
  chargeBulkInitCpy DS.vec DS.val len
  charge .MemCpy (some (satMul len (2 * 8)))
  let vals ← readValsFromLinearMemory valsPos len
  mapNewFromSlices keys vals sparse

/-- `TryFromVal<Val> for Symbol`: a conversion error unless the tag is a symbol tag. -/
def asSymbol (v : Val) : HostM Val :=
  if v.getTag == .SymbolSmall || v.getTag == .SymbolObject then pure v else throw conversionError

/-- `compare_symbol_to_bytes` (mem_helper.rs:432-446). -/
def compareSymbolToBytes (sym : Val) (b : ByteArray) : HostM Ordering := do
  if sym.getTag == .SymbolSmall then cmpBytesM (symbolSmallBytes sym.getBody) b
  else
    let s ← visitSymbolObj sym
    cmpBytesM s b

/-- `map_unpack_impl` (data_helper.rs:846-951) for keys given as byte strings. -/
def mapUnpack (map : Val) (keys : Nat → HostM ByteArray) (n : Nat) (sparse : Bool) :
    HostM (Array Val) := do
  let entries ← match ← visitObj map with
    | .map m => pure m
    | _ => hostThrow .Object .InternalError
  if !sparse && entries.size != n then hostThrow .Object .UnexpectedSize
  chargeShallowCopy n DS.val
  chargeAccess hostMapOps.entrySize entries.size   -- `host_map.iter` (charge_scan)
  let mut j := 0
  let mut prev : Option ByteArray := none
  let mut out := #[]
  for i in [0:n] do
    let key ← keys i
    if let some p := prev then
      if (← cmpBytesM p key) != .lt then hostThrow .Object .InvalidInput
    prev := some key
    let mut ov := Val.VOID
    -- (the Rust `while let` over the map iterator; at most `entries.size` steps)
    for _ in [0:entries.size] do
      if j ≥ entries.size then break
      let (mk, mv) := entries[j]!
      let ks ← asSymbol mk
      let c ← compareSymbolToBytes ks key
      if sparse then
        match c with
        | .lt => j := j + 1
        | .eq => ov := mv; j := j + 1; break
        | .gt => break
      else
        if c != .eq then hostThrow .Object .InvalidInput
        ov := mv; j := j + 1; break
    out := out.push ov
  for k in [j:entries.size] do
    discard <| asSymbol entries[k]!.1
  pure out

/-- `map_unpack_to_linear_memory_impl` (data_helper.rs:986-1033). -/
def mapUnpackToLinearMemory (sparse : Bool) : HostFnImpl := fun _ a => do
  let map := a[0]!
  let (keysPos, len) ← getMemFnArgs a[1]! a[3]!
  chargeBulkInitCpy DS.vec DS.val len
  let m ← callerMem
  chargeShallowCopy len DS.u64
  let vals ← mapUnpack map (fun i => do
      let (p, l) ← scanLinearMemorySlice m keysPos i
      if p + l > m.size then throw errOobLinearMemory
      pure (m.readBytes p l)) len sparse
  writeValsToLinearMemory (u32Of a[2]!) vals
  pure Val.VOID

end Soroban
