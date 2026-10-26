/-
The locked statements. A solution must prove theorems with exactly these names and types
(checked by `Check.lean`); it may add any lemmas of its own.
-/
import Spec.Defs

open Contract Spec

namespace Locked

/-- One step leaves a non-signing user (other than the contract) untouched: their balance of
    every token and their pool shares. -/
theorem step_bystander (st : Step) (e : Step → Prop) (he : e ∈ entries) (h : e st) (u : Addr)
    (hself : u ≠ st.call.self) (hsig : u ∉ st.call.signers) :
    (∀ tok, bal tok st.post u = bal tok st.pre u) ∧
      st.post (.entry "Shares" u) = st.pre (.entry "Shares" u) := by
  have hs1 : st.call.self ≠ u := fun h => hself h.symm
  simp only [entries, List.mem_cons, List.not_mem_nil, or_false] at he
  rcases he with rfl | rfl | rfl | rfl | rfl
  · rw [h.post]; exact ⟨fun _ => rfl, rfl⟩
  · obtain ⟨_, h⟩ := h
    have hto : st.call.argA "to" ≠ u := fun e => hsig (e ▸ h.auth_to)
    rw [h.post]
    refine ⟨fun tok => ?_, ?_⟩
    · simp [bal, xfer, Storage.set_get, hto, hs1, hself, Ne.symm hto]
    · simp [bal, xfer, Storage.set_get, hto, hs1, hself, Ne.symm hto]
  · obtain ⟨_, h⟩ := h
    rw [h.post]; exact ⟨fun _ => rfl, rfl⟩
  · have hto : st.call.argA "to" ≠ u := fun e => hsig (e ▸ h.auth_to)
    rw [h.post]
    refine ⟨fun tok => ?_, ?_⟩
    · simp [bal, xfer, Storage.set_get, hto, hs1, hself, Ne.symm hto]
    · simp [bal, xfer, Storage.set_get, hto, hs1, hself, Ne.symm hto]
  · obtain ⟨_, h⟩ := h
    have hto : st.call.argA "to" ≠ u := fun e => hsig (e ▸ h.auth_to)
    rw [h.post]
    refine ⟨fun tok => ?_, ?_⟩
    · simp [bal, xfer, Storage.set_get, hto, hs1, hself, Ne.symm hto]
    · simp [bal, xfer, Storage.set_get, hto, hs1, hself, Ne.symm hto]

/-- No theft, across any sequence of calls: a user who never signs keeps exactly their
    balance of every token and their pool shares. -/
theorem bystander_safe : ∀ pool s tr t u, Run pool s tr t → Bystander pool u tr →
    (∀ tok, bal tok t u = bal tok s u) ∧ t (.entry "Shares" u) = s (.entry "Shares" u) := by
  intro pool s tr t u hr hb
  induction hr with
  | nil => exact ⟨fun _ => rfl, rfl⟩
  | cons st _ hself _ hent ih =>
    obtain ⟨hu, hns⟩ := hb
    obtain ⟨ih1, ih2⟩ := ih ⟨hu, fun st' h' => hns st' (List.mem_cons_of_mem _ h')⟩
    obtain ⟨e, he, h⟩ := hent
    obtain ⟨h1, h2⟩ := step_bystander st e he h u (hself ▸ hu) (hns st List.mem_cons_self)
    exact ⟨fun tok => (h1 tok).trans (ih1 tok), h2.trans ih2⟩

/-- A call changes a user's token balance only if that user signed it. -/
theorem balance_change_authorized : ∀ e ∈ entries, ∀ st tok u, e st → u ≠ st.call.self →
    bal tok st.post u ≠ bal tok st.pre u → u ∈ st.call.signers := by
  intro e he st tok u h hself hne
  refine Classical.byContradiction fun hs => ?_
  exact hne ((step_bystander st e he h u hself hs).1 tok)

/-- The arithmetic core of the product check: the fee-adjusted balances bound the new
    reserves from above and share their signs. -/
theorem prod_core (P xA xB a b : Int) (hP : 0 ≤ P) (h : 1000000 * P ≤ xA * xB)
    (ha1 : xA ≤ 1000 * a) (hb1 : xB ≤ 1000 * b)
    (ha2 : 0 ≤ a → 0 ≤ xA) (hb2 : 0 ≤ b → 0 ≤ xB)
    (ha3 : a < 0 → xA = 1000 * a) (hb3 : b < 0 → xB = 1000 * b)
    (ha4 : xA = 0 → a = 0) (hb4 : xB = 0 → b = 0) : P ≤ a * b := by
  have hm : (1000 * a) * (1000 * b) = 1000000 * (a * b) := by
    rw [Int.mul_assoc, Int.mul_left_comm a, ← Int.mul_assoc]; rfl
  by_cases sa : 0 ≤ a <;> by_cases sb : 0 ≤ b
  · have := Int.mul_le_mul ha1 hb1 (hb2 sb) (by omega)
    omega
  · have ea := ha2 sa
    have eb := hb3 (by omega)
    by_cases za : xA = 0
    · have := ha4 za; subst this; subst za; simp at h ⊢; omega
    · have : xA * xB < 0 := Int.mul_neg_of_pos_of_neg (by omega) (by omega)
      omega
  · have ea := ha3 (by omega)
    have eb := hb2 sb
    by_cases zb : xB = 0
    · have := hb4 zb; subst this; subst zb; simp at h ⊢; omega
    · have : xA * xB < 0 := Int.mul_neg_of_neg_of_pos (by omega) (by omega)
      omega
  · rw [ha3 (by omega), hb3 (by omega), hm] at h
    omega

