/-
End of `invoke_host_function` (src: soroban-env-host/src/e2e_invoke.rs:209-353,
:427-447, :535-579, :1007-1022; host.rs:765-775 `try_finish`; events/internal.rs:211-247;
crypto/mod.rs:411-490).
-/
import SorobanLean.Host.Invoke
import SorobanLean.Crypto.Sha256

namespace Soroban
open Xdr

/-! ## Hashing (crypto/mod.rs) -/

def sha256HashFromBytesRaw (b : ByteArray) : HostM ByteArray := do
  charge .ComputeSha256Hash (some b.size)
  pure (Crypto.sha256 b)

def sha256HashFromBytes (b : ByteArray) : HostM ByteArray := do
  chargeBulkInitCpy DS.vec DS.u8 32
  sha256HashFromBytesRaw b


/-- e2e_invoke.rs:491-534: everything up to (excluding) `host.invoke_function`. -/
def e2eSetup (inp : E2EInput) : HostM E2ESetup := do
  let resources ← meteredFromXdr rd_SorobanResources inp.resources
  let restoredKeys ← buildRestoredKeySet resources inp.restoredRwEntryIndices
  let footprint ← buildFootprint resources.footprint
  let some minLive := minLiveUntilLedgerChecked inp.ledgerInfo .PERSISTENT
    | hostThrow .Context .InternalError
  let (storageMap, sizes) ← buildStorageMap resources.footprint inp.ledgerEntries inp.ledgerInfo.sequenceNumber
  let initMap ← cloneStorageMap storageMap
  modify fun s => { s with storage := { footprint, map := storageMap } }
  -- `build_auth_entries_from_xdr` (e2e_invoke.rs:1171-1182)
  chargeBulkInitCpy (DS.vec + DS.HostError) (DS.SorobanAuthorizationEntry + DS.HostError) inp.authEntries.size
  let mut auths := #[]
  for a in inp.authEntries do auths := auths.push (← meteredFromXdr rd_SorobanAuthorizationEntry a)
  let hostFunction ← meteredFromXdr rd_HostFunction inp.hostFn
  let src ← meteredFromXdr rd_AccountID inp.sourceAccount
  modify fun s => { s with sourceAccount := some src }
  modify fun s => { s with ledger := some inp.ledgerInfo }
  checkLedgerProtocolSupported inp.ledgerInfo
  -- `set_authorization_entries` (host.rs:538-545)
  let am ← authManagerEnforcing auths
  modify fun s => { s with auth := am }
  if inp.basePrngSeed.size != 32 then hostThrow .Context .InternalError
  -- `Prng::new_from_seed` then two unmetered 32-byte sub-PRNG draws (host.rs:548-565);
  -- the ChaCha20 stream position is recorded when the PRNG host functions are modelled.
  let seed ← unbiasPrngSeed inp.basePrngSeed
  modify fun s => { s with basePrng := some seed }
  pure { resources, restoredKeys, minLiveUntilLedger := minLive, initStorageMap := initMap,
         initialEntrySizesForRent := sizes, hostFunction }


/-! ## Ledger changes -/

structure TtlChange where
  keyHash : ByteArray
  entryType : LedgerEntryType
  durability : ContractDataDurability
  oldLiveUntilLedger : Nat := 0
  newLiveUntilLedger : Nat := 0
  deriving Inhabited

/-- `LedgerEntryChange` (e2e_invoke.rs:104-124). -/
structure LedgerEntryChange where
  readOnly : Bool := false
  encodedKey : ByteArray := .empty
  oldEntrySizeBytesForRent : Nat := 0
  encodedNewValue : Option ByteArray := none
  newEntrySizeBytesForRent : Nat := 0
  ttlChange : Option TtlChange := none
  deriving Inhabited

def _root_.Xdr.LedgerKey.entryType : LedgerKey → LedgerEntryType
  | .ACCOUNT _ => .ACCOUNT | .TRUSTLINE _ => .TRUSTLINE | .OFFER _ => .OFFER | .DATA _ => .DATA
  | .CLAIMABLE_BALANCE _ => .CLAIMABLE_BALANCE | .LIQUIDITY_POOL _ => .LIQUIDITY_POOL
  | .CONTRACT_DATA _ => .CONTRACT_DATA | .CONTRACT_CODE _ => .CONTRACT_CODE
  | .CONFIG_SETTING _ => .CONFIG_SETTING | .TTL _ => .TTL

def satU32 (n : Nat) : Nat := min n (2^32 - 1)

/-- `wasm_module_memory_cost` (parsed_module.rs:150-204): uncharged lookups. -/
def wasmModuleMemoryCost (b : Budget) (ext : ContractCodeEntryExt) (codeLen : Nat) : Nat :=
  match ext with
  | .v0 => b.memoryCost .VmInstantiation (some codeLen)
  | .v1 v1 =>
    let c := v1.costInputs
    [ (ContractCostType.ParseWasmInstructions, c.nInstructions), (.ParseWasmFunctions, c.nFunctions),
      (.ParseWasmGlobals, c.nGlobals), (.ParseWasmTableEntries, c.nTableEntries),
      (.ParseWasmTypes, c.nTypes), (.ParseWasmDataSegments, c.nDataSegments),
      (.ParseWasmElemSegments, c.nElemSegments), (.ParseWasmImports, c.nImports),
      (.ParseWasmExports, c.nExports), (.ParseWasmDataSegmentBytes, c.nDataSegmentBytes) ].foldl
      (fun acc (t, x) => satAdd acc (b.memoryCost t (some x.toNat))) 0

