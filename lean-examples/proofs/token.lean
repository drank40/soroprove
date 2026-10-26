-- Proofs over the generated `token.lean` model (appended to it by check.sh).
-- Balances are `get(Balance(a)).unwrap_or(0)`: `getOr0 s (Balance a)`.
open Contract

/-- A transfer between two different holders moves value; it creates none. -/
theorem transfer_conserves (st : Step) (h : transfer st)
    (hne : transfer.«from» st ≠ transfer.to_muxed st) :
    getOr0 st.post (Balance (transfer.«from» st)) + getOr0 st.post (Balance (transfer.to_muxed st))
      = getOr0 st.pre (Balance (transfer.«from» st)) + getOr0 st.pre (Balance (transfer.to_muxed st)) := by
  simp at hne
  rw [h.post]; simp [getOr0, hne, Ne.symm hne]; omega

/-- A self-transfer leaves the holder's balance unchanged (the second read sees
    the first write: `transfer.s2` reads `transfer.s1`). -/
theorem transfer_self_noop (st : Step) (h : transfer st)
    (heq : transfer.«from» st = transfer.to_muxed st) :
    getOr0 st.post (Balance (transfer.«from» st)) = getOr0 st.pre (Balance (transfer.«from» st)) := by
  simp at heq
  rw [h.post]; simp [getOr0, heq]

/-- No one can spend more than they hold. -/
theorem transfer_needs_balance (st : Step) (h : transfer st) :
    transfer.amount st ≤ getOr0 st.pre (Balance (transfer.«from» st)) := by
  have := h.gate2; omega
