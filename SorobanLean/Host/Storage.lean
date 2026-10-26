/-
Ledger storage in enforcing mode (src: soroban-env-host/src/storage.rs:150-760,
host/ledger_entry.rs, host/data_helper.rs:80-420, :564-760, host/ledger_info_helper.rs).

The diagnostic-only `decorate_storage_error` (storage.rs:875-930) only acts in debug
mode and does not change the error code; it is not modelled.
-/
import SorobanLean.Host.E2E

namespace Soroban
open Xdr

/-! ## Ledger info accessors (host.rs `with_ledger_info`, ledger_info_helper.rs) -/

def withLedgerInfo : HostM LedgerInfo := do
  match (← get).ledger with
  | some li => pure li
  | none => hostThrow .Context .InternalError

def getMinLiveUntilLedger (d : ContractDataDurability) : HostM Nat := do
  match minLiveUntilLedgerChecked (← withLedgerInfo) d with
  | some n => pure n
  | none => hostThrow .Context .InternalError

/-- `max_live_until_ledger_checked` (ledger_info.rs:25-30). -/
def maxLiveUntilLedgerChecked (li : LedgerInfo) : Option Nat :=
  let r := li.sequenceNumber + (li.maxEntryTtl - 1)
  if r < 2^32 then some r else none

def maxLiveUntilLedger : HostM Nat := do
  match maxLiveUntilLedgerChecked (← withLedgerInfo) with
  | some n => pure n
  | none => hostThrow .Context .InternalError

/-! ## Footprint and map access -/

/-- `Footprint::enforce_access` (storage.rs:105-122). -/
def enforceAccess (k : LedgerKey) (ty : AccessType) : HostM Unit := do
  match ← MMap.get? footprintOps (← get).storage.footprint k with
  | some .readOnly => if ty == .readWrite then hostThrow .Storage .ExceededLimit
  | some .readWrite => pure ()
  | none => hostThrow .Storage .ExceededLimit

/-- `Storage::check_supported_ledger_entry_type` (storage.rs:150-158). -/
def checkSupportedEntry (e : LedgerEntry) : HostM Unit :=
  match e.data with
  | .ACCOUNT _ | .TRUSTLINE _ | .CONTRACT_DATA _ | .CONTRACT_CODE _ => pure ()
  | _ => hostThrow .Storage .InternalError

/-- `try_get_host_ledger_entry` (storage.rs:256-268). -/
def tryGetHostEntry (k : LedgerKey) : HostM (Option SEntry) := do
  checkSupportedKey k
  enforceAccess k .readOnly
  match ← MMap.get? storageMapOps (← get).storage.map k with
  | none => hostThrow .Storage .InternalError
  | some e => pure e

/-- `LazyLedgerEntry::decoded` (ledger_entry.rs:46-57): decode at most once; the
    decoded entry is shared by every holder of the cell. -/
def decodeCell (i : Nat) : HostM LedgerEntry := do
  let some c := (← get).cells[i]? | hostThrow .Storage .InternalError
  if let some e := c.decoded then return e
  let some buf := c.encoded | hostThrow .Storage .InternalError
  let e ← meteredFromXdr rd_LedgerEntry buf
  chargeRcNew DS.LedgerEntry
  modify fun s => { s with cells := s.cells.set! i { c with decoded := some e } }
  pure e

/-- `ledger_entry_to_ledger_key` (ledger_entry.rs:79-104). -/
def ledgerEntryToKey (e : LedgerEntry) : HostM LedgerKey :=
  match e.data with
  | .ACCOUNT a => do chargeShallowCopy 1 DS.AccountId; pure (.ACCOUNT { accountID := a.accountID })
  | .TRUSTLINE t => do
      chargeShallowCopy 1 DS.AccountId; chargeShallowCopy 1 DS.TrustLineAsset
      pure (.TRUSTLINE { accountID := t.accountID, asset := t.asset })
  | .CONTRACT_DATA d => do
      chargeShallowCopy 1 DS.ScAddress
      let key ← meteredCloneScVal d.key
      pure (.CONTRACT_DATA { contract := d.contract, key, durability := d.durability })
  | .CONTRACT_CODE c => do chargeShallowCopy 1 DS.Hash; pure (.CONTRACT_CODE { hash := c.hash })
  | _ => hostThrow .Storage .InternalError

