-- Proofs over the generated `liquidity_pool.lean` model (appended to it by check.sh).
open Contract

/-- `withdraw` burns exactly `share_amount` of the caller's shares. -/
theorem withdraw_burns_shares (st : Step) (h : withdraw st) :
    st.post (.entry "Shares" (st.call.argA "to"))
      = st.pre (.entry "Shares" (st.call.argA "to")) - st.call.arg "share_amount" := by
  obtain ⟨_, _, _, _, _, _, _, hpost, _, _⟩ := h
  rw [hpost]; simp [xfer, Storage.set]

/-- `withdraw` only moves token A between the pool and the caller. -/
theorem withdraw_conserves_A (st : Step) (h : withdraw st) (hp : st.call.argA "to" ≠ pool) :
    bal "TokenA" st.post pool + bal "TokenA" st.post (st.call.argA "to")
      = bal "TokenA" st.pre pool + bal "TokenA" st.pre (st.call.argA "to") := by
  obtain ⟨_, _, _, _, _, _, _, hpost, _, _⟩ := h
  rw [hpost]; simp [xfer, bal, Storage.set, hp, Ne.symm hp]; omega

/-- After `withdraw`, the stored reserve A is the pool's actual token A balance
    (the reserve is written from the balance read, minus what was paid out). -/
theorem withdraw_syncs_reserve_A (st : Step) (h : withdraw st) (hp : st.call.argA "to" ≠ pool) :
    st.post (.var "ReserveA") = bal "TokenA" st.post pool := by
  obtain ⟨_, _, _, _, _, _, _, hpost, _, _⟩ := h
  rw [hpost]; simp [xfer, bal, Storage.set, hp, Ne.symm hp]
