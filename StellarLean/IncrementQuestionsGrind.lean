import StellarLean.Increment

/-
  The questions of `IncrementQuestions.lean`, answered with `grind`.

  `grind` does not unfold definitions on its own. The attributes below tell it
  which ones to unfold and which facts to use; they are `local`, so they apply
  to this file only and change nothing elsewhere.

  Theorems live in `Increment.Grind` so they do not clash with the originals.
-/

namespace Increment.Grind

open Query
open Spec (Addr)

/-! ## What `grind` may use -/

-- Equations: reading a number back, and what `COUNTER` reads as.
attribute [local grind =] ofVal_int ofVal_none get_COUNTER

-- A fact about every step: once `increment st` is known, the counter went up by one.
attribute [local grind →] count_after

-- Definitions to unfold: the contract and the question bricks.
attribute [local grind] increment increases changesBy returns unchanged
  Question.except Question.all one

/-! ## Questions, answered -/

/-- Does every call increase the counter? Yes. -/
theorem increment_increases : contract ⊨ increases COUNTER :=
  contract_models fun _ _ => by grind

/-- By how much? Exactly one. -/
theorem increment_adds_one : contract ⊨ changesBy COUNTER one :=
  contract_models fun _ _ => by grind

/-- What does it return? The new count. -/
theorem increment_returns_count : contract ⊨ returns COUNTER :=
  contract_models fun _ _ => by grind

/-- Does it change any other variable? No. The frame rule does the work;
    `grind` only checks that the slot read is not the slot written. -/
theorem increment_touches_only_counter :
    contract ⊨ ∀ₛ name, (unchanged (var name : Term Int)).except fun _ => name = "COUNTER" :=
  contract_models fun st h name => by
    by_cases hn : name = "COUNTER"
    · grind
    · exact Or.inr ((var name : Term Int).frame (contract.framed _ (by simp [contract]) st h)
        fun _ _ _ => by grind [var])

/-- Who can call it? Anyone, as long as the counter is below `u32::MAX`.
    `grind` cannot invent the step, so we give it; `grind` checks it. -/
theorem anyone_can_increment (s : Storage) (who : Addr) (h : count s < U32_MAX) :
    ∃ st, increment st ∧ st.pre = s ∧ st.call.caller = who :=
  ⟨{ call   := { caller := who, args := ⟨0, 0⟩, holders := [] }
     pre    := s
     post   := s.set (.var "COUNTER") (.int (count s + 1))
     writes := [.var "COUNTER"]
     ret    := .int (count s + 1) }, by grind⟩

/-- What happens at `u32::MAX`? The call fails, so storage stays as it is. -/
theorem increment_fails_at_max (st : Step) (h : count st.pre = U32_MAX) : ¬ increment st := by
  grind

def inU32 : Invariant := fun s => 0 ≤ count s ∧ count s ≤ U32_MAX

/-- A freshly deployed contract: `COUNTER` not set yet. -/
def fresh : Invariant := fun s => s (.var "COUNTER") = .none

/-- After any sequence of calls from a fresh deploy, is the counter a valid u32? Yes. -/
theorem counter_fits_u32 {s : Storage} (h : contract.Reachable fresh s) : inU32 s :=
  contract.invariant inU32
    (by grind [inU32, fresh, count, Query.read, U32_MAX])
    (contract_models fun _ _ => by grind [inU32, preserves]) h

end Increment.Grind
