/-
Contract events (src: soroban-env-host/src/host.rs:1252-1260, events/mod.rs:232-280,
events/internal.rs:20-47, :160-247; host/conversion.rs:68-121, :192-231, :976-981).
-/
import SorobanLean.Host.Fns.Num

namespace Soroban
open Xdr

/-- `bytes_new_from_slice` (`EnvBase`, host.rs:976-981): `metered_slice_to_vec`, then a
    new `Bytes` object. -/
def bytesNewFromSlice (b : ByteArray) : HostM Val := do
  chargeBulkInitCpy DS.vec DS.u8 b.size
  addHostObject (.bytes b)

/-- `bytesobj_from_internal_contract_id` (conversion.rs:223-231). -/
def bytesObjFromInternalContractId : HostM (Option Val) := do
  match ← currentContractIdOpt with
  | some id => some <$> bytesNewFromSlice id
  | none => pure none

/-- `record_contract_event` (events/mod.rs:266-279) + `InternalEventsBuffer::record`
    (events/internal.rs:168-183): one `(InternalEvent, EventError)` pushed. -/
def recordContractEvent (ty : ContractEventType) (topics data : Val) : HostM Unit := do
  let cid ← bytesObjFromInternalContractId
  chargeBulkInitCpy DS.vec (DS.pair DS.InternalEvent DS.EventError) 1
  modify fun s => { s with events := s.events.push { type_ := ty, contractId := cid, topics, data } }

/-- `contract_event` (host.rs:1252-1260). -/
def contractEvent : HostFnImpl := fun _ a => do
  recordContractEvent .CONTRACT a[0]! a[1]!
  pure Val.VOID

/-- `vals_to_scval_vec` (conversion.rs:200-214): metered collect, then the `VecM` bound. -/
def valsToScValVec (vs : Array Val) : HostM (Array SCVal) := do
  chargeBulkInitCpy (DS.vec + DS.HostError) (DS.ScVal + DS.HostError) vs.size
  let mut out := #[]
  for v in vs do out := out.push (← fromHostVal v)
  if out.size ≥ 2^32 then hostThrow .Object .ExceededLimit
  pure out

/-- `vecobject_to_scval_vec` (conversion.rs:196-199). -/
def vecObjectToScValVec (v : Val) : HostM (Array SCVal) := do
  match ← visitObj v with
  | .vec xs => valsToScValVec xs
  | _ => hostThrow .Object .InternalError

/-- `fixed_length_bytes_from_bytesobj_input::<_, 32>` (conversion.rs:86-121). -/
def hashFromBytesObj (v : Val) : HostM ByteArray := do
  match ← visitObj v with
  | .bytes b =>
    if b.size != 32 then hostThrow .Object .UnexpectedSize
    charge .MemCpy (some 32)
    pure b
  | _ => hostThrow .Object .InternalError

/-- `InternalContractEvent::to_xdr` (events/internal.rs:20-40). -/
def ContractEvent.toXdr (e : ContractEvent) : HostM Xdr.ContractEvent := do
  let topics ← vecObjectToScValVec e.topics
  let data ← fromHostVal e.data
  let cid ← match e.contractId with
    | some o => some <$> hashFromBytesObj o
    | none => pure none
  pure { ext := .v0, contractID := cid, «type» := e.type_, body := .v0 { topics, data } }

/-- `InternalEventsBuffer::externalize` (events/internal.rs:211-247) for a host
    without diagnostics: each contract event converted and pushed as a `HostEvent`. -/
def externalizeEvents : HostM (Array (Xdr.ContractEvent × Bool)) := do
  let mut out := #[]
  for e in (← get).events do
    let x ← e.toXdr
    chargeBulkInitCpy DS.vec DS.HostEvent 1
    out := out.push (x, e.failedCall)
  pure out

end Soroban
