/-
  `answer` for models emitted by stellar-diver (`slice --lean model`).

  Nothing here is specific to a contract: the entry points are read off the model's
  `Contract.entries` where the tactic is used, and each one's `Spec` is opened with the
  structure's own field names. It handles statements of the form
  `∀ st, (∃ e ∈ entries, e st) → P st` that need case analysis on the entry point, the
  post-state written into the goal, and linear arithmetic.
-/
import Lean

open Lean Elab Tactic Meta

namespace Diver

/-- `answer` for any model emitted by stellar-diver, for statements of the form
    `∀ st, (∃ e ∈ entries, e st) → P st`: one case per entry point (read off `entries`),
    its `Spec` opened with the structure's own field names, the post-state rewritten
    into the goal, and `simp`/`omega`/`grind` with the model's simp lemmas. -/
elab "answer" : tactic => do
  let env ← getEnv
  let some (.defnInfo d) := env.find? `Contract.entries | throwError "no `entries` in the model"
  let names := d.value.getUsedConstants.filter fun n => n.getPrefix == `Contract && (env.find? (n.str "Spec")).isSome
  let mut cases := #[]
  for n in names do
    let spec := n.str "Spec"
    let some (.inductInfo ci) := env.find? spec | throwError "no {spec}"
    let fields := getStructureFields env spec
    let pat := ", ".intercalate (fields.toList.map toString)
    let open_ := if ci.numParams == 2 then "\n  obtain ⟨u, h⟩ := h" else ""
    cases := cases.push s!"· simp only [{n}] at h{open_}
  obtain ⟨{pat}⟩ := h
  intros
  all_goals (try simp only [post] at *)
  all_goals (try set_option linter.unusedSimpArgs false in simp_all [Contract.getOr0, Contract.xferOk])
  all_goals (try omega)
  all_goals grind"
  let src := s!"(intro st he
 obtain ⟨e, he, h⟩ := he
 simp only [Contract.entries, List.mem_cons, List.not_mem_nil, or_false] at he
 rcases he with {" | ".intercalate (names.toList.map fun _ => "rfl")}
 {"\n ".intercalate (cases.toList.map fun c => c.replace "\n" "\n ")})"
  let stx ← match Parser.runParserCategory env `tactic src with
    | .ok stx => pure stx
    | .error e => throwError "answer: internal error {e}"
  let ref ← getRef
  try
    withoutRecover (evalTactic stx)
  catch e =>
    -- Reported at `answer` itself, with the first line of what failed (not the goal dump).
    let why := ((← e.toMessageData.toString).splitOn "\n").headD ""
    throwErrorAt ref "answer: could not prove this ({why}). It handles statements about each \
      call that need no more than case analysis and linear arithmetic; try vibe."

end Diver
