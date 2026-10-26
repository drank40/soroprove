-- Proofs over the generated `token.lean` model (appended to it by check.sh).
open Contract

/-- A transfer between two different holders moves value; it creates none. -/
theorem transfer_conserves (st : Step) (h : transfer st)
    (hne : st.call.argA "from" ≠ st.call.argA "to_muxed") :
    st.post (.entry "Balance" (st.call.argA "from")) + st.post (.entry "Balance" (st.call.argA "to_muxed"))
      = st.pre (.entry "Balance" (st.call.argA "from")) + st.pre (.entry "Balance" (st.call.argA "to_muxed")) := by
  obtain ⟨_, _, _, _, _, hpost, _, _⟩ := h
  rw [hpost]; simp [Storage.set, hne, Ne.symm hne]; omega

/-- A self-transfer is a no-op on the holder's balance (the second read sees
    the first write — the model orders the two balance updates). -/
theorem transfer_self_noop (st : Step) (h : transfer st)
    (heq : st.call.argA "from" = st.call.argA "to_muxed") :
    st.post (.entry "Balance" (st.call.argA "from")) = st.pre (.entry "Balance" (st.call.argA "from")) := by
  obtain ⟨_, _, _, _, _, hpost, _, _⟩ := h
  rw [hpost]; simp [Storage.set, heq]

/-- No one can spend more than they hold. -/
theorem transfer_needs_balance (st : Step) (h : transfer st) :
    st.call.arg "amount" ≤ st.pre (.entry "Balance" (st.call.argA "from")) := by
  obtain ⟨_, _, _, _, hb, _⟩ := h; omega