/-- `try_get_full_helper` (storage.rs:270-297). -/
def tryGetFull (k : LedgerKey) : HostM (Option (LedgerEntry × Option Nat)) := do
  match ← tryGetHostEntry k with
  | none => pure none
  | some se =>
    let wasDecoded := ((← get).cells[se.cell]?.bind (·.decoded)).isSome
    let e ← decodeCell se.cell
    if !wasDecoded then
      let dk ← ledgerEntryToKey e
      if (← cmpLedgerKey k dk) != .eq then hostThrow .Storage .InternalError
    pure (some (e, se.liveUntil))

/-- `Storage::get` (storage.rs:309-319). -/
def storageGet (k : LedgerKey) : HostM LedgerEntry := do
  match ← tryGetFull k with
  | some (e, _) => pure e
  | none => hostThrow .Storage .MissingValue

def storageTryGet (k : LedgerKey) : HostM (Option LedgerEntry) := do
  pure ((← tryGetFull k).map (·.1))

/-- `get_with_live_until_ledger` (storage.rs:331-342). -/
def storageGetWithLiveUntil (k : LedgerKey) : HostM (LedgerEntry × Option Nat) := do
  match ← tryGetFull k with
  | some r => pure r
  | none => hostThrow .Storage .MissingValue

/-- `put_opt_helper` (storage.rs:344-378). -/
def storagePutOpt (k : LedgerKey) (val : Option (LedgerEntry × Option Nat)) : HostM Unit := do
  checkSupportedKey k
  if let some (e, _) := val then checkSupportedEntry e
  enforceAccess k .readWrite
  let ent ← match val with
    | some (e, lu) => do
      chargeRcNew DS.LazyLedgerEntry
      let cell := (← get).cells.size
      modify fun s => { s with cells := s.cells.push { encoded := none, decoded := some e } }
      pure (some { cell, liveUntil := lu : SEntry })
    | none => pure none
  let m ← MMap.insert storageMapOps (← get).storage.map k ent
  modify fun s => { s with storage := { s.storage with map := m } }

def storagePut (k : LedgerKey) (e : LedgerEntry) (lu : Option Nat) : HostM Unit :=
  storagePutOpt k (some (e, lu))

def storageDel (k : LedgerKey) : HostM Unit := storagePutOpt k none

/-- `Storage::has` (storage.rs:420-432). -/
def storageHas (k : LedgerKey) : HostM Bool := do
  pure (← tryGetHostEntry k).isSome

structure TtlExtensionInfo where
  entry : SEntry
  oldLiveUntil : Nat
  currentTtl : Nat
  maxLiveUntil : Nat

/-- `prepare_extend_ttl` (storage.rs:434-500). -/
def prepareExtendTtl (k : LedgerKey) (extendTo : Nat) : HostM TtlExtensionInfo := do
  checkSupportedKey k
  let some se ← tryGetHostEntry k | hostThrow .Storage .MissingValue
  let some oldLu := se.liveUntil | hostThrow .Storage .InternalError
  let seq := (← withLedgerInfo).sequenceNumber
  if oldLu < seq then hostThrow .Storage .InternalError
  let maxLu ← maxLiveUntilLedger
  let some dur := keyDurability k | hostThrow .Storage .InternalError
  let maxTtl := maxLu - seq
  if dur == .TEMPORARY && extendTo > maxTtl then hostThrow .Storage .InvalidAction
  pure { entry := se, oldLiveUntil := oldLu, currentTtl := oldLu - seq, maxLiveUntil := maxLu }

/-- `apply_ttl_extension` (storage.rs:502-517). -/
def applyTtlExtension (k : LedgerKey) (info : TtlExtensionInfo) (newLu : Nat) : HostM Unit := do
  if newLu > info.oldLiveUntil then
    let m ← MMap.insert storageMapOps (← get).storage.map k (some { info.entry with liveUntil := some newLu })
    modify fun s => { s with storage := { s.storage with map := m } }

/-- `Storage::extend_ttl` (storage.rs:519-555). `seq + extend_to` saturates at u32. -/
def storageExtendTtl (k : LedgerKey) (threshold extendTo : Nat) : HostM Unit := do
  if threshold > extendTo then hostThrow .Storage .InvalidInput
  let info ← prepareExtendTtl k extendTo
  let seq := (← withLedgerInfo).sequenceNumber
  let newLu := min (min (seq + extendTo) (2^32 - 1)) info.maxLiveUntil
  if info.currentTtl ≤ threshold then applyTtlExtension k info newLu

/-- `Storage::extend_ttl_v2` (storage.rs:640-686). -/
def storageExtendTtlV2 (k : LedgerKey) (extendTo minExt maxExt : Nat) : HostM Unit := do
  if maxExt < minExt then hostThrow .Storage .InvalidInput
  let info ← prepareExtendTtl k extendTo
  let init := extendTo - info.currentTtl
  let fin := min (min init maxExt) (info.maxLiveUntil - info.oldLiveUntil)
  if fin < minExt then return
  let newLu := info.oldLiveUntil + fin
  if newLu ≥ 2^32 then hostThrow .Context .InternalError
  applyTtlExtension k info newLu

