/-
Host-function infrastructure shared by all host-function modules: the
implementation type and argument helpers (src: soroban-env-host/src/vm/dispatch.rs,
soroban-env-common/src/storage_type.rs, host/conversion.rs:131-165).
-/
import SorobanLean.Host.Frame
import SorobanLean.Host.Symbol

namespace Soroban
open Xdr

/-- Capabilities a host function may need from the invocation layer (nested contract
    calls). Supplied by `Invoke.lean` at a smaller Lean gas. -/
structure Rec where
  callContract : ByteArray → Val → Array Val → HostM Val

/-- A host function body: the marshalled arguments (Val payloads; raw `i64`/`u64` and
    enum arguments as their payload) to the result payload. -/
abbrev HostFnImpl := Rec → Array Val → HostM Val

/-! ## Argument helpers -/

/-- `StorageType` (storage_type.rs:9-14). -/
inductive StorageType where
  | temporary | persistent | inst
  deriving DecidableEq, Inhabited

def StorageType.ofVal (v : Val) : StorageType :=
  match v.payload with | 0 => .temporary | 1 => .persistent | _ => .inst

/-- `TryFrom<StorageType> for ContractDataDurability` (storage_type.rs:19-32). -/
def StorageType.durability : StorageType → HostM ContractDataDurability
  | .temporary => pure .TEMPORARY
  | .persistent => pure .PERSISTENT
  | .inst => hostThrow .Value .InvalidInput

def u32Of (v : Val) : Nat := v.getMajor.toNat

/-- `storage_key_from_val` (conversion.rs:131-165). -/
def storageKeyFromVal (k : Val) (d : ContractDataDurability) : HostM LedgerKey := do
  let key ← fromHostValForStorage k
  let cid ← currentContractId
  chargeRcNew DS.LedgerKey
  pure (.CONTRACT_DATA { contract := .SC_ADDRESS_TYPE_CONTRACT cid, key, durability := d })

end Soroban
