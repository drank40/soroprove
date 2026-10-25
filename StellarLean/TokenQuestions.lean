import StellarLean.Token

/-
  Questions about the token contract (modelled in `StellarLean/Token.lean`).
  Each theorem statement is a question; its proof is the answer.
-/

namespace Token

open Query
open Spec (Addr Args St Eff Entry applyAll)

/-! ## Questions about the token, answered

  Each statement is the question; the proof is the answer. -/

/-- Is the caller's balance reduced when a transfer happens? Yes, by exactly the amount. -/
theorem transfer_charges_caller : Spec.transfer.exec ⊨ changesBy balance[caller] (- amount ·) :=
  Spec.Entry.models fun s c a s' _ h => by
    obtain ⟨hreq, rfl⟩ := Spec.Entry.run_some h
    simp only [Spec.transfer, List.all_cons, List.all_nil, Bool.and_true, Bool.and_eq_true,
      decide_eq_true_eq] at hreq
    simp [changesBy, caller, amount, Spec.applyAll_bal, Spec.transfer, hreq.2.1]

theorem transfer_reduces_caller : Spec.transfer.exec ⊨ decreases balance[caller] := by
  intro st h
  have hc := transfer_charges_caller st h
  obtain ⟨s, c, a, s', _, hr, rfl⟩ := h
  obtain ⟨hreq, -⟩ := Spec.Entry.run_some hr
  simp only [Spec.transfer, List.all_cons, List.all_nil, Bool.and_true, Bool.and_eq_true,
    decide_eq_true_eq] at hreq
  simp only [changesBy, decreases, amount, step_call] at hc ⊢
  omega