/-- `entry_size_for_rent` (e2e_invoke.rs:427-447). -/
def entrySizeForRent (b : Budget) (e : LedgerEntry) (xdrSize : Nat) : Nat :=
  let mc := match e.data with
    | .CONTRACT_CODE c => satU32 (wasmModuleMemoryCost b c.ext (satU32 c.code.size))
    | _ => 0
  satU32 (xdrSize + mc)

/-- `EntryTTLSource for StorageMap` (e2e_invoke.rs:1184-1197). -/
def initLiveUntil (init : Array (LedgerKey × Option SEntry)) (k : LedgerKey) : HostM (Option (Option Nat)) := do
  match ← MMap.get? storageMapOps init k with
  | some (some se) => pure (some se.liveUntil)
  | _ => pure none

/-- `get_ledger_changes` (e2e_invoke.rs:209-353), enforcing build. -/
def getLedgerChanges (su : E2ESetup) : HostM (Array LedgerEntryChange) := do
  let fp := su.resources.footprint
  if fp.readOnly.size + fp.readWrite.size != su.initialEntrySizesForRent.size then throw storageInternalError
  let keys := fp.readOnly.map (AccessType.readOnly, ·) ++ fp.readWrite.map (AccessType.readWrite, ·)
  let mut out := #[]
  for h : i in [0:keys.size] do
    let (acc, key) := keys[i]
    let initSize := su.initialEntrySizesForRent[i]!
    let some newE ← MMap.get? storageMapOps (← get).storage.map key | continue
    let encodedKey ← meteredWriteXdr wr_LedgerKey key
    let mut ch : LedgerEntryChange := { encodedKey }
    if let some d := keyDurability key then
      let keyHash ← sha256HashFromBytes encodedKey
      ch := { ch with ttlChange := some { keyHash, entryType := key.entryType, durability := d } }
    match ← initLiveUntil su.initStorageMap key with
    | some mlu =>
      if initSize.isSome != mlu.isSome then throw storageInternalError
      if let some tc := ch.ttlChange then
        let some sz := initSize | throw storageInternalError
        let some lu := mlu | throw storageInternalError
        let tc' := { tc with oldLiveUntilLedger := lu }
        ch := { ch with oldEntrySizeBytesForRent := sz, ttlChange := some tc' }
    | none => if initSize.isSome then throw storageInternalError
    if let some se := newE then
      if let some tc := ch.ttlChange then
        let some nlu := se.liveUntil | throw storageInternalError
        let tc' := { tc with newLiveUntilLedger := max nlu tc.oldLiveUntilLedger }
        ch := { ch with ttlChange := some tc' }
    match acc with
    | .readOnly => ch := { ch with readOnly := true }
    | .readWrite =>
      if let some se := newE then
        let e ← decodeCell se.cell
        let buf ← meteredWriteXdr wr_LedgerEntry e
        let sz := entrySizeForRent (← get).budget e (satU32 buf.size)
        ch := { ch with newEntrySizeBytesForRent := sz, encodedNewValue := some buf }
        if let some rk := su.restoredKeys then
          if ← MMap.containsKey restoredKeyOps rk key then
            ch := { ch with oldEntrySizeBytesForRent := 0 }
            if let some tc := ch.ttlChange then
              let nlu := max tc.newLiveUntilLedger su.minLiveUntilLedger
              let tc' := { tc with oldLiveUntilLedger := 0, newLiveUntilLedger := nlu }
              ch := { ch with ttlChange := some tc' }
    out := out.push ch
  pure out

/-! ## The whole invocation -/

structure E2EResult where
  /-- `Ok(encoded ScVal)` or the error. -/
  result : Except HErr ByteArray
  ledgerChanges : Array LedgerEntryChange
  encodedContractEvents : Array ByteArray
  deriving Inhabited

/-- `encode_contract_events` (e2e_invoke.rs:1007-1022): the externalized events that are
    neither diagnostic nor from a failed call, each written as XDR; then the result
    vector is charged. -/
def encodeContractEvents (evs : Array (Xdr.ContractEvent × Bool)) : HostM (Array ByteArray) := do
  let mut out := #[]
  for (e, failed) in evs do
    if failed || e.«type» == .DIAGNOSTIC then continue
    out := out.push (← meteredWriteXdr wr_ContractEvent e)
  chargeBulkInitCpy DS.vec DS.vec out.size
  pure out

/-- `invoke_host_function` (e2e_invoke.rs:470-579) with `enable_diagnostics = false`, no
    trace hook and no module cache. `n` is the Lean gas. -/
def invokeHostFunction (n : Nat) (inp : E2EInput) : HostM E2EResult := do
  let su ← e2eSetup inp
  let res ← tryCatch (Except.ok <$> invokeFunction n su.hostFunction) (fun e => pure (Except.error e))
  -- `try_finish` (host.rs:765-775): events are externalized, whatever the result
  let evs ← externalizeEvents
  let enc ← match res with
    | .ok v => tryCatch (Except.ok <$> meteredWriteXdr wr_SCVal v) (fun e => pure (Except.error e))
    | .error e => pure (.error e)
  match enc with
  | .ok b => do
    let changes ← getLedgerChanges su
    let encEvs ← encodeContractEvents evs
    pure { result := .ok b, ledgerChanges := changes, encodedContractEvents := encEvs }
  | .error e => pure { result := .error e, ledgerChanges := #[], encodedContractEvents := #[] }

end Soroban
