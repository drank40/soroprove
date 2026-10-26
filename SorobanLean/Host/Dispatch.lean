/-
Host functions and their dispatch from Wasm (src: soroban-env-host/src/vm/dispatch.rs,
host.rs `impl VmCallerEnv for Host`, host/data_helper.rs, host/conversion.rs:131-165).
-/
import SorobanLean.Host.Fns.Ledger
import SorobanLean.Host.Fns.Num
import SorobanLean.Host.Fns.Mem
import SorobanLean.Host.Fns.Event
import SorobanLean.Host.Fns.Auth
import SorobanLean.Host.Fns.Call

namespace Soroban
open Xdr

/-! ## The host function table -/

def hostFnImpl : Env.HostFn → Option HostFnImpl
  | .put_contract_data => some putContractData
  | .has_contract_data => some hasContractData
  | .get_contract_data => some getContractData
  | .del_contract_data => some delContractData
  | .extend_contract_data_ttl => some extendContractDataTtl
  | .extend_current_contract_instance_and_code_ttl => some extendCurrentContractInstanceAndCodeTtl
  | .obj_from_u64 => some objFromU64
  | .obj_to_u64 => some objToU64
  | .obj_from_i128_pieces => some objFromI128Pieces
  | .obj_to_i128_lo64 => some objToI128Lo64
  | .obj_to_i128_hi64 => some objToI128Hi64
  | .get_ledger_sequence => some getLedgerSequence
  | .get_address_from_muxed_address => some getAddressFromMuxed
  | .get_id_from_muxed_address => some getIdFromMuxed
  | .contract_event => some contractEvent
  | .require_auth => some requireAuth
  | .call => some callFn
  | .obj_cmp => some objCmp
  | .get_current_contract_address => some getCurrentContractAddress
  | .vec_new_from_linear_memory => some vecNewFromLinearMemory
  | .symbol_new_from_linear_memory => some symbolNewFromLinearMemory
  | .map_new_from_linear_memory => some (mapNewFromLinearMemory false)
  | .sparse_map_new_from_linear_memory => some (mapNewFromLinearMemory true)
  | .map_unpack_to_linear_memory => some (mapUnpackToLinearMemory false)
  | .sparse_map_unpack_to_linear_memory => some (mapUnpackToLinearMemory true)
  | _ => none

/-! ## Dispatch (dispatch.rs:206-290) -/

/-- `check_protocol_version_{lower,upper}_bound` (host.rs:1113-1143). -/
def checkProtoBounds (f : Env.HostFn) : HostM Unit := do
  let p := (← withLedgerInfo).protocolVersion
  if let some lo := f.minProto then if p < lo then hostThrow .Context .IndexBounds
  if let some hi := f.maxProto then if p > hi then hostThrow .Context .IndexBounds

def callerStore : HostM Wasm.Store := do
  match (← get).vmCaller with
  | some c => pure c.store
  | none => hostThrow .Context .InternalError

def setCallerStore (st : Wasm.Store) : HostM Unit :=
  modify fun s => { s with vmCaller := s.vmCaller.map ({ · with store := st }) }

/-- Marshal one argument (`try_marshal_from_relative_value` then `check_env_arg`). -/
def marshalArg (t : Env.ValTy) (raw : UInt64) : HostM Val := do
  if !t.tryMarshal raw then throw marshalError
  let v : Val := ⟨raw⟩
  if t.isRaw then return v
  let v ← relativeToAbsolute v
  checkValIntegrity v
  pure v

/-- The dispatch body on the host side, with the caller's store installed in
    `vmCaller`: everything from the protocol guard to re-fuelling the VM. -/
def dispatchM (rec : Rec) (f : Env.HostFn) (args : List Wasm.Value) : HostM UInt64 := do
  checkProtoBounds f
  setCallerStore (← returnFuelToHost (← callerStore))
  charge .DispatchHostFunction none
  let tys := f.args.map (·.2)
  let mut vals := #[]
  for (t, a) in tys.zip args do
    let raw := match a with | .i64 x => x | .i32 x => x.toUInt64
    vals := vals.push (← marshalArg t raw)
  let res ← tryCatch (do
      let some impl := hostFnImpl f | unsupported
      let r ← impl rec vals
      -- `ok.check_env_arg` then `marshal_relative_from_self`
      let rt := f.ret
      if rt.isRaw then pure (Except.ok r.payload) else
        checkValIntegrity r
        let r ← absoluteToRelative r
        pure (Except.ok r.payload)) (fun e => pure (Except.error e))
  setCallerStore (← addFuelToVm (← callerStore))
  match res with
  | .ok x => pure x
  | .error e => throw e

/-- The interpreter-facing host call for a VM with the given import table. The
    previous `vmCaller` (an outer VM, if any) is restored afterwards. -/
def dispatch (rec : Rec) (imports : Array Env.HostFn) (memExported : Bool)
    (fi : Nat) (args : List Wasm.Value) (st : Wasm.Store) (h : HostState) :
    Wasm.Res HErr (Wasm.Store × HostState) (List Wasm.Value × Wasm.Store × HostState) :=
  let prev := h.vmCaller
  let h := { h with vmCaller := some { store := st, memExported } }
  match imports[fi]? with
  | none => .trap (.code .UnreachableCodeReached) (st, { h with vmCaller := prev })
  | some f =>
    let (r, h') := runHost (dispatchM rec f args) h
    let st' := (h'.vmCaller.map (·.store)).getD st
    let h' := { h' with vmCaller := prev }
    match r with
    | .ok x => .ok ([.i64 x], st', h')
    | .error e => .trap (.host e) (st', h')

end Soroban
