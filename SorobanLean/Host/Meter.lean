/-
Metering primitives of the host (src: vendor/rs-soroban-env/soroban-env-host/src/host/
{metered_clone.rs, declared_size.rs, metered_vector.rs, metered_map.rs},
budget/limits.rs DepthLimiter).
-/
import SorobanLean.Host.Budget

namespace Soroban

/-- Observable host error = the `Error` Val it carries (HostError.error). -/
abbrev HErr := Val

/- Declared sizes for metering (src: host/declared_size.rs:59-347). -/
namespace DS
def unit : Nat := 0
def bool : Nat := 1
def u8 : Nat := 1
def u32 : Nat := 4
def i32 : Nat := 4
def u64 : Nat := 8
def i64 : Nat := 8
def u128 : Nat := 16
def i128 : Nat := 16
def usize : Nat := 8
def str : Nat := 16
def val : Nat := 8          -- Val and every Val wrapper / Object type (:72-110)
def U256 : Nat := 32
def I256 : Nat := 32
def HostObject : Nat := 64
def HostError : Nat := 16
def Context : Nat := 552
def Address : Nat := 16
def AccessType : Nat := 1
def InternalContractEvent : Nat := 40
def HostEvent : Nat := 168
def Events : Nat := 24
def InternalEvent : Nat := 40
def TimePoint : Nat := 8
def Duration : Nat := 8
def ScVal : Nat := 96
def ScValObject : Nat := 96
def ScMapEntry : Nat := 192
def ScVec : Nat := 24
def ScMap : Nat := 24
def Hash : Nat := 32
def ContractId : Nat := 32
def Uint256 : Nat := 32
def Int128Parts : Nat := 16
def UInt128Parts : Nat := 16
def Int256Parts : Nat := 32
def UInt256Parts : Nat := 32
def ContractExecutable : Nat := 72
def AccountId : Nat := 32
def ScAddress : Nat := 48
def MuxedScAddress : Nat := 48
def ScNonceKey : Nat := 33
def PublicKey : Nat := 32
def LedgerKeyContractCode : Nat := 36
def LedgerEntryExt : Nat := 33
def AccountEntry : Nat := 216
def TrustLineEntry : Nat := 128
def ContractCodeCostInputs : Nat := 40
def ContractCodeEntry : Nat := 64
def ContractCodeEntryV1 : Nat := 40
def TtlEntry : Nat := 36
def LedgerKey : Nat := 152
def LedgerEntry : Nat := 288
def ContractEvent : Nat := 160
def ScBytes : Nat := 24
def ScString : Nat := 24
def ExecutableTag : Nat := 24
def ScSymbol : Nat := 24
def ScError : Nat := 8
def InvokeContractArgs : Nat := 96
def ContractDataDurability : Nat := 4
def ExtensionPoint : Nat := 0
def ScContractInstance : Nat := 96
def SorobanAuthorizationEntry : Nat := 384
def SorobanAuthorizedInvocation : Nat := 200
def SorobanAuthorizedFunction : Nat := 176
def LazyLedgerEntry : Nat := 32
def Value : Nat := 16
def EventError : Nat := 1
def ContractInvocation : Nat := 16
def AuthorizedInvocation : Nat := 208
def AuthorizedInvocationSnapshot : Nat := 32
def AccountAuthorizationTracker : Nat := 320
def AccountAuthorizationTrackerSnapshot : Nat := 96
def DelegatedAccountAuthSignerTreeNode : Nat := 48
def DelegatedAccountAuthSignerTreeNodeSnapshot : Nat := 32
def DelegatedAccountAuthTrackerSnapshot : Nat := 56
def InvokerContractAuthorizationTracker : Nat := 264
def InternalDiagnosticArg : Nat := 96
def InternalDiagnosticEvent : Nat := 88
def SponsorshipDescriptor : Nat := 33
def Asset : Nat := 45
def TrustLineAsset : Nat := 45
def Signer : Nat := 72
def LedgerKeyAccount : Nat := 32
def LedgerKeyTrustLine : Nat := 77
def CreateContractArgs : Nat := 152
def CreateContractArgsV2 : Nat := 176
def ContractIdPreimage : Nat := 80
def BlsScalar : Nat := 32
def BnScalar : Nat := 32
/-- Generic containers (:276-347). -/
def rc : Nat := 16
def vec : Nat := 24
def bytesM : Nat := 24
def stringM : Nat := 24
def box : Nat := 8
def option (c : Nat) : Nat := satAdd c 8
def pair (k v : Nat) : Nat := satAdd (satAdd k v) 8
def array (c n : Nat) : Nat := satMul c n
def refCell (t : Nat) : Nat := t + 8
def refCellAccountAuthorizationTracker : Nat := refCell AccountAuthorizationTracker
end DS

