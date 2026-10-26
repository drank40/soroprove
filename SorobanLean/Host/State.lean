/-
Host state (src: vendor/rs-soroban-env/soroban-env-host/src/host.rs:97-172 `HostImpl`,
storage.rs, host/frame.rs, host_object.rs, auth.rs).
-/
import SorobanLean.Host.Meter
import SorobanLean.Wasm.Instantiate

namespace Soroban

/-- src: soroban-env-host/src/ledger_info.rs:4-13. -/
structure LedgerInfo where
  protocolVersion : Nat
  sequenceNumber : Nat
  timestamp : Nat
  networkId : ByteArray
  baseReserve : Nat
  minTempEntryTtl : Nat
  minPersistentEntryTtl : Nat
  maxEntryTtl : Nat
  deriving Inhabited

/-- src: storage.rs `AccessType` (derived Ord: ReadOnly < ReadWrite). -/
inductive AccessType where
  | readOnly | readWrite
  deriving DecidableEq, Repr, Inhabited

/-- `LazyLedgerEntry` (host/ledger_entry.rs): shared via `Rc`, decoded at most once
    through interior mutability. Modelled as a cell in a heap so that sharing between
    the live storage map, rollback points and the e2e initial-map clone is exact. -/
structure LazyCell where
  encoded : Option ByteArray
  decoded : Option Xdr.LedgerEntry
  deriving Inhabited

/-- `HostEntryWithLiveUntil` = (Rc<LazyLedgerEntry>, Option<u32>) — cell index + TTL. -/
structure SEntry where
  cell : Nat
  liveUntil : Option Nat
  deriving Inhabited

/-- `Storage` (storage.rs) in enforcing mode. Both maps are sorted metered maps. -/
structure Storage where
  footprint : Array (Xdr.LedgerKey × AccessType)
  map : Array (Xdr.LedgerKey × Option SEntry)
  deriving Inhabited

/-- `HostObject` (host_object.rs:21-38). Big integers are kept as Lean `Int`/`Nat`
    in their exact Rust ranges. -/
inductive HostObject where
  | vec (xs : Array Val)
  | map (kvs : Array (Val × Val))
  | u64 (v : Nat)
  | i64 (v : Int)
  | timepoint (v : Nat)
  | duration (v : Nat)
  | u128 (v : Nat)
  | i128 (v : Int)
  | u256 (v : Nat)
  | i256 (v : Int)
  | bytes (b : ByteArray)
  | string (b : ByteArray)
  | symbol (b : ByteArray)
  | address (a : Xdr.SCAddress)
  | muxedAddress (a : Xdr.SCAddress)
  | executableTag (b : ByteArray)
  deriving Inhabited

/-- `InstanceStorageMap` (storage.rs:24-53). -/
structure InstanceStorage where
  map : Array (Val × Val)
  isModified : Bool := false
  deriving Inhabited

/-- `Frame` (host/frame.rs). The VM itself (wasmi store) is not part of the host
    state: during a VM frame it lives in the interpreter and is handed to host
    functions as the wasm `Store`, like wasmi's `Caller`. -/
inductive Frame where
  | contractVM (contractId : ByteArray) (fnName : Val) (args : Array Val)
      (inst : Xdr.SCContractInstance) (relObjects : Array Val)
  | hostFunction (t : Xdr.HostFunctionType)
  | stellarAsset (contractId : ByteArray) (fnName : Val) (args : Array Val) (inst : Xdr.SCContractInstance)
  deriving Inhabited

/-- `Context` (host/frame.rs:79-84). -/
structure Context where
  frame : Frame
  prng : Option ByteArray := none   -- refined when PRNG host fns are modelled
  storage : Option InstanceStorage := none
  linearMemCharged : Nat := 0
  deriving Inhabited

/-! ## Authorization manager (auth.rs:193-700), enforcing mode -/

/-- `AuthorizedFunction` (auth.rs:672-676). -/
inductive AuthFn where
  /-- `ContractFunction { contract_address, function_name, args }` -/
  | contractFn (address : Val) (fnName : Val) (args : Array Val)
  | createContractHostFn (args : Xdr.CreateContractArgsV2)
  deriving Inhabited

