/-
Frames, contexts and rollback (src: soroban-env-host/src/host/frame.rs:200-600,
:1196-1340; auth.rs:1455-1700; storage.rs:24-53 `InstanceStorageMap`;
events/internal.rs:197-205).
-/
import SorobanLean.Host.Vm
import SorobanLean.Host.Auth

namespace Soroban
open Xdr

/-! ## Contexts (frame.rs:200-262) -/

structure RollbackPoint where
  storage : Array (LedgerKey × Option SEntry)
  events : Nat
  auth : AuthSnapshot
  deriving Inhabited

/-- `push_context` (frame.rs:222-235). -/
def pushContext (ctx : Context) : HostM RollbackPoint := do
  let auth ← authPushFrame ctx.frame
  let storage ← cloneStorageMap (← get).storage.map
  let events := (← get).events.size
  chargeBulkInitCpy DS.vec DS.Context 1
  checkCtxBorrow
  modify fun s => { s with contexts := s.contexts.push ctx }
  pure { storage, events, auth }

/-- `pop_context` (frame.rs:237-262). -/
def popContext (orp : Option RollbackPoint) : HostM Context := do
  checkCtxBorrow
  let ctx? := (← get).contexts.back?
  modify fun s => { s with contexts := s.contexts.pop }
  let mut snap := none
  if let some rp := orp then
    modify fun s => { s with storage := { s.storage with map := rp.storage },
                             events := (s.events.mapIdx fun i e =>
                               if i ≥ rp.events then { e with failedCall := true } else e) }
    snap := some rp.auth
  authPopFrame snap
  let some ctx := ctx? | hostThrow .Context .InternalError
  if ctx.linearMemCharged != 0 then
    modify fun s => { s with budget := s.budget.refundMem ctx.linearMemCharged }
  pure ctx

def Frame.contractId? : Frame → Option ByteArray
  | .contractVM cid .. | .stellarAsset cid .. => some cid
  | .hostFunction _ => none

def Frame.instance? : Frame → Option SCContractInstance
  | .contractVM _ _ _ inst _ | .stellarAsset _ _ _ inst => some inst
  | .hostFunction _ => none

/-- `get_current_contract_id_opt_internal` (frame.rs:588-600). -/
def currentContractIdOpt : HostM (Option ByteArray) := do
  checkCtxBorrow
  match (← get).contexts.back? with
  | none => pure none
  | some ctx => match ctx.frame.contractId? with
    | some cid => do chargeShallowCopy 1 DS.ContractId; pure (some cid)
    | none => pure none

def currentContractId : HostM ByteArray := do
  match ← currentContractIdOpt with
  | some c => pure c
  | none => hostThrow .Context .InternalError

/-! ## Instance storage (storage.rs:24-53, frame.rs:1269-1340) -/

def instanceMapOps : MMapOps Val Val :=
  { entrySize := DS.pair DS.val DS.val, kcmp := cmpVal BIG }

/-- `InstanceStorageMap::from_instance_xdr` (storage.rs:34-52). -/
def instanceStorageFromXdr (inst : SCContractInstance) : HostM InstanceStorage := do
  let kvs ← match inst.storage with
    | none => pure #[]
    | some m => do
      chargeBulkInitCpy (DS.vec + DS.HostError) (DS.pair DS.val DS.val + DS.HostError) m.size
      let mut out := #[]
      for e in m do
        let k ← toValidHostVal e.key
        let v ← toValidHostVal e.val
        out := out.push (k, v)
      pure out
  let map ← MMap.fromMap instanceMapOps kvs
  pure { map, isModified := false }

/-- `maybe_init_instance_storage` (frame.rs:1269-1284). -/
def maybeInitInstanceStorage (ctx : Context) : HostM Context := do
  if ctx.storage.isSome then return ctx
  let some inst := ctx.frame.instance? | hostThrow .Context .InternalError
  let st ← instanceStorageFromXdr inst
  pure { ctx with storage := some st }

/-- Write the (possibly just initialised) top context back while still borrowed, so
    that in-place initialisation survives a later failure of the callback. -/
def setTopContext (ctx : Context) : HostM Unit :=
  modify fun s => { s with contexts := s.contexts.set! (s.contexts.size - 1) ctx }

