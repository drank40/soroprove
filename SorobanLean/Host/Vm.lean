/-
Contract VMs (src: soroban-env-host/src/vm.rs, vm/parsed_module.rs, vm/dispatch.rs,
vm/fuel_refillable.rs, budget/wasmi_helper.rs; soroban-env-common/src/error.rs:173-283
for wasmi error → `Error` mapping).

No module cache: `invoke_host_function(.., module_cache = None)` parses every
contract on instantiation (frame.rs:932-960 falls through to
`Vm::new_with_cost_inputs`).
-/
import SorobanLean.Host.Storage
import SorobanLean.Wasm.Instantiate
import SorobanLean.Wasm.Decode

namespace Soroban
open Xdr

/-! ## wasmi errors (soroban-env-common/src/error.rs:173-283) -/

/-- `From<TrapCode> for Error`. -/
def trapCodeError : Wasm.TrapCode → HErr
  | .UnreachableCodeReached => errV .WasmVm .InvalidAction
  | .MemoryOutOfBounds | .TableOutOfBounds => errV .WasmVm .IndexBounds
  | .IndirectCallToNull => errV .WasmVm .MissingValue
  | .IntegerDivisionByZero | .IntegerOverflow | .BadConversionToInteger => errV .WasmVm .ArithDomain
  | .BadSignature => errV .WasmVm .UnexpectedType
  | .StackOverflow | .OutOfFuel | .GrowthOperationLimited => errV .Budget .ExceededLimit

/-- Any wasmi error without a dedicated mapping (parse/validation/translation,
    linker, `FoundStartFn`, segment bounds): (WasmVm, InvalidAction). -/
def wasmiOtherError : HErr := errV .WasmVm .InvalidAction

/-! ## Cost inputs (parsed_module.rs:21-125) -/

def chargeForParsing : CostInputs → HostM Unit
  | .v0 n => charge .VmInstantiation (some n)
  | .v1 c => do
    charge .ParseWasmInstructions (some c.nInstructions.toNat)
    charge .ParseWasmFunctions (some c.nFunctions.toNat)
    charge .ParseWasmGlobals (some c.nGlobals.toNat)
    charge .ParseWasmTableEntries (some c.nTableEntries.toNat)
    charge .ParseWasmTypes (some c.nTypes.toNat)
    charge .ParseWasmDataSegments (some c.nDataSegments.toNat)
    charge .ParseWasmElemSegments (some c.nElemSegments.toNat)
    charge .ParseWasmImports (some c.nImports.toNat)
    charge .ParseWasmExports (some c.nExports.toNat)
    charge .ParseWasmDataSegmentBytes (some c.nDataSegmentBytes.toNat)

def chargeForInstantiation : CostInputs → HostM Unit
  | .v0 n => charge .VmCachedInstantiation (some n)
  | .v1 c => do
    charge .InstantiateWasmInstructions none
    charge .InstantiateWasmFunctions (some c.nFunctions.toNat)
    charge .InstantiateWasmGlobals (some c.nGlobals.toNat)
    charge .InstantiateWasmTableEntries (some c.nTableEntries.toNat)
    charge .InstantiateWasmTypes none
    charge .InstantiateWasmDataSegments (some c.nDataSegments.toNat)
    charge .InstantiateWasmElemSegments (some c.nElemSegments.toNat)
    charge .InstantiateWasmImports (some c.nImports.toNat)
    charge .InstantiateWasmExports (some c.nExports.toNat)
    charge .InstantiateWasmDataSegmentBytes (some c.nDataSegmentBytes.toNat)

/-! ## Parsing (parsed_module.rs:206-458) -/

structure ParsedModule where
  module : Wasm.Module
  protoVersion : Nat
  costInputs : CostInputs
  deriving Inhabited

def MAX_VM_ARGS : Nat := 32

/-- `INTERFACE_VERSION.pre_release` (soroban-env-common/src/meta.rs, non-`next`). -/
def INTERFACE_PRE_RELEASE : Nat := 0

/-- `check_contract_interface_version` (parsed_module.rs:306-366). -/
def checkInterfaceVersion (ledgerProto : Nat) (v : SCEnvMetaEntryInterfaceVersion) : HostM Unit := do
  let wantProto ← if ledgerProto ≤ INTERFACE_PROTOCOL then pure ledgerProto
    else hostThrow .Context .InternalError
  let gotPre := v.preRelease.toNat
  let gotProto := v.protocol.toNat
  if gotProto < wantProto then
    if gotPre != 0 then hostThrow .WasmVm .InvalidInput
  else if gotProto == wantProto then
    if gotPre != INTERFACE_PRE_RELEASE then hostThrow .WasmVm .InvalidInput
  else hostThrow .WasmVm .InvalidInput