/-- Can a transfer reduce anyone else's balance? No. -/
theorem transfer_spares_others :
    Spec.transfer.exec ⊨ ∀ₛ user, (neverDecreases balance[user]).except (isCaller user) :=
  Spec.Entry.models fun s c a s' hnd h user => by
    by_cases hu : user = c
    · exact Or.inl hu
    · exact Or.inr (by
        simpa [neverDecreases] using Spec.transfer_not_debited s c a s' hnd h user hu)

/-- Does a transfer touch any balance besides the caller's and the recipient's?
    No, and the frame rule answers it without looking at what transfer computes. -/
theorem transfer_touches_two :
    Spec.transfer.exec ⊨ ∀ₛ user,
      (unchanged balance[user]).except (isCaller user ∨ₛ isRecipient user) := by
  rintro _ ⟨s, c, a, s', -, h, rfl⟩ user
  by_cases hu : user = c ∨ user = a.to
  · exact Or.inl hu
  · refine Or.inr ((balance[user] : Term Int).frame (Spec.Entry.step_framed h) fun k hr hw => ?_)
    subst hr
    simp [Spec.Entry.step, Spec.transfer, balance] at hw
    exact hu hw

/-- Does a transfer change the total supply? No. -/
theorem transfer_keeps_supply : Spec.transfer.exec ⊨ unchanged balance.total :=
  Spec.Entry.models fun s c a s' hnd h => by
    show balance.total.get { caller := c, args := a, holders := s.holders } s'.store = balance.total.get { caller := c, args := a, holders := s.holders } s.store
    rw [total_store _ s' (holders_of_run h).symm, total_store _ s rfl]
    exact Spec.transfer_conserves s c a s' hnd h

/-- How much does a mint add to the supply? Exactly the amount. -/
theorem mint_adds_amount : Spec.mint.exec ⊨ changesBy balance.total amount :=
  Spec.Entry.models fun s c a s' hnd h => by
    show balance.total.get { caller := c, args := a, holders := s.holders } s'.store
      = balance.total.get { caller := c, args := a, holders := s.holders } s.store + a.amt
    rw [total_store _ s' (holders_of_run h).symm, total_store _ s rfl]
    exact Spec.mint_supply s c a s' hnd h

/-- Who can mint? Only the owner. -/
theorem mint_needs_owner : Spec.mint.exec ⊨ signedBy owner :=
  Spec.Entry.models fun s c a s' hnd h =>
    (Spec.mint_only_owner s c a s' hnd h).symm

/-- Can anything replace the owner? No: no entry point writes it (frame rule). -/
theorem owner_fixed : token ⊨ unchanged owner :=
  token.frame owner fun e he st h k hk hw => by
    subst hk
    rcases token_cases he with rfl | rfl <;>
    · obtain ⟨_, _, _, _, _, _, rfl⟩ := h
      simp [Spec.Entry.step] at hw

/-- Over the whole contract: the supply changes only when the owner signs. -/
theorem supply_only_by_owner :
    token ⊨ (unchanged balance.total).except (signedBy owner) := by
  intro e he
  rcases token_cases he with rfl | rfl
  · exact fun st h => Or.inr (transfer_keeps_supply st h)
  · exact fun st h => Or.inl (mint_needs_owner st h)

/-- Over the whole contract: only the caller can lose balance. -/
theorem token_no_debit :
    token ⊨ ∀ₛ user, (neverDecreases balance[user]).except (isCaller user) := by
  intro e he
  rcases token_cases he with rfl | rfl
  · exact transfer_spares_others
  · exact Spec.Entry.models fun s c a s' hnd h user => by
      by_cases hu : user = c
      · exact Or.inl hu
      exact Or.inr (by
      simpa [neverDecreases] using Spec.mint_not_debited s c a s' hnd h user hu)

/-! ## An invariant: balances never go negative -/

def balancesNonneg : Invariant := fun s => ∀ a, 0 ≤ balance.read s a

theorem transfer_keeps_nonneg :
    Spec.transfer.Post (fun s _ _ s' => (∀ k, 0 ≤ s.bal k) → ∀ k, 0 ≤ s'.bal k) := by
  unpack Spec.transfer
  obtain ⟨_, hne, hfund, -, -⟩ := hreq
  intro hs k
  have h0 := hs k
  rw [Spec.applyAll_bal]
  by_cases hkc : k = c
  · subst hkc
    simp [Spec.transfer, hne] <;> omega
  · by_cases hkt : k = a.to
    · subst hkt
      simp [Spec.transfer, hkc] <;> omega
    · simp [Spec.transfer, hkc, hkt] <;> omega

theorem mint_keeps_nonneg :
    Spec.mint.Post (fun s _ _ s' => (∀ k, 0 ≤ s.bal k) → ∀ k, 0 ≤ s'.bal k) := by
  unpack Spec.mint
  obtain ⟨_, hpos, _⟩ := hreq
  intro hs k
  have h0 := hs k
  rw [Spec.applyAll_bal]
  by_cases hkt : k = a.to
  · subst hkt
    simp [Spec.mint] <;> omega
  · simp [Spec.mint, hkt] <;> omega

theorem nonneg_preserved {e : Entry}
    (h : e.Post (fun s _ _ s' => (∀ k, 0 ≤ s.bal k) → ∀ k, 0 ≤ s'.bal k)) :
    e.exec ⊨ preserves balancesNonneg :=
  Spec.Entry.models fun s c a s' hnd hr hs k => by
    simpa [balancesNonneg] using h s c a s' hnd hr (fun k => by simpa using hs k) k

/-- Initial storage: every balance is zero. -/
def zeroBalances : Invariant := fun s => ∀ a, balance.read s a = 0

/-- Can a balance ever go negative, after any sequence of calls? No. -/
theorem balances_never_negative {s : Storage} (h : token.Reachable zeroBalances s) :
    balancesNonneg s := by
  refine token.invariant balancesNonneg (fun _ h0 a => by rw [h0 a]; exact Int.le_refl 0) ?_ h
  intro e he
  rcases token_cases he with rfl | rfl
  · exact nonneg_preserved transfer_keeps_nonneg
  · exact nonneg_preserved mint_keeps_nonneg

end Token
