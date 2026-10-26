-- Proofs over the generated `timelock.lean` model (appended to it by check.sh).
-- `ClaimableBalance` (with its nested `TimeBound`) is stored field by field
-- under `Balance`; `.has k` is the presence bit `has()` reads.
open Contract

/-- `claim` pays the claimant exactly the recorded amount, in the recorded token. -/
theorem claim_pays_recorded (st : Step) (h : claim st) (hne : claim.claimant st ≠ pool st) :
    bal (st.pre Balance.token) st.post (claim.claimant st)
      = bal (st.pre Balance.token) st.pre (claim.claimant st) + st.pre Balance.amount := by
  obtain ⟨u, h⟩ := h
  simp at hne
  rw [h.post]; simp [xfer, bal, Storage.set, hne]

/-! ### Over whole runs, with anything happening around the contract

`Run me s t`: the contract at `me` goes from `s` to `t` through its own calls,
interleaved with any outside activity (`Outside`): other people's transfers,
tokens sent to the contract, expiring temporary entries. -/

/-- Funded / claimed state: once funded, `Init` stays set, and once claimed,
    `Balance` stays gone. -/
def Settled (s : Storage) : Prop := s (.has Init) = 1 ∧ s (.has Balance) ≠ 1

/-- Whatever happens, a settled contract stays settled: neither `deposit` (needs
    `Init` unset) nor `claim` (needs `Balance` set) can run again, and nothing
    outside touches the contract's (instance) storage. -/
theorem settled_stays (me : Addr) {s t : Storage} (r : Run me s t) (h : Settled s) : Settled t := by
  induction r with
  | refl => exact h
  | call st _ _ he ih =>
    simp only [entries, List.mem_cons, List.mem_nil_iff, or_false] at he
    obtain ⟨e, he, hst⟩ := he
    rcases he with rfl | rfl
    · obtain ⟨u, hc⟩ := hst; exact absurd hc.gate1 ih.2
    · obtain ⟨u, hd⟩ := hst; exact absurd ih.1 hd.gate2
  | outside _ ho ih =>
    have hi := ho (.has Init); have hb := ho (.has Balance)
    simp [temporary] at hi hb
    exact ⟨hi ▸ ih.1, hb ▸ ih.2⟩

/-- `Balance` is only ever stored together with `Init` (`deposit` sets both):
    true of a fresh contract, and kept by every run. -/
def Wf (s : Storage) : Prop := s (.has Balance) = 1 → s (.has Init) = 1

theorem wf_stays (me : Addr) {s t : Storage} (r : Run me s t) (h : Wf s) : Wf t := by
  induction r with
  | refl => exact h
  | call st _ _ he ih =>
    simp only [entries, List.mem_cons, List.mem_nil_iff, or_false] at he
    obtain ⟨e, he, hst⟩ := he
    rcases he with rfl | rfl
    · obtain ⟨u, hc⟩ := hst; intro hb; rw [hc.post] at hb; simp [Storage.set] at hb
    · obtain ⟨u, hd⟩ := hst; intro _; rw [hd.post]; simp [Storage.set]
  | outside _ ho ih =>
    have hi := ho (.has Init); have hb := ho (.has Balance)
    simp [temporary] at hi hb
    intro h'; simp only [Wf, Init, Balance] at ih h' ⊢; rw [hi]; exact ih (by rw [← hb]; exact h')

/-- A claim (on a well-formed state) settles the contract. -/
theorem claim_settles (st : Step) (h : claim st) (hw : Wf st.pre) : Settled st.post := by
  obtain ⟨u, h⟩ := h
  have hi := hw h.gate1
  rw [h.post]; simp only [Settled, Init, Balance] at hi ⊢; simp [Storage.set, xfer, bal, hi]

/-- So, starting from a fresh contract, a balance is claimed at most once,
    whatever happens before, between and around the two calls. -/
theorem claim_once_ever (me : Addr) (s0 : Storage) (fresh : s0 (.has Balance) ≠ 1)
    (a b : Step) (r0 : Run me s0 a.pre) (ha : claim a) (r : Run me a.post b.pre) (hb : claim b) : False := by
  have hw : Wf a.pre := wf_stays me r0 (fun h => absurd h fresh)
  have hs := settled_stays me r (claim_settles a ha hw)
  obtain ⟨u, hb⟩ := hb
  exact hs.2 hb.gate1

/-- Likewise the contract is funded at most once. -/
theorem deposit_once_ever (me : Addr) (a b : Step) (ha : deposit a) (r : Run me a.post b.pre) (hb : deposit b) : False := by
  obtain ⟨u, ha⟩ := ha
  have hi : a.post (.has Init) = 1 := by rw [ha.post]; simp [Storage.set]
  -- Init is never cleared: by `settled_stays`'s argument, restricted to Init.
  have keep : ∀ {s t}, Run me s t → s (.has Init) = 1 → t (.has Init) = 1 := by
    intro s t r h
    induction r with
    | refl => exact h
    | call st _ _ he ih =>
      simp only [entries, List.mem_cons, List.mem_nil_iff, or_false] at he
      obtain ⟨e, he, hst⟩ := he
      rcases he with rfl | rfl
      · obtain ⟨u, hc⟩ := hst; rw [hc.post]; simp only [Init] at ih ⊢; simp [Storage.set, xfer, bal, ih]
      · obtain ⟨u, hd⟩ := hst; exact absurd ih hd.gate2
    | outside _ ho ih => have hi := ho (.has Init); simp [temporary] at hi; simp only [Init] at ih ⊢; rw [hi]; exact ih
  obtain ⟨u', hb⟩ := hb
  exact hb.gate2 (keep r hi)