/-- `AuthorizedInvocation` (auth.rs:680-685). -/
inductive AuthInv where
  | mk (function : AuthFn) (subs : Array AuthInv) (exhausted : Bool)
  deriving Inhabited

def AuthInv.function : AuthInv → AuthFn | .mk f _ _ => f
def AuthInv.subs : AuthInv → Array AuthInv | .mk _ s _ => s
def AuthInv.exhausted : AuthInv → Bool | .mk _ _ e => e

/-- `AuthorizedInvocationSnapshot` (auth.rs:692-695). -/
inductive AuthInvSnapshot where
  | mk (exhausted : Bool) (subs : Array AuthInvSnapshot)
  deriving Inhabited

/-- `MatchState` (auth.rs:374-378). -/
inductive MatchState where
  | unmatched | root | sub (indexInParent : Nat)
  deriving DecidableEq, Inhabited

def MatchState.isMatched : MatchState → Bool | .unmatched => false | _ => true

/-- `InvocationTracker` (auth.rs:428-437). -/
structure InvocationTracker where
  root : AuthInv
  matchStack : Array MatchState := #[]
  rootExhaustedFrame : Option Nat := none
  isFullyProcessed : Bool := false
  deriving Inhabited

/-- `AccountAuthorizationCredentials` (auth.rs:559-564); delegated signers are not
    modelled yet (their trackers raise `unsupportedErr`). -/
inductive AuthCredentials where
  | sourceAccount | address | addressV2 | addressWithDelegates
  deriving DecidableEq, Inhabited

/-- `AccountAuthorizationTracker` (auth.rs:617-638). `borrowed` stands for the
    tracker's `RefCell` being mutably borrowed (during its own authentication). -/
structure AccountTracker where
  address : Val
  inv : InvocationTracker
  signature : Val
  credentials : AuthCredentials
  verified : Bool := false
  nonce : Option (Int × Nat) := none
  borrowed : Bool := false
  deriving Inhabited

/-- `InvokerContractAuthorizationTracker` (auth.rs:648-652). -/
structure InvokerTracker where
  contractAddress : Val
  inv : InvocationTracker
  deriving Inhabited

/-- `AuthStackFrame` (auth.rs:654-658). -/
inductive AuthStackFrame where
  | contract (address : Val) (fnName : Val)
  | createContractHostFn (args : Xdr.CreateContractArgsV2)
  deriving Inhabited

/-- `AuthorizationManager` in enforcing mode (auth.rs:196-202). -/
structure AuthManager where
  callStack : Array AuthStackFrame := #[]
  accountTrackers : Array AccountTracker := #[]
  invokerTrackers : Array InvokerTracker := #[]
  deriving Inhabited

/-- A contract event recorded by the host (events/internal.rs:12-18
    `InternalContractEvent`, plus its `EventError` status). -/
structure ContractEvent where
  type_ : Xdr.ContractEventType := .CONTRACT
  /-- `BytesObject` holding the emitting contract's id, if any -/
  contractId : Option Val
  topics : Val
  data : Val
  failedCall : Bool := false
  deriving Inhabited

/-- The calling VM during a host-function dispatch (wasmi `Caller`): its store,
    whose fuel counters and linear memory host functions may read and write, and
    whether the instance exports a memory named `memory` (vm.rs:150-155). -/
structure VmCaller where
  store : Wasm.Store
  memExported : Bool
  deriving Inhabited

structure HostState where
  budget : Budget
  objects : Array HostObject := #[]
  storage : Storage
  cells : Array LazyCell
  contexts : Array Context := #[]
  events : Array ContractEvent := #[]
  auth : AuthManager := {}
  ledger : Option LedgerInfo := none
  sourceAccount : Option Xdr.AccountID := none
  basePrng : Option ByteArray := none
  storageKeyConversionActive : Bool := false
  vmCaller : Option VmCaller := none
  /-- The context stack `RefCell` is mutably borrowed (inside `with_current_context_mut`
      and `maybe_reload_instance_storage_on_frame_pop`); any other access to the
      context stack fails with (Context, InternalError) (frame.rs:268-330). -/
  ctxBorrowedMut : Bool := false
  deriving Inhabited

instance : HasBudget HostState where
  get s := s.budget
  set s b := { s with budget := b }

abbrev HostM := HM HostState

end Soroban
