/-
  `answer` for models emitted by stellar-diver (`slice --lean model`).

  Nothing here is specific to a contract: the entry points are read off the model's
  `Contract.entries` where the tactic is used, and each one's `Spec` is opened with the
  structure's own field names. Two shapes of statement:

  * about each call, `∀ st, (∃ e ∈ entries, e st) → P st`: one case per entry point,
    its post-state written into the goal, then `simp`/`omega`/`grind`;
  * about every history, `∀ me s t, Run me s t → I s → I t` (an invariant): induction
    on the history. A call is the case above with `I` before the call as a hypothesis;
    outside activity is closed with the model's `Outside` (the contract's own storage
    is unchanged, its token balances only grow).

  It proves what needs no more than that: case analysis, rewriting and linear
  arithmetic, with an invariant that is inductive as stated. The rest is for vibe.
-/
import Lean

open Lean Elab Tactic Meta

namespace Diver

/-- One case per entry point of the model in scope, as tactic text: open the step's
    `Spec` (and its open values `u`, if it has some) under its own field names, write
    the post-state into the goal, and close it. -/
def entryCases (env : Environment) (names : Array Name) : Except String (Array String) :=
  names.mapM fun n => do
    let spec := n.str "Spec"
    let some (.inductInfo ci) := env.find? spec | throw s!"no {spec}"
    let pat := ", ".intercalate ((getStructureFields env spec).toList.map toString)
    let opn := if ci.numParams == 2 then "\n  obtain ⟨u, h⟩ := h" else ""
    pure s!"· simp only [{n}] at h{opn}
  obtain ⟨{pat}⟩ := h
  intros
  all_goals (try simp only [post] at *)
  all_goals (try set_option linter.unusedSimpArgs false in simp_all [Contract.getOr0, Contract.xferOk])
  all_goals (try omega)
  all_goals grind"

/-- Indent every line of `s` but the first by `n` spaces. -/
def indent (n : Nat) (s : String) : String := s.replace "\n" ("\n" ++ String.ofList (List.replicate n ' '))

def splitEntry (names : Array Name) : String :=
  s!"obtain ⟨e, he, h⟩ := he
simp only [Contract.entries, List.mem_cons, List.not_mem_nil, or_false] at he
rcases he with {" | ".intercalate (names.toList.map fun _ => "rfl")}"

elab "answer" : tactic => do
  let env ← getEnv
  let some (.defnInfo d) := env.find? `Contract.entries | throwError "answer: no `entries` in the model"
  let names := d.value.getUsedConstants.filter fun n => n.getPrefix == `Contract && (env.find? (n.str "Spec")).isSome
  let cases ← match entryCases env names with
    | .ok c => pure c
    | .error e => throwError "answer: {e}"
  let history := (← getMainTarget).find? (·.isConstOf `Contract.Run) |>.isSome
  let src := if history then
    s!"(intro me s t hrun hs
 induction hrun with
 | refl => exact hs
 | @call st hr hself he ih =>
   have hpre := ih
   clear ih hr
   subst hself
   {indent 3 (splitEntry names)}
   {indent 3 ("\n".intercalate (cases.toList))}
 | @outside t₁ t₂ hr hout ih =>
   have hpre := ih
   clear ih hr
   have hv : ∀ n, t₂ (Contract.Key.var n) = t₁ (Contract.Key.var n) := fun n => by
     have := hout (Contract.Key.var n); simpa [Contract.temporary] using this
   have he : ∀ m a, t₂ (Contract.Key.entry m a) = t₁ (Contract.Key.entry m a) := fun m a => by
     have := hout (Contract.Key.entry m a); simpa [Contract.temporary] using this
   have hhv : ∀ n, t₂ (Contract.Key.has (Contract.Key.var n)) = t₁ (Contract.Key.has (Contract.Key.var n)) := fun n => by
     have := hout (Contract.Key.has (Contract.Key.var n)); simpa [Contract.temporary] using this
   have hhe : ∀ m a, t₂ (Contract.Key.has (Contract.Key.entry m a)) = t₁ (Contract.Key.has (Contract.Key.entry m a)) := fun m a => by
     have := hout (Contract.Key.has (Contract.Key.entry m a)); simpa [Contract.temporary] using this
   have hb : ∀ tok, t₁ (Contract.Key.bal tok me) ≤ t₂ (Contract.Key.bal tok me) := fun tok => hout (Contract.Key.bal tok me) rfl
   set_option linter.unusedSimpArgs false in simp [Contract.bal, Contract.getOr0, hv, he, hhv, hhe] at hpre ⊢
   all_goals (try omega)
   all_goals grind)"
  else
    s!"(intro st he
 {indent 1 (splitEntry names)}
 {indent 1 ("\n".intercalate (cases.toList))})"
  let stx ← match Parser.runParserCategory env `tactic src with
    | .ok stx => pure stx
    | .error e => throwError "answer: internal error {e}"
  let ref ← getRef
  try
    withoutRecover (evalTactic stx)
  catch e =>
    -- Reported at `answer` itself, with the first line of what failed (not the goal dump).
    let why := ((← e.toMessageData.toString).splitOn "\n").headD ""
    throwErrorAt ref "answer: could not prove this ({why}). It handles statements about each call, \
      and invariants that are inductive as stated, that need no more than case analysis and linear \
      arithmetic; try vibe."

end Diver
