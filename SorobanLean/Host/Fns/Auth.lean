/-
Authorization host functions (src: soroban-env-host/src/host.rs:3567-3595).
-/
import SorobanLean.Host.FnCore

namespace Soroban
open Xdr

/-- `require_auth` (host.rs:3567-3595): the current frame's arguments, `metered_clone`d
    (a `Vec<Val>`: shallow copy plus element copies), are the authorized arguments. -/
def requireAuth : HostFnImpl := fun _ a => do
  checkCtxBorrow
  let args ← match (← get).contexts.back? with
    | some ctx => match ctx.frame with
      | .contractVM _ _ args _ _ | .stellarAsset _ _ args _ => pure args
      | .hostFunction _ => hostThrow .Context .InternalError
    | none => hostThrow .Context .InternalError
  chargeShallowCopy 1 DS.vec
  chargeVecSub args.size DS.val
  authRequireAuth a[0]! args
  pure Val.VOID

end Soroban
