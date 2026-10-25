import Spec.Invariants

open Contract Spec

namespace Locked

theorem no_replay : ∀ s, Reach s → s.used.Nodup := by
  intro s h
  induction h with
  | init => exact List.nodup_nil
  | step a _ g ih =>
    cases a with
    | withdraw amt n ok => exact List.nodup_cons.2 ⟨g.2.2.1, ih⟩
    | _ => exact ih

/-- The inductive strengthening of `Solvent`: the vault holds exactly what is left. -/
theorem books : ∀ s, Reach s → s.vault = s.deposited - s.withdrawn - s.pulled ∧ 0 ≤ s.vault := by
  intro s h
  induction h with
  | init => simp [Contract.init]
  | step a _ g ih =>
    cases a <;> simp only [Contract.guard, Contract.step] at g ⊢ <;> omega

theorem solvent : ∀ s, Reach s → Solvent s := by
  intro s h
  have := books s h
  simp only [Solvent]; omega

theorem key_owner_only : ∀ s a, Reach s → guard s a → (step s a).pubKey ≠ s.pubKey →
    ∃ k, a = .setPubKey s.owner k := by
  intro s a _ g hk
  cases a with
  | setPubKey c k => exact ⟨k, by simp only [Contract.guard] at g; rw [g]⟩
  | _ => exact absurd rfl hk

theorem withdraw_live : ∃ s, Reach s ∧ 0 < s.withdrawn := by
  have h1 := Reach.step (.deposit 1) (Reach.init 0 0) (by simp [Contract.guard])
  have h2 := Reach.step (.withdraw 1 0 true) h1 (by simp [Contract.guard, Contract.step, Contract.init])
  exact ⟨_, h2, by simp [Contract.step, Contract.init]⟩

end Locked
