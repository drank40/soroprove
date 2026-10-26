-- Proofs over the generated `liquidity_pool.lean` model (appended to it by check.sh).
-- Token ledgers are keyed by the token address stored in `TokenA` / `TokenB`.
open Contract

/-- `withdraw` burns exactly `share_amount` of the caller's shares. -/
theorem withdraw_burns_shares (st : Step) (h : withdraw st) :
    getOr0 st.post (Shares (withdraw.to st)) = getOr0 st.pre (Shares (withdraw.to st)) - withdraw.share_amount st := by
  obtain ⟨u, h⟩ := h
  rw [h.post]; simp [getOr0]

/-- `withdraw` pays out `withdraw.amt1` of token A, from the pool to the caller
    (for a pool of two distinct tokens). -/
theorem withdraw_pays_A (st : Step) (h : withdraw st) (hp : withdraw.to st ≠ pool st)
    (htok : st.pre TokenA ≠ st.pre TokenB) :
    bal (st.pre TokenA) st.post (pool st) = bal (st.pre TokenA) st.pre (pool st) - withdraw.amt1 st ∧
    bal (st.pre TokenA) st.post (withdraw.to st) = bal (st.pre TokenA) st.pre (withdraw.to st) + withdraw.amt1 st := by
  obtain ⟨u, h⟩ := h
  simp at hp htok
  rw [h.post]; simp [hp, Ne.symm hp, htok]

/-- After `withdraw`, the stored reserve A is the pool's actual token A balance. -/
theorem withdraw_syncs_reserve_A (st : Step) (h : withdraw st) (hp : withdraw.to st ≠ pool st)
    (htok : st.pre TokenA ≠ st.pre TokenB) :
    st.post ReserveA = bal (st.pre TokenA) st.post (pool st) := by
  obtain ⟨u, h⟩ := h
  simp at hp htok
  rw [h.post]; simp [Ne.symm hp, htok]

/-! ### Over whole runs, with anything happening around the pool -/

/-- The pool's books are backed: its two tokens are distinct, and each stored
    reserve is at most the pool's actual balance of that token. -/
def Backed (me : Addr) (s : Storage) : Prop :=
  s TokenA ≠ s TokenB ∧ s ReserveA ≤ bal (s TokenA) s me ∧ s ReserveB ≤ bal (s TokenB) s me

/-- No sequence of calls, interleaved with anything else on the ledger (other
    people's transfers, tokens sent straight to the pool), makes the reserves
    exceed what the pool actually holds. -/
theorem backed_stays (me : Addr) {s t : Storage} (r : Run me s t) (h : Backed me s) : Backed me t := by
  induction r with
  | refl => exact h
  | call st _ hme he ih =>
    simp only [entries, List.mem_cons, List.mem_nil_iff, or_false] at he
    obtain ⟨e, he, hst⟩ := he
    obtain ⟨hab, hA, hB⟩ := ih
    subst hme
    simp only [TokenA, TokenB, ReserveA, ReserveB, bal] at hab hA hB
    rcases he with rfl | rfl | rfl | rfl | rfl
    · -- balance_shares
      have h := hst.post; rw [h]; exact ⟨hab, hA, hB⟩
    · -- deposit
      obtain ⟨u, h⟩ := hst
      rw [h.post]; simp [Backed, Storage.set, xfer, bal, hab]
    · -- get_rsrvs
      obtain ⟨u, h⟩ := hst; rw [h.post]; exact ⟨hab, hA, hB⟩
    · -- swap
      have h := hst
      have h2 := h.xfer2
      rw [h.post]
      have hba : st.pre (.var "TokenB") ≠ st.pre (.var "TokenA") := Ne.symm hab
      simp [Backed, hab, hba] at h2 ⊢
      by_cases hb : st.call.arg "buy_a" = 0 <;> by_cases ht : st.call.argA "to" = st.call.self <;>
        simp [hb, ht] at h2 ⊢ <;> omega
    · -- withdraw
      obtain ⟨u, h⟩ := hst
      have h1 := h.xfer1; have h2 := h.xfer2
      rw [h.post]
      have hba : st.pre (.var "TokenB") ≠ st.pre (.var "TokenA") := Ne.symm hab
      simp [Backed, hab, hba] at h1 h2 ⊢
      by_cases ht : st.call.argA "to" = st.call.self <;> (try simp [ht] at h1 h2 ⊢) <;> omega
  | @outside t1 t2 _ ho ih =>
    obtain ⟨hab, hA, hB⟩ := ih
    have ha := ho TokenA; have hb := ho TokenB; have hra := ho ReserveA; have hrb := ho ReserveB
    simp [temporary] at ha hb hra hrb
    have hpa := ho (.bal (t1 TokenA) me); have hpb := ho (.bal (t1 TokenB) me)
    simp at hpa hpb
    simp only [Backed, TokenA, TokenB, ReserveA, ReserveB, bal] at ha hb hra hrb hab hA hB ⊢
    rw [ha, hb, hra, hrb]
    exact ⟨hab, by have := hpa; omega, by have := hpb; omega⟩