/-- `check_meta_section` (parsed_module.rs:411-440): the first `ScEnvMetaEntry` read by
    `read_xdr_iter` (generated.rs:509-541: `None` on an empty section, otherwise one
    value read under an extra `with_limited_depth`, trailing bytes ignored). -/
def checkMetaSection (ledgerProto : Nat) (m : Wasm.Module) : HostM SCEnvMetaEntryInterfaceVersion := do
  let some sec := m.customSection? "contractenvmetav0" | hostThrow .WasmVm .InvalidInput
  if sec.size == 0 then hostThrow .WasmVm .InvalidInput
  match rd_SCEnvMetaEntry BIG_FUEL (DEFAULT_DEPTH - 1) sec.data.toList sec.size with
  | .ok (.SC_ENV_META_KIND_INTERFACE_VERSION v, _, _) =>
      checkInterfaceVersion ledgerProto v; pure v
  | .error e => throw (xdrErrToVal e)

/-- `check_max_args` (parsed_module.rs:442-466). -/
def checkMaxArgs (m : Wasm.Module) : HostM Unit := do
  for e in m.exports do
    if let .func i := e.desc then
      let ft := (m.funcTypeIdx? i).bind (m.types[·]?) |>.getD default
      if ft.results.length > MAX_VM_ARGS then hostThrow .WasmVm .InvalidInput
      if ft.params.length > MAX_VM_ARGS then hostThrow .WasmVm .InvalidInput

/-- `ParsedModule::new` (parsed_module.rs:206-221) + `parse_wasm` (:285-303). -/
def parseModule (wasm : ByteArray) (ci : CostInputs) : HostM ParsedModule := do
  let ledgerProto := (← withLedgerInfo).protocolVersion
  chargeForParsing ci
  let m ← match Wasm.Decode.decodeModule wasm with
    | .ok m => pure m
    | .error _ => throw wasmiOtherError
  checkMaxArgs m
  let v ← checkMetaSection ledgerProto m
  pure { module := m, protoVersion := v.protocol.toNat, costInputs := ci }

/-- `with_import_symbols` (parsed_module.rs:223-248): the set of function imports whose
    module and field names are both shorter than 10 bytes, charged as a
    `Vec<(&str, &str)>`. -/
def importSymbols (m : Wasm.Module) : List (String × String) :=
  m.imports.foldl (fun acc i =>
    match i.desc with
    | .func _ => if i.module.utf8ByteSize < 10 && i.name.utf8ByteSize < 10 && !acc.contains (i.module, i.name)
        then acc ++ [(i.module, i.name)] else acc
    | _ => acc) []

def chargeImportSymbols (m : Wasm.Module) : HostM (List (String × String)) := do
  let syms := importSymbols m
  chargeBulkInitCpy DS.vec (DS.pair DS.str DS.str) syms.length
  pure syms

/-- The Wasm signature of a host function: all `i64` (dispatch.rs:206-208). -/
def hostFnType (f : Env.HostFn) : Wasm.FuncType :=
  { params := List.replicate f.arity .i64, results := [.i64] }

/-- Link the module's function imports against the minimal linker of
    `make_minimal_wasmi_linker_for_symbols` (vm.rs:84-96): an import resolves iff it
    is in the symbol set and names a host function; its declared type must equal the
    host function's (wasmi instantiate/mod.rs:94-140). -/
def linkImports (m : Wasm.Module) (syms : List (String × String)) : HostM (Array Env.HostFn) := do
  let mut out := #[]
  for i in m.imports do
    match i.desc with
    | .func t =>
      if !syms.contains (i.module, i.name) then throw wasmiOtherError
      let some f := Env.HostFn.resolve i.module i.name | throw wasmiOtherError
      if m.types[t]? != some (hostFnType f) then throw wasmiOtherError
      out := out.push f
    | _ => throw wasmiOtherError
  pure out

/-- `check_contract_imports_match_host_protocol` (parsed_module.rs:368-399). -/
def checkImportsProtocol (pm : ParsedModule) : HostM Unit := do
  let ledgerProto := (← withLedgerInfo).protocolVersion
  let syms ← chargeImportSymbols pm.module
  for f in Env.HostFn.all do
    if !syms.contains (f.module.exportName, f.exportName) then continue
    if let some lo := f.minProto then
      if pm.protoVersion < lo || ledgerProto < lo then hostThrow .WasmVm .InvalidAction
    if let some hi := f.maxProto then
      if pm.protoVersion > hi || ledgerProto > hi then hostThrow .WasmVm .InvalidAction

/-! ## Resource limiter (budget/wasmi_helper.rs:26-126) -/

/-- `Budget::get_mem_bytes_remaining`. -/
def memBytesRemaining (b : Budget) : Nat := if b.metered then b.mem.remaining else U64MAX

