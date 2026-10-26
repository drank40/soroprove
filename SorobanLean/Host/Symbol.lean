/-
Symbol conversions used by host functions and the host itself (src:
soroban-env-common/src/symbol.rs:107-122, :354-376; soroban-env-host/src/host.rs:964-1009,
:2830-2837; host/mem_helper.rs:332-342).
-/
import SorobanLean.Host.Conv

namespace Soroban
open Xdr

/-! ## Symbols -/

/-- Typed `visit_obj` (host_object.rs:522-541). -/
def visitSymbolObj (v : Val) : HostM ByteArray := do
  match ← visitObj v with
  | .symbol b => pure b
  | _ => hostThrow .Object .InternalError

/-- `symbol_len` called through `Env` (`check_env_arg` then host.rs:2830-2837). -/
def envSymbolLen (s : Val) : HostM Nat := do
  checkValIntegrity s
  let b ← visitSymbolObj s
  if b.size ≥ 2^32 then hostThrow .Value .ArithDomain
  pure b.size

/-- `symbol_copy_to_slice(obj, 0, slice)` (`EnvBase`, unwrapped): `memobj_copy_to_slice`
    (mem_helper.rs:332-342) → visit, bounds, `metered_copy_byte_slice`. -/
def symbolCopyToSlice (s : Val) (len : Nat) : HostM ByteArray := do
  let b ← visitSymbolObj s
  if len > b.size then hostThrow .Object .IndexBounds
  charge .MemCpy (some len)
  pure (b.extract 0 len)

/-- `TryFromVal<Symbol> for SymbolStr` (symbol.rs:354-376). -/
def symbolStr (s : Val) : HostM ByteArray := do
  if s.getTag == .SymbolSmall then return symbolSmallBytes s.getBody
  let len ← envSymbolLen s
  if len > SCSYMBOL_LIMIT then hostThrow .Value .InternalError
  symbolCopyToSlice s len

/-- `symbol_new_from_slice` (host.rs:990-1009). -/
def symbolNewFromSlice (b : ByteArray) : HostM Val := do
  charge .MemCmp (some b.size)
  if !(b.toList.all fun x => (SymbolSmall.encodeByte x).isSome) then hostThrow .Value .InvalidInput
  chargeBulkInitCpy DS.vec DS.u8 b.size
  if b.size > SCSYMBOL_LIMIT then hostThrow .Value .InvalidInput
  addHostObject (.symbol b)

/-- `TryFromVal<&[u8]> for Symbol` (symbol.rs:107-122). -/
def symbolFromBytes (b : ByteArray) : HostM Val := do
  match SymbolSmall.tryFromBytes b.toList with
  | some body => pure (Val.fromBodyAndTag body .SymbolSmall)
  | none => symbolNewFromSlice b

end Soroban
