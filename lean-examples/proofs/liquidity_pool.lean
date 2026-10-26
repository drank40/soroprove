-- Proofs over the generated `liquidity_pool.lean` model (appended to it by check.sh).
-- Token ledgers are keyed by the token address stored in `TokenA` / `TokenB`.
open Contract

/-- `withdraw` burns exactly `share_amount` of the caller's shares. -/
theorem withdraw_burns_shares (st : Step) (h : withdraw st) :
    getOr0 st.post (.entry "Shares" (st.call.argA "to"))
      = getOr0 st.pre (.entry "Shares" (st.call.argA "to")) - st.call.arg "share_amount" := by
  obtain ⟨_, _, _, _, _, _, _, hpost, _⟩ := h
  rw [hpost]; simp [getOr0, xfer, bal, Storage.set]

/-- `withdraw` only moves token A between the pool and the caller (for a pool of
    two distinct tokens). -/
theorem withdraw_conserves_A (st : Step) (h : withdraw st) (hp : st.call.argA "to" ≠ st.call.self)
    (htok : st.pre (.var "TokenA") ≠ st.pre (.var "TokenB")) :
    bal (st.pre (.var "TokenA")) st.post st.call.self + bal (st.pre (.var "TokenA")) st.post (st.call.argA "to")
      = bal (st.pre (.var "TokenA")) st.pre st.call.self + bal (st.pre (.var "TokenA")) st.pre (st.call.argA "to") := by
  obtain ⟨_, _, _, _, _, _, _, hpost, _⟩ := h
  rw [hpost]; simp [xfer, bal, Storage.set, hp, Ne.symm hp, htok, Ne.symm htok]; omega

/-- After `withdraw`, the stored reserve A is the pool's actual token A balance
    (the reserve is written from the balance read, minus what was paid out). -/
theorem withdraw_syncs_reserve_A (st : Step) (h : withdraw st) (hp : st.call.argA "to" ≠ st.call.self)
    (htok : st.pre (.var "TokenA") ≠ st.pre (.var "TokenB")) :
    st.post (.var "ReserveA") = bal (st.pre (.var "TokenA")) st.post st.call.self := by
  obtain ⟨_, _, _, _, _, _, _, hpost, _⟩ := h
  rw [hpost]; simp [xfer, bal, Storage.set, hp, Ne.symm hp, htok, Ne.symm htok]
