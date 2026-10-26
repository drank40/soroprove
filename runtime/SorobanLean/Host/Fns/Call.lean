/-
Contract calls, the current contract's address and object comparison
(src: soroban-env-host/src/host.rs:1192-1248, :1306-1314, :2478-2512;
host/conversion.rs:192-194, host/data_helper.rs:613-635).
-/
import SorobanLean.Host.Fns.Num

namespace Soroban
open Xdr

/-- `obj_cmp` (host.rs:1192-1248). The dispatcher has already run `check_env_arg` on
    both arguments, so this is the body of `envObjCmp` without those checks. -/
def objCmp : HostFnImpl := fun _ a => do
  let (x, y) := (a[0]!, a[1]!)
  let part ← (match x.isObject, y.isObject with
    | true, true => do
        let xo ← visitObj x
        let yo ← visitObj y
        pure (some (← cmpHostObj BIG xo yo))
    | true, false => do
        let xo ← visitObj x
        compareToSmall xo y
    | false, true => do
        let yo ← visitObj y
        pure ((← compareToSmall yo x).map Ordering.swap)
    | false, false => hostThrow .Value .UnexpectedType)
  let res ← match part with
    | some r => pure r
    | none =>
      let tx := x.getTag.scValType; let ty := y.getTag.scValType
      if tx == ty then hostThrow .Value .InternalError
      else pure (compare tx ty)
  pure (rawI64 (match res with | .lt => -1 | .eq => 0 | .gt => 1))

/-- `get_current_contract_address` (host.rs:1306-1314). -/
def getCurrentContractAddress : HostFnImpl := fun _ _ => do
  let cid ← currentContractId
  addHostObject (.address (.SC_ADDRESS_TYPE_CONTRACT cid))

/-- `contract_id_from_address` (data_helper.rs:628-635): `visit_obj`, `metered_clone` of
    the `ScAddress`, then `contract_id_from_scaddress` (:613-626). -/
def contractIdFromAddress (v : Val) : HostM ByteArray := do
  let .address addr ← visitObj v | throw conversionError
  chargeShallowCopy 1 DS.ScAddress
  match addr with
  | .SC_ADDRESS_TYPE_CONTRACT cid => pure cid
  | _ => hostThrow .Object .InvalidInput

/-- `call` (host.rs:2478-2512): `call_args_from_obj` (`visit_obj` then `to_vec`, a
    metered clone of the `Vec<Val>`), then `call_n_internal` with
    `CallParams::default_external_call` (reentry prohibited). The failure event is
    diagnostics-only, so not modelled. -/
def callFn : HostFnImpl := fun r a => do
  let .vec xs ← visitObj a[2]! | throw conversionError
  chargeShallowCopy 1 DS.vec
  chargeVecSub xs.size DS.val
  let cid ← contractIdFromAddress a[0]!
  r.callContract cid a[1]! xs

end Soroban
