/-
Contract invocation (src: soroban-env-host/src/host/frame.rs:860-1257, vm.rs:241-412,
soroban-env-common/src/symbol.rs:107-122, :354-376; host.rs:964-1009, :2830-2837;
host/mem_helper.rs:231-342).

All recursion (contract → host function → contract) is structural on a Lean-only
gas `n`: `callNInternal (n+1)` runs its VM with host functions whose nested calls use
`callNInternal n`. Exhausting it raises `gasOutErr`, never a real host error.
-/
import SorobanLean.Host.Dispatch

namespace Soroban
open Xdr

/-- Lean-only marker: the Lean gas was exhausted (tag byte `Bad`). -/
def gasOutErr : HErr := ⟨0xFFFF_FFFF_FFFF_FE7F⟩

/-! ## VM invocation (vm.rs:241-412) -/

/-- Translate an interpreter outcome to a host result, as `metered_func_call` does
    after returning the fuel (vm.rs:296-350). -/
def vmOutcomeError : Wasm.Trap HErr → HErr
  | .code c => trapCodeError c
  | .host e => e

structure CallParams where
  /-- `ContractReentryMode`: 0 Prohibited, 1 SelfAllowed, 2 Allowed. -/
  reentry : Nat := 0
  internalHostCall : Bool := false
  treatMissingAsNoop : Bool := false

def CallParams.defaultExternal : CallParams := {}

mutual
/-- `call_n_internal` (frame.rs:1105-1195). -/
def callNInternal : Nat → ByteArray → Val → Array Val → CallParams → HostM Val
  | 0, _, _, _, _ => throw gasOutErr
  | n + 1, id, func, args, cp => do
    if !cp.internalHostCall then
      let s ← symbolStr func
      if s.size ≥ 2 && s[0]! == '_'.toNat.toUInt8 && s[1]! == '_'.toNat.toUInt8 then
        hostThrow .Context .InvalidAction
    if cp.reentry != 2 then
      checkCtxBorrow
      let ids := ((← get).contexts.toList.reverse.filterMap (·.frame.contractId?))
      match ids.findIdx? (· == id), cp.reentry with
      | none, _ => pure ()
      | some 0, 1 => discard persistInstanceStorage
      | some _, _ => hostThrow .Context .InvalidAction
    callContractFn n id func args cp.treatMissingAsNoop
/-- `call_contract_fn` (frame.rs:860-930) + `instantiate_vm` without a module cache
    (:932-990). -/
def callContractFn : Nat → ByteArray → Val → Array Val → Bool → HostM Val
  | 0, _, _, _, _ => throw gasOutErr
  | n + 1, id, func, args, noop => do
    let key ← contractInstanceLedgerKey id
    let inst ← retrieveContractInstance key
    chargeBulkInitCpy DS.vec DS.val args.size
    let wasmHash ← match inst.executable with
      | .CONTRACT_EXECUTABLE_WASM h => pure h
      | .CONTRACT_EXECUTABLE_EXTERNAL_REF _ => unsupported   -- TODO(M5)
      | .CONTRACT_EXECUTABLE_STELLAR_ASSET => unsupported    -- TODO(M5): built-in SAC
    checkCtxBorrow
    let callerMark := ((← get).contexts.back?.map (·.linearMemCharged)).getD 0
    chargeShallowCopy 1 DS.ContractId
    let (code, costs) ← retrieveWasm wasmHash
    let vm ← vmNew id code costs
    -- `reclaim_frame_linear_mem_since(caller_mark)` (frame.rs:202-212)
    checkCtxBorrow
    let vmMem ← match (← get).contexts.back? with
      | some ctx => do
        let d := ctx.linearMemCharged - callerMark
        modify fun s => { s with contexts := s.contexts.set! (s.contexts.size - 1)
                                                  { ctx with linearMemCharged := callerMark } }
        pure d
      | none => pure 0
    withFrameMem vmMem (.contractVM id func args inst #[])
      (invokeFunctionRaw n vm func args noop)
/-- `invoke_function_raw` (vm.rs:393-412) + `metered_func_call` (:241-355). -/
def invokeFunctionRaw : Nat → Vm → Val → Array Val → Bool → HostM Val
  | 0, _, _, _, _ => throw gasOutErr
  | n + 1, vm, func, args, noop => do
    chargeBulkInitCpy DS.vec DS.Value args.size
    let mut inputs := #[]
    for a in args do inputs := inputs.push (Wasm.Value.i64 (← absoluteToRelative a).payload)
    charge .InvokeVmFunction none
    let fname ← symbolStr func
    let m := vm.pm.module
    let exp := m.exports.find? (fun e => e.name.toUTF8 == fname)
    let some e := exp
      | if noop then return Val.VOID else hostThrow .WasmVm .MissingValue
    let .func fi := e.desc | hostThrow .WasmVm .UnexpectedType
    if inputs.size > MAX_VM_ARGS then hostThrow .WasmVm .InvalidInput
    let st ← addFuelToVm vm.store
    -- `Func::call` type checks (func/mod.rs:462-478): parameters, then result count
    let ft := (m.funcTypeIdx? fi).bind (m.types[·]?) |>.getD default
    let callRes : Except HErr (List Wasm.Value) × Wasm.Store ←
      if ft.params.length != inputs.size then pure (Except.error (errV .WasmVm .UnexpectedSize), st)
      else if ft.params.any (· != .i64) then pure (Except.error (errV .WasmVm .UnexpectedType), st)
      else if ft.results.length != 1 then pure (Except.error (errV .WasmVm .UnexpectedSize), st)
      else do
        let rec_ : Rec := { callContract := fun id f as => callNInternal n id f as {} }
        let iface : Wasm.HostIface HostState HErr :=
          { call := fun _ f as st h => dispatch rec_ vm.imports vm.memExported f as st h,
            memoryGrowing := memoryGrowingIface }
        let cx := Wasm.Instantiate.mkCtx iface m (← get).budget.fuelCosts
        match Wasm.Exec.invoke cx n fi inputs.toList st (← get) with
        | .ok (rs, st', h') => do set h'; pure (Except.ok rs, st')
        | .trap t (st', h') => do set h'; pure (Except.error (vmOutcomeError t), st')
        | .gasOut => throw gasOutErr
    let (r, st) := callRes
    discard <| returnFuelToHost st
    let rs : List Wasm.Value ← match r with | .ok rs => pure rs | .error e => throw e
    match rs with
    | [.i64 x] =>
      let v : Val := ⟨x⟩
      if !v.isGood then throw conversionError
      relativeToAbsolute v
    | _ => throw conversionError
end

/-- `invoke_function_and_return_val` for `InvokeContract` (frame.rs:1198-1222). -/
def invokeContract (n : Nat) (a : InvokeContractArgs) : HostM Val :=
  withFrame (.hostFunction .HOST_FUNCTION_TYPE_INVOKE_CONTRACT) do
    let .SC_ADDRESS_TYPE_CONTRACT cid := a.contractAddress | hostThrow .Value .UnexpectedType
    let fn ← symbolFromBytes a.functionName
    let args ← scvalsToValVec a.args
    callNInternal n cid fn args CallParams.defaultExternal

/-- `Host::invoke_function` (frame.rs:1259-1267). -/
def invokeFunction (n : Nat) (hf : HostFunction) : HostM SCVal := do
  let rv ← match hf with
    | .HOST_FUNCTION_TYPE_INVOKE_CONTRACT a => invokeContract n a
    | _ => unsupported   -- TODO(M5): create contract, upload
  fromHostVal rv

end Soroban