/-- `with_instance_storage` (data_helper.rs:36-50). -/
def withInstanceStorage {α} (f : InstanceStorage → HostM α) : HostM α :=
  withCurrentContext fun ctx => do
    let ctx ← maybeInitInstanceStorage ctx
    setTopContext ctx
    let some st := ctx.storage | hostThrow .Context .InternalError
    pure (← f st, ctx)

/-- `with_mut_instance_storage` (data_helper.rs:52-69): marks the storage modified
    before running `f`. -/
def withMutInstanceStorage {α} (f : InstanceStorage → HostM (α × InstanceStorage)) : HostM α :=
  withCurrentContext fun ctx => do
    let ctx ← maybeInitInstanceStorage ctx
    let some st := ctx.storage | hostThrow .Context .InternalError
    let st := { st with isModified := true }
    -- the storage is marked modified in place even if `f` fails
    setTopContext { ctx with storage := some st }
    let (a, st') ← f st
    pure (a, { ctx with storage := some st' })

/-- `persist_instance_storage` (frame.rs:1312-1337). -/
def persistInstanceStorage : HostM Bool := do
  let upd ← withCurrentContext fun ctx => do
    match ctx.storage with
    | some st => if !st.isModified then pure (none, ctx) else
        pure (some (← instanceStorageMapToScMap st.map), ctx)
    | none => pure (none, ctx)
  match upd with
  | some m => do
    let cid ← currentContractId
    let key ← contractInstanceLedgerKey cid
    storeContractInstance none (some m) cid key
    pure true
  | none => pure false

/-- `reload_instance_storage` (frame.rs:1286-1298). -/
def reloadInstanceStorage (ctx : Context) : HostM Context := do
  let some cid := ctx.frame.contractId? | hostThrow .Context .InternalError
  let key ← contractInstanceLedgerKey cid
  let inst ← retrieveContractInstance key
  pure { ctx with storage := some (← instanceStorageFromXdr inst) }

/-- `maybe_reload_instance_storage_on_frame_pop` (frame.rs:1300-1310). The context
    stack is mutably borrowed throughout: contexts reloaded so far are written back as
    they are processed. -/
def maybeReloadInstanceStorageOnFramePop : HostM Unit := do
  checkCtxBorrow
  let cs := (← get).contexts
  let some cur := cs.back?.bind (·.frame.contractId?) | hostThrow .Context .InternalError
  for i in [0:cs.size - 1] do
    let ctx := (← get).contexts[i]!
    if ctx.frame.contractId? == some cur then
      let ctx' ← withCtxBorrowMut (reloadInstanceStorage ctx)
      modify fun s => { s with contexts := s.contexts.set! i ctx' }

/-! ## `with_frame` (frame.rs:443-586) -/

/-- `DEFAULT_HOST_DEPTH_LIMIT` (budget/limits.rs). -/
def HOST_DEPTH_LIMIT : Nat := 100

def isErrorVal (v : Val) : Bool := v.getTag == .Error

def withFrameMem (linearMem : Nat) (frame : Frame) (body : HostM Val) : HostM Val := do
  let startDepth := (← get).contexts.size
  if startDepth ≥ HOST_DEPTH_LIMIT then hostThrow .Context .ExceededLimit
  let rp ← pushContext { frame, linearMemCharged := linearMem }
  let res ← tryCatch (Except.ok <$> body) (fun e => pure (Except.error e))
  -- Ok(Error) escalation (frame.rs:517-540)
  let res : Except HErr Val := match res with
    | .ok v => if isErrorVal v then
        (if v.getMinor == ScErrorType.Contract.toU32 then .error v else .error (errV .Context .InvalidAction))
      else .ok v
    | e => e
  let res ← match res with
    | .ok v => do
      let r ← tryCatch (do
          let persisted ← persistInstanceStorage
          if persisted then maybeReloadInstanceStorageOnFramePop
          pure (Except.ok v)) (fun e => pure (Except.error e))
      pure r
    | e => pure e
  match res with
  | .error _ => discard <| popContext (some rp)
  | .ok _ => discard <| popContext none
  if (← get).contexts.size != startDepth then hostThrow .Context .InternalError
  match res with
  | .ok v => pure v
  | .error e => throw e

def withFrame (frame : Frame) (body : HostM Val) : HostM Val := withFrameMem 0 frame body

end Soroban