/-! ## Contract instance and code (data_helper.rs) -/

/-- `contract_instance_ledger_key` (data_helper.rs:81-95). -/
def contractInstanceLedgerKey (cid : ByteArray) : HostM LedgerKey := do
  chargeShallowCopy 1 DS.ContractId
  chargeRcNew DS.LedgerKey
  pure (.CONTRACT_DATA { contract := .SC_ADDRESS_TYPE_CONTRACT cid, key := .SCV_LEDGER_KEY_CONTRACT_INSTANCE,
                         durability := .PERSISTENT })

/-- `extract_contract_instance_from_ledger_entry` (data_helper.rs:97-118). -/
def extractContractInstance (e : LedgerEntry) : HostM SCContractInstance :=
  match e.data with
  | .CONTRACT_DATA d => match d.val with
    | .SCV_CONTRACT_INSTANCE i => meteredCloneInstance i
    | _ => hostThrow .Storage .InternalError
  | _ => hostThrow .Storage .InternalError

def retrieveContractInstance (k : LedgerKey) : HostM SCContractInstance := do
  extractContractInstance (← storageGet k)

/-- `contract_code_ledger_key` (data_helper.rs:128-137). -/
def contractCodeLedgerKey (h : ByteArray) : HostM LedgerKey := do
  chargeShallowCopy 1 DS.Hash
  chargeRcNew DS.LedgerKey
  pure (.CONTRACT_CODE { hash := h })

/-- `VersionedContractCodeCostInputs` (vm/parsed_module.rs:15-19). -/
inductive CostInputs where
  | v0 (wasmBytes : Nat)
  | v1 (c : ContractCodeCostInputs)
  deriving Inhabited

/-- `retrieve_wasm_from_storage` (data_helper.rs:139-166). -/
def retrieveWasm (h : ByteArray) : HostM (ByteArray × CostInputs) := do
  let k ← contractCodeLedgerKey h
  let e ← storageGet k
  match e.data with
  | .CONTRACT_CODE c => do
    chargeShallowCopy 1 DS.bytesM; chargeBytesSub c.code
    let costs ← match c.ext with
      | .v0 => pure (CostInputs.v0 c.code.size)
      | .v1 v1 => do chargeShallowCopy 1 DS.ContractCodeCostInputs; pure (.v1 v1.costInputs)
    pure (c.code, costs)
  | _ => hostThrow .Storage .InternalError

/-- `Host::new_contract_data` (data_helper.rs:564-578). -/
def newContractData (d : ContractDataEntry) : HostM LedgerEntry := do
  chargeRcNew DS.LedgerEntry
  pure { lastModifiedLedgerSeq := 0, data := .CONTRACT_DATA d, ext := .v0 }

/-- `store_contract_instance` (data_helper.rs:260-338). -/
def storeContractInstance (exec : Option ContractExecutable) (stor : Option (Array SCMapEntry))
    (cid : ByteArray) (k : LedgerKey) : HostM Unit := do
  if ← storageHas k then
    let (cur, lu) ← storageGetWithLiveUntil k
    let cur ← meteredCloneLedgerEntry cur
    let cur ← match cur.data with
      | .CONTRACT_DATA d => match d.val with
        | .SCV_CONTRACT_INSTANCE i =>
          let i := match exec with | some x => { i with executable := x } | none => i
          let i := match stor with | some m => { i with storage := some m } | none => i
          pure { cur with data := .CONTRACT_DATA { d with val := .SCV_CONTRACT_INSTANCE i } }
        | _ => hostThrow .Storage .InternalError
      | _ => hostThrow .Storage .InternalError
    chargeRcNew DS.LedgerEntry
    storagePut k cur lu
  else
    chargeShallowCopy 1 DS.ContractId
    let some x := exec | hostThrow .Context .InternalError
    let inst : SCContractInstance := { executable := x, storage := stor }
    let addr : SCAddress := .SC_ADDRESS_TYPE_CONTRACT cid
    let d : ContractDataEntry :=
      { ext := .v0, contract := addr, key := .SCV_LEDGER_KEY_CONTRACT_INSTANCE,
        durability := .PERSISTENT, val := .SCV_CONTRACT_INSTANCE inst }
    let e ← newContractData d
    let lu ← getMinLiveUntilLedger .PERSISTENT
    storagePut k e (some lu)

end Soroban
