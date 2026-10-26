-- Proofs over the generated `liquidity_pool.lean` model (appended to it by check.sh).
-- Token ledgers are keyed by the token address stored in `TokenA` / `TokenB`.
open Contract

/-- `withdraw` burns exactly `share_amount` of the caller's shares. -/
theorem withdraw_burns_shares (st : Step) (h : withdraw st) :
    getOr0 st.post (Shares (withdraw.to st)) = getOr0 st.pre (Shares (withdraw.to st)) - withdraw.share_amount st := by
  obtain ⟨_, _, _, _, _, _, _, hpost, _⟩ := h
  rw [hpost]; simp [getOr0, xfer, bal, Storage.set]

/-- `withdraw` pays out `withdraw.amt1` of token A: it moves between the pool
    and the caller, and nothing else changes hands (two distinct tokens). -/
theorem withdraw_conserves_A (st : Step) (h : withdraw st) (hp : withdraw.to st ≠ pool st)
    (htok : st.pre TokenA ≠ st.pre TokenB) :
    bal (st.pre TokenA) st.post (pool st) = bal (st.pre TokenA) st.pre (pool st) - withdraw.amt1 st ∧
    bal (st.pre TokenA) st.post (withdraw.to st) = bal (st.pre TokenA) st.pre (withdraw.to st) + withdraw.amt1 st := by
  obtain ⟨_, _, _, _, _, _, _, hpost, _⟩ := h
  simp at hp htok
  rw [hpost]; simp [xfer, bal, Storage.set, hp, Ne.symm hp, htok, Ne.symm htok]

/-- After `withdraw`, the stored reserve A is the pool's actual token A balance. -/
theorem withdraw_syncs_reserve_A (st : Step) (h : withdraw st) (hp : withdraw.to st ≠ pool st)
    (htok : st.pre TokenA ≠ st.pre TokenB) :
    st.post ReserveA = bal (st.pre TokenA) st.post (pool st) := by
  obtain ⟨_, _, _, _, _, _, _, hpost, _⟩ := h
  simp at hp htok
  rw [hpost]; simp [xfer, bal, Storage.set, hp, Ne.symm hp, htok, Ne.symm htok]
