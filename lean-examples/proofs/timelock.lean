-- Proofs over the generated `timelock.lean` model (appended to it by check.sh).
-- `ClaimableBalance` (with its nested `TimeBound`) is stored field by field;
-- `.has k` is the presence bit `has()` reads and `set`/`remove` write.
open Contract

/-- The contract can be funded only once. -/
theorem deposit_once (a b : Step) (ha : deposit a) (hb : deposit b) (hseq : b.pre = a.post) : False := by
  obtain ⟨_, _, _, _, _, hpost, _⟩ := ha
  obtain ⟨_, _, _, _, hnot, _⟩ := hb
  rw [hseq, hpost] at hnot; simp [Storage.set] at hnot

/-- A balance can be claimed only once: `claim` removes it. -/
theorem claim_once (a b : Step) (ha : claim a) (hb : claim b) (hseq : b.pre = a.post) : False := by
  obtain ⟨_, _, _, _, _, hpost, _⟩ := ha
  obtain ⟨_, _, _, hhas, _⟩ := hb
  rw [hseq, hpost] at hhas; simp [Storage.set] at hhas

/-- `claim` pays the claimant exactly the recorded amount, in the recorded token. -/
theorem claim_pays_recorded (st : Step) (h : claim st) (hne : st.call.argA "claimant" ≠ pool) :
    bal "Balance.token" st.post (st.call.argA "claimant")
      = bal "Balance.token" st.pre (st.call.argA "claimant") + st.pre (.fld (.var "Balance") "amount") := by
  obtain ⟨_, _, _, _, _, hpost, _⟩ := h
  rw [hpost]; simp [xfer, bal, Storage.set, hne]