/-! ## The host monad

`HostState` is defined incrementally in `Host/State.lean`; metering only needs a
budget accessor, so it is abstracted with a class. -/

class HasBudget (σ : Type) where
  get : σ → Budget
  set : σ → Budget → σ

variable {σ : Type} [HasBudget σ]

/-- Host computations. State survives errors (`ExceptT` over `StateM`), as in the Rust
    host, whose budget, object table, etc. are interior-mutable and are not rolled back
    when a `Result::Err` propagates. -/
abbrev HM (σ α : Type) := ExceptT HErr (StateM σ) α

def hmThrow {α} (e : HErr) : HM σ α := throw e

/-- `Budget::charge` (budget.rs:1404-1406 → :246-295). -/
def charge (ty : Xdr.ContractCostType) (input : Option Nat) : HM σ Unit := do
  let s ← get
  let (b, e) := (HasBudget.get s).charge ty 1 input
  set (HasBudget.set s b)
  if let some e := e then throw e

/-- `Budget::bulk_charge` (budget.rs:1388-1397). -/
def bulkCharge (ty : Xdr.ContractCostType) (iterations : Nat) (input : Option Nat) : HM σ Unit := do
  let s ← get
  let (b, e) := (HasBudget.get s).charge ty iterations input
  set (HasBudget.set s b)
  if let some e := e then throw e

/-- `charge_shallow_copy::<T>(n)` = MemCpy(n * size) (metered_clone.rs:44-58). -/
def chargeShallowCopy (n size : Nat) : HM σ Unit := charge .MemCpy (some (satMul n size))
/-- `charge_heap_alloc::<T>(n)` = MemAlloc(n * size) (metered_clone.rs:60-74). -/
def chargeHeapAlloc (n size : Nat) : HM σ Unit := charge .MemAlloc (some (satMul n size))

/-- `MeteredContainer::charge_bulk_init_cpy(len)` (metered_clone.rs:93-97):
    shallow copy of the container, heap alloc + shallow copy of the items. -/
def chargeBulkInitCpy (containerSize itemSize len : Nat) : HM σ Unit := do
  chargeShallowCopy 1 containerSize
  chargeHeapAlloc len itemSize
  chargeShallowCopy len itemSize

/-- `Rc::metered_new` (metered_clone.rs:80-84): heap alloc of one T. -/
def chargeRcNew (tSize : Nat) : HM σ Unit := chargeHeapAlloc 1 tSize

/-- `DepthLimiter::with_limited_depth` on the budget (budget/limits.rs:31-41, :82-114):
    enter (Context/ExceededLimit at 0), run, always leave, then return the result. -/
def withDepth {α} (act : HM σ α) : HM σ α := do
  let s ← get
  let b := HasBudget.get s
  if b.depthLimit = 0 then throw (Val.fromError .Context .ExceededLimit)
  set (HasBudget.set s { b with depthLimit := b.depthLimit - 1 })
  let r ← tryCatch (do let a ← act; pure (Except.ok a)) (fun e => pure (Except.error e))
  let s ← get
  let b := HasBudget.get s
  set (HasBudget.set s { b with depthLimit := b.depthLimit + 1 })
  match r with
  | .ok a => pure a
  | .error e => throw e

/-! ## Deep-clone charges of XDR values (metered_clone.rs:206-560)

`Vec<C>` substructure: heap alloc + shallow copy of len elements, then the
elements' own substructure if `C` is not shallow (:270-277). -/

def chargeVecSub (len elemSize : Nat) : HM σ Unit := do
  chargeHeapAlloc len elemSize
  chargeShallowCopy len elemSize

/-- BytesM / StringM / ScBytes / ScString / ScSymbol: a `Vec<u8>` (:364-410). -/
def chargeBytesSub (b : ByteArray) : HM σ Unit := chargeVecSub b.size DS.u8

/-- ContractExecutable (:228-237). -/
def chargeExecutableSub : Xdr.ContractExecutable → HM σ Unit
  | .CONTRACT_EXECUTABLE_WASM _ | .CONTRACT_EXECUTABLE_STELLAR_ASSET => pure ()
  | .CONTRACT_EXECUTABLE_EXTERNAL_REF r => chargeBytesSub r.tag

mutual
/-- `impl MeteredClone for ScVal::charge_for_substructure` (:305-341), inside the
    budget depth limiter. `fu` is Lean fuel only. -/