/-- `charge_current_frame_linear_mem` (frame.rs:214-220). -/
def chargeCurrentFrameLinearMem (amount : Nat) : HostM Unit := do
  checkCtxBorrow
  modify fun s => match s.contexts.back? with
    | some ctx =>
      let ctx' := { ctx with linearMemCharged := satAdd ctx.linearMemCharged amount }
      { s with contexts := s.contexts.set! (s.contexts.size - 1) ctx' }
    | none => s

/-- `ResourceLimiter::memory_growing` for `Host`: `true` or an error
    (`MemoryError::OutOfBoundsGrowth`); never `false`. -/
def memoryGrowingM (cur desired : Nat) (maximum : Option Nat) : HostM Bool := do
  let limit := memBytesRemaining (← get).budget
  let delta := desired - cur
  let allow := if delta > limit then false else match maximum with
    | some mx => desired ≤ mx
    | none => true
  if !allow then throw (errV .Budget .ExceededLimit)
  charge .MemAlloc (some delta)
  let charged := (← get).budget.memoryCost .MemAlloc (some delta)
  chargeCurrentFrameLinearMem charged
  pure true

/-- Run a host computation on a state, keeping the state also on error. -/
def runHost {α} (act : HostM α) (h : HostState) : Except HErr α × HostState :=
  (ExceptT.run act).run h

/-- The limiter as seen by the interpreter: an error becomes a trap
    (`GrowthOperationLimited` while executing, memory/mod.rs:219-223). -/
def memoryGrowingIface (cur desired : Nat) (maximum : Option Nat) (h : HostState) :
    Wasm.Res HErr HostState (Bool × HostState) :=
  match runHost (memoryGrowingM cur desired maximum) h with
  | (.ok b, h') => .ok (b, h')
  | (.error _, h') => .trap (.code .GrowthOperationLimited) h'

/-- `table_growing` (wasmi_helper.rs:84-107) at instantiation: at most 1000 elements. -/
def TABLE_ELEMENTS_LIMIT : Nat := 1000

/-! ## The VM -/

structure Vm where
  contractId : ByteArray
  pm : ParsedModule
  /-- Host function bound to each function import, in import order. -/
  imports : Array Env.HostFn
  memExported : Bool
  store : Wasm.Store
  deriving Inhabited

/-- `Vm::instantiate_wasmi` (vm.rs:124-158) + `from_parsed_module_and_wasmi_linker`
    (:160-180). `syms` are the linker symbols computed by `make_wasmi_linker`. -/
def instantiateWasmi (cid : ByteArray) (pm : ParsedModule) (syms : List (String × String)) : HostM Vm := do
  checkLedgerProtocolSupported (← withLedgerInfo)
  chargeForInstantiation pm.costInputs
  checkImportsProtocol pm
  let m := pm.module
  let imports ← linkImports m syms
  if let some t := m.tables[0]? then
    if t.limits.min > TABLE_ELEMENTS_LIMIT then throw (errV .Budget .ExceededLimit)
    if let some mx := t.limits.max then
      if t.limits.min > mx then throw (errV .Budget .ExceededLimit)
  let iface : Wasm.HostIface HostState HErr :=
    { call := fun _ _ _ st h => .trap (.code .UnreachableCodeReached) (st, h),
      memoryGrowing := memoryGrowingIface }
  let h ← get
  match Wasm.Instantiate.instantiate iface m #[] h with
  | .ok (st, h') => do
    set h'
    let memExported := m.exports.any fun e => e.name == "memory" && match e.desc with
      | .mem _ => true | _ => false
    pure { contractId := cid, pm, imports, memExported, store := st }
  | .err .memoryAlloc => throw (errV .Budget .ExceededLimit)
  | .err _ => throw wasmiOtherError
  | .trap _ => throw (errV .Budget .ExceededLimit)

/-- `Vm::new_with_cost_inputs` (vm.rs:189-200). -/
def vmNew (cid : ByteArray) (wasm : ByteArray) (ci : CostInputs) : HostM Vm := do
  let pm ← parseModule wasm ci
  let syms ← chargeImportSymbols pm.module
  instantiateWasmi cid pm syms

/-! ## Fuel (vm/fuel_refillable.rs) -/

/-- `return_fuel_to_host`: charge the consumed fuel as WasmInsnExec iterations, then
    reset. If the charge fails the store keeps its fuel. -/
def returnFuelToHost (st : Wasm.Store) : HostM Wasm.Store := do
  bulkCharge .WasmInsnExec st.fuel.consumed none
  pure { st with fuel := {} }

/-- `add_fuel_to_vm`: the store must be clean; supply all remaining CPU as fuel. -/
def addFuelToVm (st : Wasm.Store) : HostM Wasm.Store := do
  if st.fuel.consumed != 0 || st.fuel.total != 0 then hostThrow .WasmVm .InternalError
  let b := (← get).budget
  let f := b.wasmiFuelRemaining
  pure { st with fuel := { total := f, remaining := f, metered := b.metered } }

end Soroban
