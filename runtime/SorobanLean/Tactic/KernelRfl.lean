/-
`kernel_rfl name : ∀ xs, lhs = rhs` adds the theorem `fun xs => Eq.refl lhs`, checked by
the kernel alone (no elaborator `isDefEq`, which is far too slow on decoded modules).
-/
import Lean

namespace Soroban.Tactic
open Lean Elab Command Term Meta

syntax (name := kernelRfl) "kernel_rfl " ident " : " term : command

@[command_elab kernelRfl] def elabKernelRfl : CommandElab := fun stx => do
  let n := stx[1].getId
  let name := (← getCurrNamespace) ++ n
  liftTermElabM do
    let ty ← elabType stx[3]
    synthesizeSyntheticMVarsNoPostponing
    let ty ← instantiateMVars ty
    if ty.hasMVar then throwError "kernel_rfl: statement has metavariables"
    let pf ← forallTelescope ty fun xs body => do
      let some (α, lhs, _) := body.eq? | throwError "kernel_rfl: expected an equation"
      mkLambdaFVars xs (mkApp2 (mkConst ``Eq.refl [← getLevel α]) α lhs)
    let lvls := (collectLevelParams {} ty).params.toList
    addDecl (.thmDecl { name, levelParams := lvls, type := ty, value := pf })

end Soroban.Tactic
