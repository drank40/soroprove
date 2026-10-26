/-
Metered XDR (src: soroban-env-host/src/host/metered_xdr.rs; error mapping
soroban-env-common/src/error.rs:154-163 `From<xdr::Error> for Error`).
-/
import SorobanLean.Host.Meter

namespace Soroban
open Xdr

variable {σ : Type} [HasBudget σ]

/-- `From<xdr::Error> for Error`: depth/length limits → (Context, ExceededLimit), any
    other decoding failure (incl. `Io` for truncated input) → (Value, InvalidInput). -/
def xdrErrToVal : Xdr.Err → HErr
  | .depthLimitExceeded | .lengthLimitExceeded => Val.fromError .Context .ExceededLimit
  | .fuel => Val.fromError .Context .InternalError   -- Lean fuel only, unreachable
  | _ => Val.fromError .Value .InvalidInput

/-- `metered_from_xdr` / `metered_from_xdr_with_budget` (metered_xdr.rs:40-46, :73-82):
    ValDeser(len), then a full decode with the default depth and `len = bytes.len()`. -/
def meteredFromXdr {α} (rd : Nat → Nat → Rt.R α) (bytes : ByteArray) : HM σ α := do
  charge .ValDeser (some bytes.size)
  match decodeToEnd rd bytes DEFAULT_DEPTH bytes.size with
  | .ok a => pure a
  | .error e => throw (xdrErrToVal e)

/-- `metered_write_xdr` (metered_xdr.rs:56-68): one ValSer charge per `write` call; any
    failure (budget or XDR limit) becomes (Budget, ExceededLimit). -/
def meteredWriteXdr {α} (wr : Nat → Nat → α → Rt.W) (x : α) : HM σ ByteArray := do
  let (bytes, chunks, ok) := match encodeChunks wr x with
    | .ok (b, cs) => (b, cs, true)
    | .error (_, cs) => (ByteArray.empty, cs, false)
  for c in chunks do
    tryCatch (charge .ValSer (some c)) fun _ => throw (Val.fromError .Budget .ExceededLimit)
  if !ok then throw (Val.fromError .Budget .ExceededLimit)
  pure bytes

end Soroban
