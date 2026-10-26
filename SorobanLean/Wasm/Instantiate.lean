/-
Module instantiation as done by soroban-wasmi 29.0.0
(src: vendor/crates/soroban-wasmi-29.0.0/src/module/instantiate/mod.rs:49-385).

Order: imports, functions, tables (null-initialised), memories (`Memory::new` asks the
resource limiter for `0 → initial` bytes, memory/mod.rs:132-160), globals, exports,
start fn, element segments (in order, each bounds-checked, active ones dropped after
init, :301-347), data segments (in order, active ones written then dropped,
:350-385, memory/data.rs:68-77). Soroban additionally rejects modules with a start
function (soroban-env-host/src/vm.rs:170-180, `ensure_no_start`).
-/
import SorobanLean.Wasm.Exec

namespace Wasm

inductive InstError where
  | unsupportedImport (module name : String)
  | memoryAlloc            -- MemoryError::OutOfBoundsAllocation / limiter refusal
  | elementSegmentDoesNotFit (seg : Nat)
  | dataOutOfBounds (seg : Nat)
  | startFunctionPresent
  | badModule (msg : String)
  deriving Repr, Inhabited

namespace Instantiate

variable {H E : Type}

def evalConst (globals : Array Value) : ConstExpr → Option Value
  | .i32Const v => some (.i32 v)
  | .i64Const v => some (.i64 v)
  | .globalGet i => globals[i]?
  | .refFunc f => some (.i64 f.toUInt64)
  | .refNull _ => some (.i64 0)

def elemItem (globals : Array Value) : ConstExpr → Option Nat
  | .refFunc f => some f
  | .refNull _ => none
  | .globalGet i => match globals[i]? with | some (.i64 f) => some f.toNat | _ => none
  | _ => none

/-- Result of instantiation: the store and host state, or an error. Host errors
    raised by the limiter are reported as `.trap`. -/
inductive IRes (E α : Type) where
  | ok (a : α)
  | err (e : InstError)
  | trap (t : Trap E)

/-- Instantiate `m` whose imports are only functions (the Soroban case; imported
    globals may be supplied via `importedGlobals`). -/
def instantiate (host : HostIface H E) (m : Module) (importedGlobals : Array Value) (h : H) :
    IRes E (Store × H) := Id.run do
  -- imports other than functions and globals are not provided by Soroban
  for i in m.imports do
    match i.desc with
    | .func _ | .global _ => pure ()
    | _ => return .err (.unsupportedImport i.module i.name)
  -- tables: null-initialised to their minimum size
  let table : Array (Option Nat) := match m.tables[0]? with
    | some t => Array.replicate t.limits.min none
    | none => #[]
  -- memories: limiter sees 0 → initial bytes
  let mut h := h
  let mut mem : LinMem := {}
  let mut memMax : Option Nat := none
  match m.mems[0]? with
  | none => pure ()
  | some l =>
    if l.min > MAX_PAGES then return .err .memoryAlloc
    match host.memoryGrowing 0 (l.min * PAGE_SIZE) (some ((l.max.getD MAX_PAGES) * PAGE_SIZE)) h with
    | .ok (true, h') => h := h'; mem := LinMem.zeros (l.min * PAGE_SIZE); memMax := l.max
    | .ok (false, _) => return .err .memoryAlloc
    | .trap t _ => return .trap t
    | .gasOut => return .err (.badModule "gas")
  -- globals: imported first, then internal, each init evaluated in order
  let mut globals := importedGlobals
  for g in m.globals do
    match evalConst globals g.init with
    | some v => globals := globals.push v
    | none => return .err (.badModule "bad global init")
  -- start function
  if m.start.isSome then return .err .startFunctionPresent
  -- element segments
  let mut st : Store := { mem, memMax, globals, table, datas := #[], elems := #[] }
  let mut k := 0
  for e in m.elems do
    let items : Array (Option Nat) := (e.items.map (elemItem globals)).toArray
    match e.mode with
    | .declarative => st := { st with elems := st.elems.push #[] }
    | .passive => st := { st with elems := st.elems.push items }
    | .active _ off =>
      let dst ← match evalConst globals off with
        | some (.i32 v) => pure v.toNat
        | _ => return .err (.badModule "bad elem offset")
      if dst + items.size ≥ 2^32 || dst + items.size > st.table.size then
        return .err (.elementSegmentDoesNotFit k)
      st := { st with table := Mem.arrCopyFrom st.table dst items 0 items.size, elems := st.elems.push #[] }
    k := k + 1
  -- data segments
  k := 0
  for d in m.datas do
    match d.mode with
    | .passive => st := { st with datas := st.datas.push d.init }
    | .active _ off =>
      let dst ← match evalConst globals off with
        | some (.i32 v) => pure v.toNat
        | _ => return .err (.badModule "bad data offset")
      if dst + d.init.size > st.mem.size then return .err (.dataOutOfBounds k)
      st := { st with mem := Mem.copyFrom st.mem dst d.init 0 d.init.size, datas := st.datas.push ByteArray.empty }
    k := k + 1
  return .ok (st, h)

/-- Build the execution context for a module. -/
def mkCtx (host : HostIface H E) (m : Module) (costs : FuelCosts := sorobanFuelCosts) : Ctx H E :=
  let env := Compile.mkEnv m costs
  { host, funcs := Compile.module m costs, nImports := m.numImportedFuncs,
    funcTypes := env.funcTypes, types := m.types, costs }

def exportedFunc? (m : Module) (name : String) : Option Nat :=
  m.exports.findSome? fun e => match e.desc with
    | .func i => if e.name == name then some i else none
    | _ => none

end Instantiate
end Wasm
