/-
Evaluation of closed bitwise/shift expressions on `UInt64`/`UInt32` literals (core Lean
only ships arithmetic simprocs for these types). Definitional (`dsimproc`), so they add
nothing to proof terms.
-/
import Lean

namespace Soroban.Proof
open Lean Meta Simp

dsimproc reduceAnd64 ((_ : UInt64) &&& _) := fun e => do
  let_expr HAnd.hAnd _ _ _ _ a b ← e | return .continue
  let some x ← getUInt64Value? a | return .continue
  let some y ← getUInt64Value? b | return .continue
  return .done (toExpr (x &&& y))

dsimproc reduceOr64 ((_ : UInt64) ||| _) := fun e => do
  let_expr HOr.hOr _ _ _ _ a b ← e | return .continue
  let some x ← getUInt64Value? a | return .continue
  let some y ← getUInt64Value? b | return .continue
  return .done (toExpr (x ||| y))

dsimproc reduceXor64 ((_ : UInt64) ^^^ _) := fun e => do
  let_expr HXor.hXor _ _ _ _ a b ← e | return .continue
  let some x ← getUInt64Value? a | return .continue
  let some y ← getUInt64Value? b | return .continue
  return .done (toExpr (x ^^^ y))

dsimproc reduceShl64 ((_ : UInt64) <<< _) := fun e => do
  let_expr HShiftLeft.hShiftLeft _ _ _ _ a b ← e | return .continue
  let some x ← getUInt64Value? a | return .continue
  let some y ← getUInt64Value? b | return .continue
  return .done (toExpr (x <<< y))

dsimproc reduceShr64 ((_ : UInt64) >>> _) := fun e => do
  let_expr HShiftRight.hShiftRight _ _ _ _ a b ← e | return .continue
  let some x ← getUInt64Value? a | return .continue
  let some y ← getUInt64Value? b | return .continue
  return .done (toExpr (x >>> y))

dsimproc reduceAnd32 ((_ : UInt32) &&& _) := fun e => do
  let_expr HAnd.hAnd _ _ _ _ a b ← e | return .continue
  let some x ← getUInt32Value? a | return .continue
  let some y ← getUInt32Value? b | return .continue
  return .done (toExpr (x &&& y))

dsimproc reduceOr32 ((_ : UInt32) ||| _) := fun e => do
  let_expr HOr.hOr _ _ _ _ a b ← e | return .continue
  let some x ← getUInt32Value? a | return .continue
  let some y ← getUInt32Value? b | return .continue
  return .done (toExpr (x ||| y))

dsimproc reduceXor32 ((_ : UInt32) ^^^ _) := fun e => do
  let_expr HXor.hXor _ _ _ _ a b ← e | return .continue
  let some x ← getUInt32Value? a | return .continue
  let some y ← getUInt32Value? b | return .continue
  return .done (toExpr (x ^^^ y))

dsimproc reduceShl32 ((_ : UInt32) <<< _) := fun e => do
  let_expr HShiftLeft.hShiftLeft _ _ _ _ a b ← e | return .continue
  let some x ← getUInt32Value? a | return .continue
  let some y ← getUInt32Value? b | return .continue
  return .done (toExpr (x <<< y))

dsimproc reduceShr32 ((_ : UInt32) >>> _) := fun e => do
  let_expr HShiftRight.hShiftRight _ _ _ _ a b ← e | return .continue
  let some x ← getUInt32Value? a | return .continue
  let some y ← getUInt32Value? b | return .continue
  return .done (toExpr (x >>> y))

dsimproc reduceToUInt32Of64 (UInt64.toUInt32 _) := fun e => do
  let some x ← getUInt64Value? e.appArg! | return .continue
  return .done (toExpr x.toUInt32)

dsimproc reduceToUInt64Of32 (UInt32.toUInt64 _) := fun e => do
  let some x ← getUInt32Value? e.appArg! | return .continue
  return .done (toExpr x.toUInt64)

dsimproc reduceToNat64 (UInt64.toNat _) := fun e => do
  let some x ← getUInt64Value? e.appArg! | return .continue
  return .done (toExpr x.toNat)

dsimproc reduceToNat32 (UInt32.toNat _) := fun e => do
  let some x ← getUInt32Value? e.appArg! | return .continue
  return .done (toExpr x.toNat)

end Soroban.Proof
