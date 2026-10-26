/-
The authorization manager in enforcing mode (src: soroban-env-host/src/auth.rs:697-1000,
:1118-1300, :1437-1730, :1862-2091, :2346-2420, :2474-2600, :2665-2723, :2836-2956;
host.rs:513-521 `source_account_address`).

Modelled exactly: authorization entries with transaction-source-account credentials,
invocation trees and their matching, invoker-contract trackers, frame push/pop,
snapshots and rollback (with their metering). Raising `unsupportedErr` for now:
authentication of `Address` credentials (nonces, ed25519 / `__check_auth`) and
delegated-account signers.
-/
import SorobanLean.Host.Symbol
import SorobanLean.Host.Storage

namespace Soroban
open Xdr

/-! ## Comparisons (auth.rs:697-743, soroban-env-common/src/symbol.rs:140-158) -/

/-- `Compare<Symbol> for E`: by tag, then small symbols by their characters, objects
    through `Compare<Val>`. -/
def cmpSymbol (a b : Val) : HostM Ordering := do
  let ta := a.getTag.toU8; let tb := b.getTag.toU8
  if ta < tb then return .lt
  if ta > tb then return .gt
  if a.getTag == .SymbolSmall then
    return Ord.lexBytes (symbolSmallBytes a.getBody) (symbolSmallBytes b.getBody)
  cmpVal BIG a b

/-- `Compare<CreateContractArgsV2> for Budget` (comparison.rs:261-282). -/
def cmpCreateContractArgsV2 (a b : CreateContractArgsV2) : HostM Ordering :=
  thenM (cmpFixed DS.ContractIdPreimage (Ord.cmp_ContractIDPreimage a.contractIDPreimage b.contractIDPreimage)) fun _ =>
  thenM (cmpFixed DS.ContractExecutable (Ord.cmp_ContractExecutable a.executable b.executable)) fun _ =>
  cmpScVals BIG a.constructorArgs.toList b.constructorArgs.toList

/-- `Compare<AuthorizedFunction> for Host` (auth.rs:718-743). -/
def cmpAuthFn (a b : AuthFn) : HostM Ordering :=
  match a, b with
  | .contractFn a1 f1 x1, .contractFn a2 f2 x2 =>
    thenM (cmpVal BIG a1 a2) fun _ => thenM (cmpSymbol f1 f2) fun _ => cmpValList BIG x1.toList x2.toList
  | .createContractHostFn c1, .createContractHostFn c2 => cmpCreateContractArgsV2 c1 c2
  | .contractFn .., .createContractHostFn _ => pure .lt
  | .createContractHostFn _, .contractFn .. => pure .gt

/-! ## From XDR (auth.rs:767-830, :1862-1873, :2346-2412) -/

