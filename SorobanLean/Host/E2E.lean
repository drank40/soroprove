/-
End-to-end `invoke_host_function` (src: soroban-env-host/src/e2e_invoke.rs:470-579).

This file holds the pre-invocation setup and post-invocation finish; the invocation
itself is `Host.invokeFunction`.
-/
import SorobanLean.Host.Conv
import SorobanLean.Host.MeteredXdr
import SorobanLean.Crypto.Sha256

namespace Soroban
open Xdr

/-- `TtlLedgerEntryMeta` (e2e_invoke.rs:41-45). -/
structure TtlMeta where
  liveUntilLedger : Nat
  entrySizeForRent : Nat
  deriving Inhabited

/-- Metered-map instances of the storage layer (storage.rs:57-70). -/
def footprintOps : MMapOps LedgerKey AccessType :=
  { entrySize := DS.pair DS.rc DS.AccessType, kcmp := cmpLedgerKey }
def storageMapOps : MMapOps LedgerKey (Option SEntry) :=
  { entrySize := DS.pair DS.rc (DS.option (DS.pair DS.rc (DS.option DS.u32))), kcmp := cmpLedgerKey }
def restoredKeyOps : MMapOps LedgerKey Unit :=
  { entrySize := DS.pair DS.rc DS.unit, kcmp := cmpLedgerKey }

/-- `get_key_durability` (ledger_info.rs:33-39). -/
def keyDurability : LedgerKey → Option ContractDataDurability
  | .CONTRACT_DATA d => some d.durability
  | .CONTRACT_CODE _ => some .PERSISTENT
  | _ => none

def storageInternalError : HErr := errV .Storage .InternalError

/-- `build_restored_key_set` (e2e_invoke.rs:146-169). `Rc::new` is unmetered here. -/
def buildRestoredKeySet (res : SorobanResources) (idx : Array Nat) :
    HostM (Option (Array (LedgerKey × Unit))) := do
  if idx.isEmpty then return none
  let rw := res.footprint.readWrite
  let mut ks := #[]
  for e in idx do
    let some k := rw[e]? | throw storageInternalError
    let k ← meteredCloneLedgerKey k
    ks ← MMap.insert restoredKeyOps ks k ()
  pure (some ks)

/-- `build_storage_footprint_from_xdr` (e2e_invoke.rs:1035-1059). -/
def buildFootprint (fp : LedgerFootprint) : HostM (Array (LedgerKey × AccessType)) := do
  let mut m := #[]
  for k in fp.readWrite do
    checkSupportedKey k
    let k ← meteredCloneLedgerKey k
    chargeRcNew DS.LedgerKey
    m ← MMap.insert footprintOps m k .readWrite
  for k in fp.readOnly do
    checkSupportedKey k
    let k ← meteredCloneLedgerKey k
    chargeRcNew DS.LedgerKey
    m ← MMap.insert footprintOps m k .readOnly
  pure m

/-- `build_storage_map_from_xdr_ledger_entries` (e2e_invoke.rs:1061-1169), enforcing build
    (no `recording_mode`). New lazy cells are appended to the host's cell heap. -/
def buildStorageMap (fp : LedgerFootprint) (entries : Array (Option ByteArray × Option TtlMeta))
    (ledgerNum : Nat) : HostM (Array (LedgerKey × Option SEntry) × Array (Option Nat)) := do
  if fp.readOnly.size + fp.readWrite.size != entries.size then throw storageInternalError
  let keys := fp.readOnly ++ fp.readWrite
  let mut m := #[]
  let mut sizes := #[]
  for h : i in [0:keys.size] do
    let key := keys[i]
    let (maybeEntry, maybeTtl) := entries[i]!
    checkSupportedKey key
    let key ← meteredCloneLedgerKey key
    chargeRcNew DS.LedgerKey
    let ent ← match maybeEntry with
      | some bytes => do
        charge .MemAlloc (some bytes.size)
        charge .MemCpy (some bytes.size)
        chargeRcNew DS.LazyLedgerEntry
        let cell := (← get).cells.size
        modify fun s => { s with cells := s.cells.push { encoded := some bytes, decoded := none } }
        match maybeTtl, keyDurability key with
        | some t, some _ =>
            if t.liveUntilLedger < ledgerNum then throw storageInternalError
            pure (some { cell, liveUntil := some t.liveUntilLedger : SEntry })
        | none, none => pure (some { cell, liveUntil := none : SEntry })
        | _, _ => throw storageInternalError
      | none => do
        if maybeTtl.isSome then throw storageInternalError
        pure none
    sizes := sizes.push (maybeTtl.map (·.entrySizeForRent))
    m ← MMap.insert storageMapOps m key ent
  pure (m, sizes)

/-- `StorageMap::metered_clone` (metered_map.rs `MeteredClone`, metered_clone.rs:270-277):
    the element type `(Rc<LedgerKey>, Option<(Rc<..>, Option<u32>)>)` is shallow. -/
def cloneStorageMap (m : Array (LedgerKey × Option SEntry)) : HostM (Array (LedgerKey × Option SEntry)) := do
  chargeShallowCopy 1 DS.vec
  chargeVecSub m.size storageMapOps.entrySize
  pure m

/-- `LedgerInfo::min_live_until_ledger_checked` (ledger_info.rs:16-23). -/
def minLiveUntilLedgerChecked (li : LedgerInfo) (d : ContractDataDurability) : Option Nat :=
  let m := match d with | .TEMPORARY => li.minTempEntryTtl | .PERSISTENT => li.minPersistentEntryTtl
  let r := li.sequenceNumber + (m - 1)
  if r < 2^32 then some r else none

/-- `INTERFACE_VERSION.protocol` of soroban-env-common v30.0.0. -/
def INTERFACE_PROTOCOL : Nat := 30

/-- `check_ledger_protocol_supported` (host.rs:572-605). -/
def checkLedgerProtocolSupported (li : LedgerInfo) : HostM Unit := do
  if li.protocolVersion < INTERFACE_PROTOCOL then hostThrow .Context .InternalError
  if li.protocolVersion > INTERFACE_PROTOCOL then hostThrow .Context .InternalError

/-- Inputs of `invoke_host_function`. -/
structure E2EInput where
  hostFn : ByteArray
  resources : ByteArray
  restoredRwEntryIndices : Array Nat := #[]
  sourceAccount : ByteArray
  authEntries : Array ByteArray := #[]
  ledgerInfo : LedgerInfo
  ledgerEntries : Array (Option ByteArray × Option TtlMeta)
  basePrngSeed : ByteArray

/-- Everything `invoke_host_function` computes before `host.invoke_function`. -/
structure E2ESetup where
  resources : SorobanResources
  restoredKeys : Option (Array (LedgerKey × Unit))
  minLiveUntilLedger : Nat
  initStorageMap : Array (LedgerKey × Option SEntry)
  initialEntrySizesForRent : Array (Option Nat)
  hostFunction : HostFunction
  deriving Inhabited

/-- `unbias_prng_seed` (crypto/mod.rs:457-486): HMAC-SHA256 keyed by the public
    network id (a fixed salt, independent of the ledger's network). -/
def PRNG_SALT : ByteArray := Crypto.sha256 "Public Global Stellar Network ; September 2015".toUTF8

def unbiasPrngSeed (seed : ByteArray) : HostM ByteArray := do
  bulkCharge .ComputeSha256Hash 2 (some 64)
  pure (Crypto.hmacSha256 PRNG_SALT seed)

end Soroban
