/-
Checks `Solution` against the locked `Spec.Invariants`, both loaded from their .olean files:
* every theorem of `Spec.Invariants` exists in `Solution`, is a theorem defined there, and has
  exactly the locked type;
* every constant that type depends on is the same declaration, from the same trusted module,
  in both environments (so a solution cannot redefine `Reach`, `Solvent`, ...);
* the proofs use only the standard axioms (no `sorry`, `native_decide`, new axioms);
* all of `Solution`'s declarations re-check in the kernel (replay), independent of how the
  .olean was produced.
-/
import Lean
open Lean

def specModule : Name := `Spec.Invariants
def solModule : Name := `Solution
def allowedAxioms : List Name := [``propext, ``Classical.choice, ``Quot.sound]

def moduleOf (env : Environment) (n : Name) : Option Name :=
  (env.getModuleIdxFor? n).map fun i => env.header.moduleNames[i.toNat]!

/-- The constants a statement means something through: types, definition bodies and
    inductive constructors, transitively (not theorem proofs). -/
partial def statementDeps (env : Environment) (e : Expr) : NameSet :=
  go e.getUsedConstants.toList {}
where
  go : List Name → NameSet → NameSet
    | [], seen => seen
    | n :: ns, seen =>
      if seen.contains n then go ns seen else
      let seen := seen.insert n
      match env.find? n with
      | some (.defnInfo d) => go (d.type.getUsedConstants.toList ++ d.value.getUsedConstants.toList ++ ns) seen
      | some (.inductInfo i) => go (i.type.getUsedConstants.toList ++ i.ctors ++ ns) seen
      | some ci => go (ci.type.getUsedConstants.toList ++ ns) seen
      | none => go ns seen

def axiomsOf (env : Environment) (n : Name) : IO (Array Name) := do
  let ctx : Core.Context := { fileName := "<check>", fileMap := default }
  let (axs, _) ← (collectAxioms n : CoreM _).toIO ctx { env }
  return axs

def moduleIdx (env : Environment) (m : Name) : Option Nat :=
  env.header.moduleNames.findIdx? (· == m)

/-- Problems with `n` in `sol` as a proof of `ty`, the locked statement (or its negation). -/
def problems (spec sol : Environment) (n : Name) (ty : Expr) : IO (Array String) := do
  let mut errs : Array String := #[]
  match sol.find? n with
  | none => errs := errs.push s!"{n}: missing"
  | some ci =>
    if !ci.isTheorem then errs := errs.push s!"{n}: not a theorem"
    if moduleOf sol n != some solModule then errs := errs.push s!"{n}: not proved in {solModule}"
    if ci.type != ty then errs := errs.push s!"{n}: statement differs from the locked one"
    for d in (statementDeps spec ty).toList do
      let ok := match spec.find? d, sol.find? d with
        | some a, some b => moduleOf spec d == moduleOf sol d && a.type == b.type
        | _, _ => false
      if !ok then errs := errs.push s!"{n}: depends on {d}, which the solution redefines"
    if errs.isEmpty then
      for ax in ← axiomsOf sol n do
        if !allowedAxioms.contains ax then errs := errs.push s!"{n}: uses axiom {ax}"
  return errs

/-- Per locked theorem: PROVED, DISPROVED (the solution proves `<name>_false : ¬ <statement>`),
    or REJECT with the reasons. Exit 0 only when every locked theorem is proved. -/
def main : IO UInt32 := do
  initSearchPath (← findSysroot)
  let spec ← importModules #[{ module := specModule }] {}
  let sol ← importModules #[{ module := solModule }] {}
  -- Kernel replay of everything `Solution` declares, on top of its imports.
  let some idx := moduleIdx sol solModule | throw <| .userError "solution module missing"
  let md := sol.header.moduleData[idx]!
  let base ← importModules md.imports {}
  let consts := md.constants.foldl (fun m ci => m.insert ci.name ci) ({} : Std.HashMap Name ConstantInfo)
  let replayed ← try base.replay consts *> pure none catch e => pure (some e)
  if let some e := replayed then
    IO.println s!"REJECT kernel replay failed: {e}"
    return 1
  let some si := moduleIdx spec specModule | throw <| .userError "spec module missing"
  let locked := spec.header.moduleData[si]!.constants.filter (·.isTheorem) |>.map (·.name)
  let mut proved : Nat := 0
  for n in locked do
    let ty := (spec.find? n).get!.type
    let errs ← problems spec sol n ty
    if errs.isEmpty then
      IO.println s!"PROVED    {n}"; proved := proved + 1
    else if (← problems spec sol (n.appendAfter "_false") (mkNot ty)).isEmpty then
      IO.println s!"DISPROVED {n}: {n.appendAfter "_false"} proves its negation"
    else
      for e in errs do IO.println s!"REJECT {e}"
  IO.println s!"{proved}/{locked.size} locked theorems proved, axioms ⊆ {allowedAxioms}"
  return if proved == locked.size then 0 else 1