/-- `AuthorizedFunction::from_xdr` (auth.rs:768-790). -/
def AuthFn.fromXdr (f : SorobanAuthorizedFunction) : HostM AuthFn := do
  match f with
  | .SOROBAN_AUTHORIZED_FUNCTION_TYPE_CONTRACT_FN c =>
    let addr ← addHostObject (.address c.contractAddress)
    let fn ← symbolFromBytes c.functionName
    let args ← scvalsToValVec c.args
    pure (.contractFn addr fn args)
  | .SOROBAN_AUTHORIZED_FUNCTION_TYPE_CREATE_CONTRACT_HOST_FN c =>
    pure (.createContractHostFn { contractIDPreimage := c.contractIDPreimage, executable := c.executable,
                                  constructorArgs := #[] })
  | .SOROBAN_AUTHORIZED_FUNCTION_TYPE_CREATE_CONTRACT_V2_HOST_FN c => pure (.createContractHostFn c)

/-- `AuthorizedInvocation::from_xdr` (auth.rs:812-828): the sub-invocations are
    converted (in order) before the function. -/
def AuthInv.fromXdr : Nat → SorobanAuthorizedInvocation → HostM AuthInv
  | 0, _ => hostThrow .Context .InternalError
  | fu + 1, x => do
    chargeBulkInitCpy (DS.vec + DS.HostError) (DS.AuthorizedInvocation + DS.HostError) x.subInvocations.size
    let mut subs := #[]
    for s in x.subInvocations do subs := subs.push (← AuthInv.fromXdr fu s)
    let f ← AuthFn.fromXdr x.function
    pure (.mk f subs false)

/-- `Host::source_account_address` (host.rs:513-521). -/
def sourceAccountAddress : HostM (Option Val) := do
  match (← get).sourceAccount with
  | some acc => do
    chargeShallowCopy 1 DS.AccountId
    some <$> addHostObject (.address (.SC_ADDRESS_TYPE_ACCOUNT acc))
  | none => pure none

/-- `AccountAuthorizationTracker::from_authorization_entry` (auth.rs:2347-2412). -/
def AccountTracker.fromEntry (e : SorobanAuthorizationEntry) : HostM AccountTracker := do
  let (address, nonce, signature, credentials) ← match e.credentials with
    | .SOROBAN_CREDENTIALS_SOURCE_ACCOUNT => do
      let some a ← sourceAccountAddress | hostThrow .Auth .InternalError
      pure (a, none, Val.VOID, AuthCredentials.sourceAccount)
    | .SOROBAN_CREDENTIALS_ADDRESS c => do
      let a ← addHostObject (.address c.address)
      let sig ← toHostVal BIG c.signature
      pure (a, some (c.nonce.toInt, c.signatureExpirationLedger.toNat), sig, AuthCredentials.address)
    | .SOROBAN_CREDENTIALS_ADDRESS_V2 c => do
      let a ← addHostObject (.address c.address)
      let sig ← toHostVal BIG c.signature
      pure (a, some (c.nonce.toInt, c.signatureExpirationLedger.toNat), sig, AuthCredentials.addressV2)
    | .SOROBAN_CREDENTIALS_ADDRESS_WITH_DELEGATES _ => unsupported   -- TODO: delegated signers
  let root ← AuthInv.fromXdr BIG e.rootInvocation
  pure { address, inv := { root }, signature, credentials, nonce }

/-- `AuthorizationManager::new_enforcing` (auth.rs:945-965). -/
def authManagerEnforcing (entries : Array SorobanAuthorizationEntry) : HostM AuthManager := do
  chargeBulkInitCpy DS.vec (DS.refCell DS.AccountAuthorizationTracker) entries.size
  let mut ts := #[]
  for e in entries do ts := ts.push (← AccountTracker.fromEntry e)
  pure { accountTrackers := ts }

/-! ## Snapshots and rollback (auth.rs:903-932, :1460-1595, :2074-2090, :2836-2897) -/

/-- `AuthorizedInvocation::snapshot` (auth.rs:903-915). -/
def AuthInv.snapshot : Nat → AuthInv → HostM AuthInvSnapshot
  | 0, _ => hostThrow .Context .InternalError
  | fu + 1, .mk _ subs ex => do
    chargeBulkInitCpy (DS.vec + DS.HostError) (DS.AuthorizedInvocationSnapshot + DS.HostError) subs.size
    let mut out := #[]
    for s in subs do out := out.push (← AuthInv.snapshot fu s)
    pure (.mk ex out)

/-- `AuthorizedInvocation::rollback` (auth.rs:917-932). -/
def AuthInv.rollback : Nat → AuthInv → AuthInvSnapshot → Except HErr AuthInv
  | 0, _, _ => .error (errV .Context .InternalError)
  | fu + 1, .mk f subs _, .mk ex snaps => do
    if subs.size != snaps.size then throw (errV .Auth .InternalError)
    let mut out := #[]
    for h : i in [0:subs.size] do
      out := out.push (← AuthInv.rollback fu subs[i] snaps[i]!)
    pure (.mk f out ex)

/-- `InvocationTracker::rollback` (auth.rs:2079-2089). -/
def InvocationTracker.rollback (t : InvocationTracker) (s : AuthInvSnapshot) : Except HErr InvocationTracker := do
  let root ← AuthInv.rollback BIG t.root s
  if !root.exhausted then pure { t with root, rootExhaustedFrame := none, isFullyProcessed := false }
  else pure { t with root }

/-- `AccountAuthorizationTrackerSnapshot` (auth.rs:640-646) without delegated signers. -/
structure AccountTrackerSnapshot where
  root : AuthInvSnapshot
  verified : Bool
  deriving Inhabited

/-- `AuthorizationManagerSnapshot` (auth.rs:298-305), enforcing mode. -/
structure AuthSnapshot where
  accountTrackers : Array (Option AccountTrackerSnapshot)
  invokerRoots : Array AuthInvSnapshot
  deriving Inhabited

/-- `AuthorizationManager::snapshot` (auth.rs:1460-1510). -/
def authSnapshot : HostM AuthSnapshot := do
  let am := (← get).auth
  chargeBulkInitCpy DS.vec (DS.option DS.AccountAuthorizationTrackerSnapshot) am.accountTrackers.size
  let mut accs := #[]
  for t in am.accountTrackers do
    if t.borrowed then accs := accs.push none
    else
      if t.credentials == .addressWithDelegates then unsupported
      let r ← AuthInv.snapshot BIG t.inv.root
      accs := accs.push (some { root := r, verified := t.verified })
  chargeBulkInitCpy (DS.vec + DS.HostError) (DS.AuthorizedInvocationSnapshot + DS.HostError) am.invokerTrackers.size
  let mut invs := #[]
  for t in am.invokerTrackers do invs := invs.push (← AuthInv.snapshot BIG t.inv.root)
  pure { accountTrackers := accs, invokerRoots := invs }

def liftExcept {α} (r : Except HErr α) : HostM α :=
  match r with | .ok a => pure a | .error e => throw e

def setAuth (am : AuthManager) : HostM Unit := modify fun s => { s with auth := am }

/-- `AuthorizationManager::rollback` (auth.rs:1514-1595). -/
def authRollback (snap : AuthSnapshot) : HostM Unit := do
  let am := (← get).auth
  if am.accountTrackers.size != snap.accountTrackers.size then hostThrow .Auth .InternalError
  let mut accs := am.accountTrackers
  for h : i in [0:accs.size] do
    let some sopt := snap.accountTrackers[i]? | hostThrow .Auth .InternalError
    if let some s := sopt then
      let t := accs[i]!
      if t.borrowed then hostThrow .Auth .InternalError
      let inv ← liftExcept (t.inv.rollback s.root)
      accs := accs.set! i { t with inv, verified := s.verified }
  setAuth { am with accountTrackers := accs }
  let am := (← get).auth
  if am.invokerTrackers.size < snap.invokerRoots.size then hostThrow .Auth .InternalError
  let mut invs := am.invokerTrackers.extract 0 snap.invokerRoots.size
  for h : i in [0:invs.size] do
    let t := invs[i]!
    let inv ← liftExcept (t.inv.rollback snap.invokerRoots[i]!)
    invs := invs.set! i { t with inv }
  setAuth { am with invokerTrackers := invs }

/-! ## Frames (auth.rs:1598-1730, :1928-1945) -/

/-- `InvocationTracker::push_frame` (auth.rs:1928-1933). -/
def InvocationTracker.pushFrame (t : InvocationTracker) : HostM InvocationTracker := do
  chargeBulkInitCpy DS.vec DS.usize 1
  pure { t with matchStack := t.matchStack.push .unmatched }

/-- `InvocationTracker::pop_frame` (auth.rs:1935-1943). -/
def InvocationTracker.popFrame (t : InvocationTracker) : InvocationTracker :=
  let ms := t.matchStack.pop
  match t.rootExhaustedFrame with
  | some f => if f ≥ ms.size then { t with matchStack := ms, isFullyProcessed := true } else { t with matchStack := ms }
  | none => { t with matchStack := ms }

/-- `push_tracker_frame` (auth.rs:1598-1614): borrowed account trackers are skipped. -/
def pushTrackerFrame : HostM Unit := do
  let am := (← get).auth
  let mut accs := am.accountTrackers
  for h : i in [0:accs.size] do
    let t := accs[i]!
    if !t.borrowed then accs := accs.set! i { t with inv := ← t.inv.pushFrame }
  setAuth { am with accountTrackers := accs }
  let am := (← get).auth
  let mut invs := am.invokerTrackers
  for h : i in [0:invs.size] do
    let t := invs[i]!
    invs := invs.set! i { t with inv := ← t.inv.pushFrame }
  setAuth { am with invokerTrackers := invs }

/-- `AuthorizationManager::push_frame` (auth.rs:1631-1665). -/
def authPushFrame (f : Frame) : HostM AuthSnapshot := do
  match f with
  | .hostFunction _ => authSnapshot
  | .contractVM cid fnName .. | .stellarAsset cid fnName .. => do
    chargeShallowCopy 1 DS.ContractId
    let addr ← addHostObject (.address (.SC_ADDRESS_TYPE_CONTRACT cid))
    chargeBulkInitCpy DS.vec DS.ContractInvocation 1
    modify fun s => { s with auth := { s.auth with callStack := s.auth.callStack.push (.contract addr fnName) } }
    pushTrackerFrame
    authSnapshot

/-- `AuthorizationManager::pop_frame` (auth.rs:1667-1722). -/
def authPopFrame (snap : Option AuthSnapshot) : HostM Unit := do
  if let some sn := snap then authRollback sn
  let am := (← get).auth
  if am.callStack.isEmpty then return
  let accs := am.accountTrackers.map fun t => if t.borrowed then t else { t with inv := t.inv.popFrame }
  let invs := am.invokerTrackers.map fun t => { t with inv := t.inv.popFrame }
  -- drop invoker trackers that went out of scope, from the top
  let mut n := invs.size
  for _ in [0:invs.size] do
    if n > 0 && invs[n-1]!.inv.matchStack.isEmpty then n := n - 1 else break
  setAuth { callStack := am.callStack.pop, accountTrackers := accs, invokerTrackers := invs.extract 0 n }

/-! ## Matching (auth.rs:1897-2029) -/

/-- `AuthorizedInvocation::last_authorized_invocation_mut` (auth.rs:872-901): the path
    of sub-invocation indices below the root, following `SubMatch`es after position `start`. -/
def subPath (ms : Array MatchState) (start : Nat) : Except HErr (List Nat) := do
  let mut path := []
  for i in [start:ms.size] do
    match ms[i]! with
    | .sub k => path := path ++ [k]
    | .root => throw (errV .Auth .InternalError)
    | .unmatched => pure ()
  pure path

/-- `InvocationTracker::last_authorized_invocation_mut` (auth.rs:1907-1926): `none` if no
    frame matched the root yet. -/
def InvocationTracker.lastPath (t : InvocationTracker) : Except HErr (Option (List Nat)) := do
  for h : i in [0:t.matchStack.size] do
    match t.matchStack[i] with
    | .root => return some (← subPath t.matchStack (i + 1))
    | .sub _ => throw (errV .Auth .InternalError)
    | .unmatched => pure ()
  pure none

/-- The invocation node at `path` (sub-invocation indices). -/
def AuthInv.at? : AuthInv → List Nat → Option AuthInv
  | n, [] => some n
  | .mk _ subs _, k :: ks => subs[k]?.bind (·.at? ks)

/-- Update the node at `path`. -/
def AuthInv.modifyAt : Nat → AuthInv → List Nat → (AuthInv → AuthInv) → Option AuthInv
  | 0, _, _, _ => none
  | _ + 1, n, [], g => some (g n)
  | fu + 1, .mk f subs ex, k :: ks, g => do
    let c ← subs[k]?
    let c' ← AuthInv.modifyAt fu c ks g
    pure (.mk f (subs.set! k c') ex)

def AuthInv.setExhausted : AuthInv → AuthInv | .mk f s _ => .mk f s true

/-- `InvocationTracker::maybe_extend_invocation_match` (auth.rs:1972-2029). -/
def InvocationTracker.maybeExtend (t : InvocationTracker) (fn : AuthFn) (allowRoot : Bool) :
    HostM (Bool × InvocationTracker) := do
  if t.matchStack.isEmpty then hostThrow .Auth .InternalError
  if (t.matchStack.back?.map (·.isMatched)).getD false then return (false, t)
  let mut st := MatchState.unmatched
  let mut t := t
  match ← liftExcept t.lastPath with
  | some path =>
    let some cur := t.root.at? path | hostThrow .Auth .InternalError
    for h : k in [0:cur.subs.size] do
      let s := cur.subs[k]
      -- `!is_exhausted && compare(..)` short-circuits: no comparison for exhausted
      -- sub-invocations (a `(← ..)` inside `&&` would run unconditionally).
      if s.exhausted then continue
      if (← cmpAuthFn s.function fn) == .eq then
        st := .sub k
        let some root' := AuthInv.modifyAt BIG t.root (path ++ [k]) AuthInv.setExhausted
          | hostThrow .Auth .InternalError
        t := { t with root := root' }
        break
  | none =>
    if !t.root.exhausted && allowRoot then
      if (← cmpAuthFn t.root.function fn) == .eq then
        st := .root
        t := { t with root := t.root.setExhausted, rootExhaustedFrame := some (t.matchStack.size - 1) }
  if st.isMatched then
    t := { t with matchStack := t.matchStack.set! (t.matchStack.size - 1) st }
  pure (st.isMatched, t)

def InvocationTracker.isActive (t : InvocationTracker) : Bool := t.root.exhausted && !t.isFullyProcessed
def InvocationTracker.currentFrameMatched (t : InvocationTracker) : Bool :=
  (t.matchStack.back?.map (·.isMatched)).getD false

/-! ## `require_auth` (auth.rs:1118-1300, :1437-1456, :2474-2526, :2586-2723) -/

/-- `AuthStackFrame::to_authorized_function` (auth.rs:745-765). -/
def AuthStackFrame.toAuthFn (f : AuthStackFrame) (args : Array Val) : HostM AuthFn := do
  match f with
  | .contract addr fn => do chargeShallowCopy 1 DS.val; pure (.contractFn addr fn args)
  | .createContractHostFn a => do
    -- `CreateContractArgsV2::metered_clone` (metered_clone.rs:690-700)
    chargeShallowCopy 1 DS.CreateContractArgsV2
    chargeExecutableSub a.executable
    chargeVecSub a.constructorArgs.size DS.ScVal
    chargeScValsSub BIG a.constructorArgs.toList
    pure (.createContractHostFn a)

/-- `maybe_check_invoker_contract_auth` (auth.rs:1164-1225). -/
def maybeCheckInvokerContractAuth (address : Val) (fn : AuthFn) : HostM Bool := do
  let am := (← get).auth
  let cs := am.callStack
  if cs.size < 2 then return false
  let curr := match cs.back? with | some (.contract a _) => some a | _ => none
  let some inv := cs[cs.size - 2]? | hostThrow .Auth .InternalError
  if let .contract ia _ := inv then
    if (← cmpVal BIG ia address) == .eq then return true
  let mut invs := am.invokerTrackers
  for h : i in [0:invs.size] do
    let t := invs[i]!
    if let some ca := curr then
      if (← cmpVal BIG t.contractAddress ca) == .eq then continue
    if (← cmpVal BIG t.contractAddress address) == .eq then
      let (ok, inv') ← t.inv.maybeExtend fn true
      invs := invs.set! i { t with inv := inv' }
      modify fun s => { s with auth := { s.auth with invokerTrackers := invs } }
      if ok then return true
  return false

/-- `AccountAuthorizationTracker::authenticate` + `verify_and_consume_nonce`
    (auth.rs:2586-2723): nothing to do for the transaction source account. -/
def AccountTracker.authenticate (t : AccountTracker) : HostM Unit := do
  if t.credentials == .sourceAccount then return
  unsupported   -- TODO: signature checks (ed25519 accounts, `__check_auth`), nonces

/-- `require_auth_enforcing` (auth.rs:1227-1296). -/
def requireAuthEnforcing (address : Val) (fn : AuthFn) : HostM Unit := do
  let accs := (← get).auth.accountTrackers
  let mut hasActive := false
  for t in accs do
    if t.borrowed then continue
    if (← cmpVal BIG t.address address) == .eq && t.inv.isActive && !t.inv.currentFrameMatched then
      hasActive := true
      break
  for h : i in [0:(← get).auth.accountTrackers.size] do
    let t := (← get).auth.accountTrackers[i]!
    if t.borrowed then continue
    if (← cmpVal BIG t.address address) != .eq then continue
    -- `maybe_authorize_invocation` (auth.rs:2474-2512)
    let (ok, inv') ← t.inv.maybeExtend fn !hasActive
    let t := { t with inv := inv' }
    modify fun s => { s with auth := { s.auth with accountTrackers := s.auth.accountTrackers.set! i t } }
    if !ok then continue
    if !t.verified then
      t.authenticate
      modify fun s => { s with auth := { s.auth with
        accountTrackers := s.auth.accountTrackers.set! i { t with verified := true } } }
    return
  hostThrow .Auth .InvalidAction

/-- `AuthorizationManager::require_auth` (auth.rs:1118-1139) + `require_auth_internal`. -/
def authRequireAuth (address : Val) (args : Array Val) : HostM Unit := do
  let some top := (← get).auth.callStack.back? | hostThrow .Auth .InternalError
  let fn ← top.toAuthFn args
  if ← maybeCheckInvokerContractAuth address fn then return
  requireAuthEnforcing address fn

end Soroban
