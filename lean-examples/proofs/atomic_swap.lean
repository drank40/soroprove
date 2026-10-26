-- Proofs over the generated `atomic_swap.lean` model (appended to it by check.sh).
open Contract

/-- In a swap of two distinct tokens between two distinct parties, `a` pays
    exactly `min_a_for_b` of token A (the deposit of `amount_a` is partly refunded). -/
theorem swap_a_pays_exactly (st : Step) (h : swap st)
    (hab : st.call.argA "a" ≠ st.call.argA "b") (hap : st.call.argA "a" ≠ st.call.self) (hbp : st.call.argA "b" ≠ st.call.self)
    (htok : st.call.argA "token_a" ≠ st.call.argA "token_b") :
    bal (st.call.argA "token_a") st.post (st.call.argA "a")
      = bal (st.call.argA "token_a") st.pre (st.call.argA "a") - st.call.arg "min_a_for_b" := by
  obtain ⟨_, _, _, _, _, _, hpost, _, _⟩ := h
  rw [hpost]
  simp [xfer, bal, Storage.set, hab, hap, hbp, htok, Ne.symm hab, Ne.symm hap, Ne.symm hbp, Ne.symm htok]
  all_goals omega

/-- ... and `b` receives exactly that amount. -/
theorem swap_b_receives_exactly (st : Step) (h : swap st)
    (hab : st.call.argA "a" ≠ st.call.argA "b") (hap : st.call.argA "a" ≠ st.call.self) (hbp : st.call.argA "b" ≠ st.call.self)
    (htok : st.call.argA "token_a" ≠ st.call.argA "token_b") :
    bal (st.call.argA "token_a") st.post (st.call.argA "b")
      = bal (st.call.argA "token_a") st.pre (st.call.argA "b") + st.call.arg "min_a_for_b" := by
  obtain ⟨_, _, _, _, _, _, hpost, _, _⟩ := h
  rw [hpost]
  simp [xfer, bal, Storage.set, hab, hap, hbp, htok, Ne.symm hab, Ne.symm hap, Ne.symm hbp, Ne.symm htok]
  all_goals omega

/-- The swap contract keeps nothing: its token A balance is unchanged. -/
theorem swap_pool_keeps_nothing (st : Step) (h : swap st)
    (hab : st.call.argA "a" ≠ st.call.argA "b") (hap : st.call.argA "a" ≠ st.call.self) (hbp : st.call.argA "b" ≠ st.call.self)
    (htok : st.call.argA "token_a" ≠ st.call.argA "token_b") :
    bal (st.call.argA "token_a") st.post st.call.self = bal (st.call.argA "token_a") st.pre st.call.self := by
  obtain ⟨_, _, _, _, _, _, hpost, _, _⟩ := h
  rw [hpost]
  simp [xfer, bal, Storage.set, hab, hap, hbp, htok, Ne.symm hab, Ne.symm hap, Ne.symm hbp, Ne.symm htok]
  all_goals omega