def chargeScValSub : Nat → Xdr.SCVal → HM σ Unit
  | 0, _ => throw (Val.fromError .Context .InternalError)
  | fu + 1, v => withDepth do
    match v with
    | .SCV_VEC (some xs) => do chargeVecSub xs.size DS.ScVal; chargeScValsSub fu xs.toList
    | .SCV_MAP (some m) => do chargeVecSub m.size DS.ScMapEntry; chargeMapEntriesSub fu m.toList
    | .SCV_VEC none | .SCV_MAP none => throw (Val.fromError .Value .InvalidInput)
    | .SCV_BYTES b => chargeBytesSub b
    | .SCV_STRING s => chargeBytesSub s
    | .SCV_SYMBOL s => chargeBytesSub s
    | .SCV_EXECUTABLE_TAG s => chargeBytesSub s
    | .SCV_CONTRACT_INSTANCE i => do
        chargeExecutableSub i.executable
        match i.storage with
        | some m => do chargeVecSub m.size DS.ScMapEntry; chargeMapEntriesSub fu m.toList
        | none => pure ()
    | _ => pure ()
def chargeScValsSub : Nat → List Xdr.SCVal → HM σ Unit
  | 0, _ => throw (Val.fromError .Context .InternalError)
  | _ + 1, [] => pure ()
  | fu + 1, x :: xs => do chargeScValSub fu x; chargeScValsSub fu xs
def chargeMapEntriesSub : Nat → List Xdr.SCMapEntry → HM σ Unit
  | 0, _ => throw (Val.fromError .Context .InternalError)
  | _ + 1, [] => pure ()
  | fu + 1, e :: es => do chargeScValSub fu e.key; chargeScValSub fu e.val; chargeMapEntriesSub fu es
end

def BIG : Nat := 2 ^ 40

/-- `ScVal::metered_clone` (:178-182): shallow copy of the ScVal then substructure. -/
def meteredCloneScVal (v : Xdr.SCVal) : HM σ Xdr.SCVal := do
  chargeShallowCopy 1 DS.ScVal
  chargeScValSub BIG v
  pure v

/-- `LedgerKey::charge_for_substructure` (:411-422). -/
def chargeLedgerKeySub : Xdr.LedgerKey → HM σ Unit
  | .CONTRACT_DATA d => chargeScValSub BIG d.key
  | .CONTRACT_CODE _ | .ACCOUNT _ | .TRUSTLINE _ => pure ()
  | _ => throw (Val.fromError .Value .InternalError)

def meteredCloneLedgerKey (k : Xdr.LedgerKey) : HM σ Xdr.LedgerKey := do
  chargeShallowCopy 1 DS.LedgerKey
  chargeLedgerKeySub k
  pure k

/-- `Signer::charge_for_substructure` (metered_clone.rs:612-621). -/
def chargeSignerSub (s : Xdr.Signer) : HM σ Unit :=
  match s.key with
  | .SIGNER_KEY_TYPE_ED25519_SIGNED_PAYLOAD p => chargeBytesSub p.payload
  | _ => pure ()

/-- `AccountEntry::charge_for_substructure` (metered_clone.rs:623-640). -/
def chargeAccountEntrySub (ae : Xdr.AccountEntry) : HM σ Unit := do
  chargeBytesSub ae.homeDomain
  chargeVecSub ae.signers.size DS.Signer
  for s in ae.signers do chargeSignerSub s
  match ae.ext with
  | .v0 => pure ()
  | .v1 v1 => match v1.ext with
    | .v0 => pure ()
    | .v2 v2 => chargeVecSub v2.signerSponsoringIDs.size DS.SponsorshipDescriptor

/-- `LedgerEntry::charge_for_substructure` (metered_clone.rs:596-610). -/
def chargeLedgerEntrySub (e : Xdr.LedgerEntry) : HM σ Unit :=
  match e.data with
  | .CONTRACT_DATA d => do chargeScValSub BIG d.val; chargeScValSub BIG d.key
  | .CONTRACT_CODE c => chargeBytesSub c.code   -- ContractCodeEntryV1 is shallow (:584-594)
  | .ACCOUNT ae => chargeAccountEntrySub ae
  | .TRUSTLINE _ => pure ()
  | _ => throw (Val.fromError .Value .InternalError)

def meteredCloneLedgerEntry (e : Xdr.LedgerEntry) : HM σ Xdr.LedgerEntry := do
  chargeShallowCopy 1 DS.LedgerEntry
  chargeLedgerEntrySub e
  pure e

/-- `ScContractInstance::metered_clone` (metered_clone.rs:574-580). -/
def meteredCloneInstance (i : Xdr.SCContractInstance) : HM σ Xdr.SCContractInstance := do
  chargeShallowCopy 1 DS.ScContractInstance
  chargeExecutableSub i.executable
  match i.storage with
  | some m => do chargeVecSub m.size DS.ScMapEntry; chargeMapEntriesSub BIG m.toList
  | none => pure ()
  pure i

end Soroban
