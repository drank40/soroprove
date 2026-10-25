import StellarLean.Increment

/-
  Questions about Soroban's increment contract (modelled in
  `StellarLean/Increment.lean`). Each theorem statement is a question;
  its proof is the answer.
-/

namespace Increment

open Query
open Spec (Addr)

/-! ## Questions, answered -/

/-- Does every call increase the counter? Yes. -/
theorem increment_increases : contract ⊨ increases COUNTER :=
  contract_models fun st h => by
    simp only [increases, get_COUNTER, count_after h]
    omega

/-- By how much? Exactly one. -/
theorem increment_adds_one : contract ⊨ changesBy COUNTER one :=
  contract_models fun st h => by
    simp only [changesBy, get_COUNTER, count_after h, one]

/-- What does it return? The new count. -/
theorem increment_returns_count : contract ⊨ returns COUNTER :=
  contract_models fun st h => by
    simp only [returns, get_COUNTER, count_after h]
    rw [h.2.2.2]
    rfl

/-- Does it change any other variable? No, and the frame rule answers it
    without looking at what increment computes. -/
theorem increment_touches_only_counter :
    contract ⊨ ∀ₛ name, (unchanged (var name : Term Int)).except fun _ => name = "COUNTER" :=
  contract_models fun st h name => by
    by_cases hn : name = "COUNTER"
    · exact Or.inl hn
    · refine Or.inr ((var name : Term Int).frame (contract.framed _ (by simp [contract]) st h)
        fun k hr hw => ?_)
      rw [h.2.1] at hw
      simp only [List.mem_singleton] at hw
      subst hw
      exact hn (show "COUNTER" = name by simpa [var] using hr).symm

/-- Who can call it? Anyone: no `require_auth`, so any caller succeeds
    as long as the counter is below `u32::MAX`. -/
theorem anyone_can_increment (s : Storage) (who : Addr) (h : count s < U32_MAX) :
    ∃ st, increment st ∧ st.pre = s ∧ st.call.caller = who :=
  ⟨{ call   := { caller := who, args := ⟨0, 0⟩, holders := [] }
     pre    := s
     post   := s.set (.var "COUNTER") (.int (count s + 1))
     writes := [.var "COUNTER"]
     ret    := .int (count s + 1) },
   ⟨h, rfl, rfl, rfl⟩, rfl, rfl⟩

/-- What happens at `u32::MAX`? The call fails, so storage stays as it is. -/
theorem increment_fails_at_max (st : Step) (h : count st.pre = U32_MAX) : ¬ increment st :=
  fun hi => by have := hi.1; omega

/-! ## An invariant: the counter always fits in a u32 -/

def inU32 : Invariant := fun s => 0 ≤ count s ∧ count s ≤ U32_MAX

/-- A freshly deployed contract: `COUNTER` not set yet. -/
def fresh : Invariant := fun s => s (.var "COUNTER") = .none

/-- After any sequence of calls from a fresh deploy, is the counter a valid u32? Yes. -/
theorem counter_fits_u32 {s : Storage} (h : contract.Reachable fresh s) : inU32 s := by
  refine contract.invariant inU32 (fun s h0 => ?_) (contract_models fun st hi hpre => ?_) h
  · have h0 : s (.var "COUNTER") = .none := h0
    simp [inU32, count, Query.read, h0, U32_MAX]
  · have := hi.1
    simp only [inU32, count_after hi] at hpre ⊢
    omega

end Increment
