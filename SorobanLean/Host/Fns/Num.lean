/-
Integer-object and ledger-info host functions (src: soroban-env-host/src/host.rs:1266-1384,
:3689-3730, host/num.rs:1-16, int128_helpers in soroban-env-common/src/num.rs;
`TryFromVal<u64> for U64Val` soroban-env-common/src/convert.rs:143-154).
-/
import SorobanLean.Host.FnCore

namespace Soroban
open Xdr

/-- Typed `visit_obj` (host_object.rs:522-541): a wrong variant is (Object, InternalError). -/
def visitU64Obj (v : Val) : HostM Nat := do
  match ← visitObj v with | .u64 n => pure n | _ => hostThrow .Object .InternalError

def visitI128Obj (v : Val) : HostM Int := do
  match ← visitObj v with | .i128 n => pure n | _ => hostThrow .Object .InternalError

def visitMuxedObj (v : Val) : HostM SCAddress := do
  match ← visitObj v with | .muxedAddress a => pure a | _ => hostThrow .Object .InternalError

/-- A raw `i64` argument (passed as its payload bits). -/
def i64Of (v : Val) : Int := v.payload.toInt64.toInt
def u64Of (v : Val) : Nat := v.payload.toNat
def rawVal (n : Nat) : Val := ⟨UInt64.ofNat n⟩
def rawI64 (i : Int) : Val := ⟨(Int64.ofInt i).toUInt64⟩

/-- `u64::metered_clone` on a visited object: a shallow copy (host/num.rs:11-16). -/
def cloneU64 (n : Nat) : HostM Nat := do chargeShallowCopy 1 DS.u64; pure n

/-- `obj_from_u64` called through `Env`: `add_host_object`, then the returned
    `U64Object` is integrity-checked (vmcaller_env.rs:196-200). -/
def envObjFromU64 (u : Nat) : HostM Val := do
  let o ← addHostObject (.u64 u)
  checkValIntegrity o
  pure o

/-- `TryFromVal<u64> for U64Val` (convert.rs:143-154). -/
def u64ValFromNat (u : Nat) : HostM Val :=
  if isSmallU64 u then pure (Val.fromBodyAndTag (UInt64.ofNat u) .U64Small) else envObjFromU64 u

def objFromU64 : HostFnImpl := fun _ a => addHostObject (.u64 (u64Of a[0]!))

def objToU64 : HostFnImpl := fun _ a => do
  let n ← cloneU64 (← visitU64Obj a[0]!)
  pure (rawVal n)

/-- `int128_helpers::i128_from_pieces`: `(hi as i128) << 64 | lo`. -/
def objFromI128Pieces : HostFnImpl := fun _ a =>
  addHostObject (.i128 (i64Of a[0]! * 2^64 + u64Of a[1]!))

def objToI128Lo64 : HostFnImpl := fun _ a => do
  let i ← visitI128Obj a[0]!
  pure (rawVal (Int.emod i (2^64)).toNat)

def objToI128Hi64 : HostFnImpl := fun _ a => do
  let i ← visitI128Obj a[0]!
  pure (rawI64 (Int.ediv i (2^64)))

def getLedgerSequence : HostFnImpl := fun _ _ => do
  pure (Val.fromU32 (UInt32.ofNat (← withLedgerInfo).sequenceNumber))

/-- `get_address_from_muxed_address` (host.rs:3689-3712). -/
def getAddressFromMuxed : HostFnImpl := fun _ a => do
  let addr ← match ← visitMuxedObj a[0]! with
    | .SC_ADDRESS_TYPE_MUXED_ACCOUNT m => do
        chargeShallowCopy 1 DS.Uint256
        pure (SCAddress.SC_ADDRESS_TYPE_ACCOUNT (.PUBLIC_KEY_TYPE_ED25519 m.ed25519))
    | .SC_ADDRESS_TYPE_MUXED_CONTRACT m => do
        chargeShallowCopy 1 DS.ContractId
        pure (SCAddress.SC_ADDRESS_TYPE_CONTRACT m.contractId)
    | _ => hostThrow .Object .InternalError
  addHostObject (.address addr)

/-- `get_id_from_muxed_address` (host.rs:3714-3730). -/
def getIdFromMuxed : HostFnImpl := fun _ a => do
  let id ← match ← visitMuxedObj a[0]! with
    | .SC_ADDRESS_TYPE_MUXED_ACCOUNT m => pure m.id.toNat
    | .SC_ADDRESS_TYPE_MUXED_CONTRACT m => pure m.id.toNat
    | _ => hostThrow .Object .InternalError
  u64ValFromNat id

end Soroban