theorem fee_facts (r d : Int) (hr : 0 ≤ r) :
    let x := 1000 * r + (if d > 0 then 997 * d else 1000 * d)
    x ≤ 1000 * (r + d) ∧ (0 ≤ r + d → 0 ≤ x) ∧ (r + d < 0 → x = 1000 * (r + d)) ∧
      (x = 0 → r + d = 0) := by
  intro x
  by_cases hd : d > 0 <;> simp [x, hd] <;> omega

theorem prod_key (rA rB bA bB iA iB : Int) (hA : 0 ≤ rA) (hB : 0 ≤ rB)
    (g : (1000 * rA + (if bA - rA - iA > 0 then 997 * (bA - rA - iA) else 1000 * (bA - rA - iA))) *
        (1000 * rB + (if bB - rB - iB > 0 then 997 * (bB - rB - iB) else 1000 * (bB - rB - iB)))
        ≥ rA * 1000 * (rB * 1000)) :
    rA * rB ≤ (bA - iA) * (bB - iB) := by
  obtain ⟨a1, a2, a3, a4⟩ := fee_facts rA (bA - rA - iA) hA
  obtain ⟨b1, b2, b3, b4⟩ := fee_facts rB (bB - rB - iB) hB
  have ea : rA + (bA - rA - iA) = bA - iA := by omega
  have eb : rB + (bB - rB - iB) = bB - iB := by omega
  rw [ea] at a1 a2 a3 a4
  rw [eb] at b1 b2 b3 b4
  have hm : rA * 1000 * (rB * 1000) = 1000000 * (rA * rB) := by
    rw [Int.mul_assoc rA 1000, Int.mul_left_comm 1000 rB, ← Int.mul_assoc]; omega
  rw [hm] at g
  exact prod_core _ _ _ _ _ (Int.mul_nonneg hA hB) g a1 b1 a2 b2 a3 b3 a4 b4

/-- No draining by swapping: from non-negative reserves, a swap never lowers the product
    of the stored reserves. -/
theorem swap_keeps_product : ∀ st, swap st → 0 ≤ reserveA st.pre → 0 ≤ reserveB st.pre →
    reserveA st.pre * reserveB st.pre ≤ reserveA st.post * reserveB st.post := by
  intro st h hA hB
  have g := h.gate3
  have pA : reserveA st.post = swap.new_ReserveA st := by
    rw [reserveA, h.post]; simp
  have pB : reserveB st.post = swap.new_ReserveB st := by
    rw [reserveB, h.post]; simp
  rw [pA, pB]
  exact prod_key _ _ _ _ _ _ hA hB g

/-- A witness swap: pool 10, trader 20, tokens A = 1 and B = 2, reserves 1000/1000 matching
    the pool's balances; the trader buys 1 of B (`buy_a = 0`) for 2 of A. -/
def liveCall : Call where
  fn := "swap"
  caller := 20
  self := 10
  arg := fun n => if n = "out" then 1 else if n = "in_max" then 100 else 0
  argA := fun _ => 20
  signers := [20]
  env := fun _ => 0

def livePre : Storage := fun k =>
  if k = .var "TokenA" then 1
  else if k = .var "TokenB" then 2
  else if k = .var "ReserveA" then 1000
  else if k = .var "ReserveB" then 1000
  else if k = .bal 1 20 then 100
  else if k = .bal 1 10 then 1000
  else if k = .bal 2 10 then 1000
  else 0

def liveStep0 : Step := { call := liveCall, pre := livePre, post := livePre, writes := [], ret := 2 }

/-- the write list `swap.Spec` expects for `liveStep0`. -/
def liveWrites (st : Step) : List Key :=
  [.bal (if (swap.buy_a st) ≠ 0 then (st.pre TokenB) else (st.pre TokenA)) (swap.to st), .bal (if (swap.buy_a st) ≠ 0 then (st.pre TokenB) else (st.pre TokenA)) (pool st), .bal (if (swap.buy_a st) = 0 then (st.pre TokenB) else (st.pre TokenA)) (pool st), .bal (if (swap.buy_a st) = 0 then (st.pre TokenB) else (st.pre TokenA)) (swap.to st), ReserveA, .has ReserveA, ReserveB, .has ReserveB]

/-- NON-VACUITY: a swap paying out tokens can happen. -/
theorem swap_live :
    ∃ st, swap st ∧ 0 < st.call.arg "out" := by
  refine ⟨{ call := liveCall, pre := livePre, post := swap.s4 liveStep0,
            writes := liveWrites liveStep0, ret := 2 }, ?_, by decide⟩
  exact { fn := rfl, notReentrant := by decide, xfer1 := by decide, xfer2 := by decide,
          auth_to := by decide, gate1 := by decide, gate2 := by decide, gate3 := by decide,
          post := rfl, writes := rfl, ret := rfl }

end Locked
