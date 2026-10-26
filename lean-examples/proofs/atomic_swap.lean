-- Proofs over the generated `atomic_swap.lean` model (appended to it by check.sh).
open Contract

/-- In a swap, party `a` ends up paying exactly `min_a_for_b` of token A
    (the deposit of `amount_a` is partly refunded). -/
theorem swap_a_pays_exactly (st : Step) (h : swap st)
    (hab : st.call.argA "a" ≠ st.call.argA "b") (hap : st.call.argA "a" ≠ pool) (hbp : st.call.argA "b" ≠ pool)
    (htok : toString (st.call.argA "token_a") ≠ toString (st.call.argA "token_b")) :
    bal (toString (st.call.argA "token_a")) st.post (st.call.argA "a")
      = bal (toString (st.call.argA "token_a")) st.pre (st.call.argA "a") - st.call.arg "min_a_for_b" := by
  obtain ⟨_, _, _, _, _, _, hpost, _, _⟩ := h
  -- `simp` unfolds `toString` on Int to `Int.repr`: state the hypothesis that way.
  have ht : Int.repr (st.call.argA "token_a") ≠ Int.repr (st.call.argA "token_b") := htok
  rw [hpost]
  simp [xfer, bal, Storage.set, hab, hap, hbp, ht, Ne.symm hab, Ne.symm hap, Ne.symm hbp, Ne.symm ht]
  all_goals omega

/-- ... and `b` receives exactly that amount. -/
theorem swap_b_receives_exactly (st : Step) (h : swap st)
    (hab : st.call.argA "a" ≠ st.call.argA "b") (hap : st.call.argA "a" ≠ pool) (hbp : st.call.argA "b" ≠ pool)
    (htok : toString (st.call.argA "token_a") ≠ toString (st.call.argA "token_b")) :
    bal (toString (st.call.argA "token_a")) st.post (st.call.argA "b")
      = bal (toString (st.call.argA "token_a")) st.pre (st.call.argA "b") + st.call.arg "min_a_for_b" := by
  obtain ⟨_, _, _, _, _, _, hpost, _, _⟩ := h
  -- `simp` unfolds `toString` on Int to `Int.repr`: state the hypothesis that way.
  have ht : Int.repr (st.call.argA "token_a") ≠ Int.repr (st.call.argA "token_b") := htok
  rw [hpost]
  simp [xfer, bal, Storage.set, hab, hap, hbp, ht, Ne.symm hab, Ne.symm hap, Ne.symm hbp, Ne.symm ht]
  all_goals omega

/-- The swap contract keeps nothing: its token A balance is unchanged. -/
theorem swap_pool_keeps_nothing (st : Step) (h : swap st)
    (hab : st.call.argA "a" ≠ st.call.argA "b") (hap : st.call.argA "a" ≠ pool) (hbp : st.call.argA "b" ≠ pool)
    (htok : toString (st.call.argA "token_a") ≠ toString (st.call.argA "token_b")) :
    bal (toString (st.call.argA "token_a")) st.post pool = bal (toString (st.call.argA "token_a")) st.pre pool := by
  obtain ⟨_, _, _, _, _, _, hpost, _, _⟩ := h
  -- `simp` unfolds `toString` on Int to `Int.repr`: state the hypothesis that way.
  have ht : Int.repr (st.call.argA "token_a") ≠ Int.repr (st.call.argA "token_b") := htok
  rw [hpost]
  simp [xfer, bal, Storage.set, hab, hap, hbp, ht, Ne.symm hab, Ne.symm hap, Ne.symm hbp, Ne.symm ht]
  all_goals omega
