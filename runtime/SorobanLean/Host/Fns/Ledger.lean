/-
Contract data host functions (src: soroban-env-host/src/host.rs:2076-2260,
host/data_helper.rs:260-420, :600-760).
-/
import SorobanLean.Host.FnCore

namespace Soroban
open Xdr

/-! ## Contract data (host.rs:2076-2224, data_helper.rs:637-760) -/

/-- `validate_put_contract_data` (data_helper.rs:637-666). -/
def validatePutContractData (k _v : Val) (_t : StorageType) : HostM Unit := do
  if k.getTag == .ExecutableTagObject then unsupported   -- TODO(M5): executable refs

/-- `put_contract_data_into_ledger` (data_helper.rs:686-740). -/
def putContractDataIntoLedger (k v : Val) (t : StorageType) : HostM Unit := do
  let d ← t.durability
  let key ← storageKeyFromVal k d
  if ← storageHas key then
    let (cur, lu) ← storageGetWithLiveUntil key
    let cur ← meteredCloneLedgerEntry cur
    let cur ← match cur.data with
      | .CONTRACT_DATA e => do
        let val ← fromHostVal v
        pure { cur with data := .CONTRACT_DATA { e with val } }
      | _ => hostThrow .Storage .InternalError
    chargeRcNew DS.LedgerEntry
    storagePut key cur lu
  else
    let cid ← currentContractId
    let kk ← fromHostVal k
    let vv ← fromHostVal v
    let addr : SCAddress := .SC_ADDRESS_TYPE_CONTRACT cid
    let e ← newContractData { ext := .v0, contract := addr, key := kk, durability := d, val := vv }
    let lu ← getMinLiveUntilLedger d
    storagePut key e (some lu)

def putContractData : HostFnImpl := fun _ a => do
  let k := a[0]!; let v := a[1]!; let t := StorageType.ofVal a[2]!
  validatePutContractData k v t
  match t with
  | .temporary | .persistent => putContractDataIntoLedger k v t
  | .inst => withMutInstanceStorage fun st => do
      let m ← MMap.insert instanceMapOps st.map k v
      pure ((), { st with map := m })
  pure Val.VOID

def hasContractData : HostFnImpl := fun _ a => do
  let k := a[0]!; let t := StorageType.ofVal a[1]!
  let r ← match t with
    | .temporary | .persistent => do
      let key ← storageKeyFromVal k (← t.durability)
      storageHas key
    | .inst => withInstanceStorage fun st => do
      pure (← MMap.get? instanceMapOps st.map k).isSome
  pure (Val.fromBool r)

def getContractData : HostFnImpl := fun _ a => do
  let k := a[0]!; let t := StorageType.ofVal a[1]!
  match t with
  | .temporary | .persistent => do
    let key ← storageKeyFromVal k (← t.durability)
    let e ← storageGet key
    match e.data with
    | .CONTRACT_DATA d => toValidHostVal d.val
    | _ => hostThrow .Storage .InternalError
  | .inst => withInstanceStorage fun st => do
    match ← MMap.get? instanceMapOps st.map k with
    | some v => pure v
    | none => hostThrow .Storage .MissingValue

/-- `validate_del_contract_data` (data_helper.rs:668-684). -/
def validateDelContractData (k : Val) : HostM Unit := do
  if k.getTag == .ExecutableTagObject then hostThrow .Storage .InvalidAction

/-- `MeteredOrdMap::remove` (metered_map.rs:254-292): `Some((new_map, value))`; the
    removed value is `metered_clone`d (`cloneV`). -/
def mmapRemove {K V} [Inhabited K] [Inhabited V] (o : MMapOps K V) (cloneV : V → HostM V)
    (m : Array (K × V)) (k : K) : HostM (Option (Array (K × V) × V)) := do
  match ← MMap.find o m k with
  | .ok i => do
    let m' ← MMap.fromExactIter o (m.extract 0 i ++ m.extract (i + 1) m.size)
    pure (some (m', ← cloneV m[i]!.2))
  | .error _ => pure none

/-- `Val::metered_clone`: a shallow copy. -/
def cloneVal (v : Val) : HostM Val := do chargeShallowCopy 1 DS.val; pure v

def delContractData : HostFnImpl := fun _ a => do
  let k := a[0]!; let t := StorageType.ofVal a[1]!
  validateDelContractData k
  match t with
  | .temporary | .persistent => do
    let key ← storageKeyFromVal k (← t.durability)
    storageDel key
  | .inst => withMutInstanceStorage fun st => do
    match ← mmapRemove instanceMapOps cloneVal st.map k with
    | some (m, _) => pure ((), { st with map := m })
    | none => pure ((), st)
  pure Val.VOID

def extendContractDataTtl : HostFnImpl := fun _ a => do
  let k := a[0]!; let t := StorageType.ofVal a[1]!
  if t == .inst then hostThrow .Storage .InvalidAction
  let key ← storageKeyFromVal k (← t.durability)
  storageExtendTtl key (u32Of a[2]!) (u32Of a[3]!)
  pure Val.VOID

/-- `extend_contract_instance_ttl_from_contract_id` (data_helper.rs:372-386); the
    instance key's `Rc` is `metered_clone`d (a shallow copy). -/
def extendInstanceTtlFromId (key : LedgerKey) (threshold extendTo : Nat) : HostM Unit := do
  chargeShallowCopy 1 DS.rc
  storageExtendTtl key threshold extendTo

/-- `extend_contract_code_ttl_from_contract_id` (data_helper.rs:340-370). -/
def extendCodeTtlFromId (key : LedgerKey) (threshold extendTo : Nat) : HostM Unit := do
  let inst ← retrieveContractInstance key
  match inst.executable with
  | .CONTRACT_EXECUTABLE_WASM h => do
    let ck ← contractCodeLedgerKey h
    storageExtendTtl ck threshold extendTo
  | .CONTRACT_EXECUTABLE_EXTERNAL_REF _ => unsupported   -- TODO(M5): executable refs
  | .CONTRACT_EXECUTABLE_STELLAR_ASSET => pure ()

def extendCurrentContractInstanceAndCodeTtl : HostFnImpl := fun _ a => do
  let cid ← currentContractId
  let key ← contractInstanceLedgerKey cid
  extendInstanceTtlFromId key (u32Of a[0]!) (u32Of a[1]!)
  extendCodeTtlFromId key (u32Of a[0]!) (u32Of a[1]!)
  pure Val.VOID

end Soroban
