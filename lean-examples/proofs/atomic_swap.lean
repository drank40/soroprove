-- Proofs over the generated `atomic_swap.lean` model (appended to it by check.sh).
open Contract

/-- In a swap of two distinct tokens between two distinct parties, `a` pays
    exactly `min_a_for_b` of token A (the deposit of `amount_a` is partly refunded). -/
theorem swap_a_pays_exactly (st : Step) (h : swap st)
    (hab : swap.a st ≠ swap.b st) (hap : swap.a st ≠ pool st) (hbp : swap.b st ≠ pool st)
    (htok : swap.token_a st ≠ swap.token_b st) :
    bal (swap.token_a st) st.post (swap.a st) = bal (swap.token_a st) st.pre (swap.a st) - swap.min_a_for_b st := by
  obtain ⟨_, _, _, _, _, _, hpost, _, _⟩ := h
  simp at hab hap hbp htok
  rw [hpost]
  simp [xfer, bal, Storage.set, hab, hap, hbp, htok, Ne.symm hab, Ne.symm hap, Ne.symm hbp, Ne.symm htok]
  all_goals omega

/-- ... and `b` receives exactly that amount. -/
theorem swap_b_receives_exactly (st : Step) (h : swap st)
    (hab : swap.a st ≠ swap.b st) (hap : swap.a st ≠ pool st) (hbp : swap.b st ≠ pool st)
    (htok : swap.token_a st ≠ swap.token_b st) :
    bal (swap.token_a st) st.post (swap.b st) = bal (swap.token_a st) st.pre (swap.b st) + swap.min_a_for_b st := by
  obtain ⟨_, _, _, _, _, _, hpost, _, _⟩ := h
  simp at hab hap hbp htok
  rw [hpost]
  simp [xfer, bal, Storage.set, hab, hap, hbp, htok, Ne.symm hab, Ne.symm hap, Ne.symm hbp, Ne.symm htok]
  all_goals omega

/-- The swap contract keeps nothing: its token A balance is unchanged. -/
theorem swap_pool_keeps_nothing (st : Step) (h : swap st)
    (hab : swap.a st ≠ swap.b st) (hap : swap.a st ≠ pool st) (hbp : swap.b st ≠ pool st)
    (htok : swap.token_a st ≠ swap.token_b st) :
    bal (swap.token_a st) st.post (pool st) = bal (swap.token_a st) st.pre (pool st) := by
  obtain ⟨_, _, _, _, _, _, hpost, _, _⟩ := h
  simp at hab hap hbp htok
  rw [hpost]
  simp [xfer, bal, Storage.set, hab, hap, hbp, htok, Ne.symm hab, Ne.symm hap, Ne.symm hbp, Ne.symm htok]
  all_goals omega
