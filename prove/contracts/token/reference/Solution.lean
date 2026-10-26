/-
The locked statements. A solution must prove theorems with exactly these names and types
(checked by `Check.lean`); it may add any lemmas of its own. Theorems marked PROBE are
expected to fail on the current model; they record a known limitation.
-/
import Spec.Defs

open Contract Spec

namespace Aux

/-- reading a balance after the model's two-part balance write (value, then presence). -/
theorem getOr0_setBal (s : Storage) (x a : Addr) (v : Int) :
    getOr0 ((s.set (.entry "Balance" x) v).set (.has (.entry "Balance" x)) 1) (.entry "Balance" a) =
      if a = x then v else getOr0 s (.entry "Balance" a) := by
  by_cases h : a = x <;> simp [getOr0, h]

/-! Each balance-changing entry point, as a closed-form effect on `balanceOf`. -/

theorem bal_transfer {st : Step} (h : transfer st) (a : Addr) :
    balanceOf st.post a = balanceOf st.pre a + (if a = st.call.argA "to_muxed" then st.call.arg "amount" else 0)
      - (if a = st.call.argA "from" then st.call.arg "amount" else 0) := by
  simp only [balanceOf, h.post, transfer.s2, transfer.s1, transfer.new_Balance_2, transfer.new_Balance,
    Balance, transfer.«from», transfer.to_muxed, transfer.amount, getOr0_setBal]
  generalize st.call.argA "to_muxed" = t; generalize st.call.argA "from" = f
  by_cases h1 : a = t <;> by_cases h2 : a = f <;> by_cases h3 : t = f <;> subst_vars <;> simp_all <;> omega

theorem tf_s1 {st : Step} (a : Addr) :
    getOr0 (transfer_from.s1 st) (.entry "Balance" a) = getOr0 st.pre (.entry "Balance" a) := by
  simp only [transfer_from.s1]; split <;> simp [getOr0]

theorem bal_transfer_from {st : Step} (h : transfer_from st) (a : Addr) :
    balanceOf st.post a = balanceOf st.pre a + (if a = st.call.argA "to" then st.call.arg "amount" else 0)
      - (if a = st.call.argA "from" then st.call.arg "amount" else 0) := by
  simp only [balanceOf, h.post, transfer_from.s3, transfer_from.s2, transfer_from.new_Balance_2,
    transfer_from.new_Balance, Balance, transfer_from.«from», transfer_from.to, transfer_from.amount,
    getOr0_setBal, tf_s1]
  generalize st.call.argA "to" = t; generalize st.call.argA "from" = f
  by_cases h1 : a = t <;> by_cases h2 : a = f <;> by_cases h3 : t = f <;> subst_vars <;> simp_all <;> omega

theorem bf_s1 {st : Step} (a : Addr) :
    getOr0 (burn_from.s1 st) (.entry "Balance" a) = getOr0 st.pre (.entry "Balance" a) := by
  simp only [burn_from.s1]; split <;> simp [getOr0]

theorem bal_burn_from {st : Step} (h : burn_from st) (a : Addr) :
    balanceOf st.post a = balanceOf st.pre a
      - (if a = st.call.argA "from" then st.call.arg "amount" else 0) := by
  simp only [balanceOf, h.post, burn_from.s2, burn_from.new_Balance, Balance, burn_from.«from»,
    burn_from.amount, getOr0_setBal, bf_s1]
  by_cases h2 : a = st.call.argA "from"
  · subst h2; simp
  · simp [h2]

theorem bal_burn {st : Step} (h : burn st) (a : Addr) :
    balanceOf st.post a = balanceOf st.pre a
      - (if a = st.call.argA "from" then st.call.arg "amount" else 0) := by
  simp only [balanceOf, h.post, burn.s1, burn.new_Balance, Balance, burn.«from», burn.amount, getOr0_setBal]
  by_cases h2 : a = st.call.argA "from"
  · subst h2; simp
  · simp [h2]

theorem bal_mint {st : Step} (h : mint st) (a : Addr) :
    balanceOf st.post a = balanceOf st.pre a
      + (if a = st.call.argA "to" then st.call.arg "amount" else 0) := by
  simp only [balanceOf, h.post, mint.s1, mint.new_Balance, Balance, mint.to, mint.amount, getOr0_setBal]
  by_cases h2 : a = st.call.argA "to"
  · subst h2; simp
  · simp [h2]

theorem bal_approve {st : Step} (h : approve st) (a : Addr) :
    balanceOf st.post a = balanceOf st.pre a := by
  obtain ⟨u, h⟩ := h; simp [balanceOf, h.post, getOr0]

/-- One call keeps a non-signing user with no allowances allowance-free, and doesn't lower
    their balance. (`transfer_from` / `burn_from` out of such a user are forced to amount 0
    by the allowance gate, and then write no allowance.) -/
theorem step_bystander {st : Step} {u : Addr} (he : ∃ e ∈ entries, e st)
    (hu : u ∉ st.call.signers) (hna : NoAllowances st.pre u) :
    NoAllowances st.post u ∧ balanceOf st.pre u ≤ balanceOf st.post u := by
  obtain ⟨e, he, h⟩ := he
  simp only [entries, List.mem_cons, List.not_mem_nil, or_false] at he
  have ne_of {a : Addr} (ha : a ∈ st.call.signers) : u ≠ a := fun h => hu (h ▸ ha)
  rcases he with rfl|rfl|rfl|rfl|rfl|rfl|rfl|rfl|rfl|rfl|rfl|rfl
  -- read-only entry points and `set_admin`
  all_goals first
    | (rw [h.post]; exact ⟨hna, Int.le_refl _⟩)
    | skip
  · -- approve
    have hb := bal_approve h u
    obtain ⟨_, h⟩ := h
    have hf := ne_of h.auth_from; simp only [approve.«from»] at hf
    refine ⟨fun sp => ?_, by omega⟩
    have := hna sp; simp only [allowanceKey] at this
    simp [h.post, allowanceKey, this, hf]
  · -- burn
    have hf := ne_of h.auth_from; simp only [burn.«from»] at hf
    have hb := bal_burn h u
    refine ⟨fun sp => ?_, ?_⟩
    · have := hna sp; simp only [allowanceKey] at this; simp [h.post, allowanceKey, this]
    · simp only [hf, if_false] at hb; omega
  · -- burn_from
    have g1 := h.gate1; have g2 := h.gate2
    have hb := bal_burn_from h u
    have hna' := hna (st.call.argA "spender")
    simp only [allowanceKey] at hna'
    have key : st.call.arg "amount" = 0 ∨ u ≠ st.call.argA "from" := by
      by_cases hf : u = st.call.argA "from"
      · left; subst hf
        simp only [burn_from.pre_has_Allowance, burn_from.amount, burn_from.«from», burn_from.spender,
          Allowance, hna', ne_eq, not_false_eq_true, if_true] at g1 g2
        omega
      · exact Or.inr hf
    refine ⟨fun sp => ?_, ?_⟩
    · have := hna sp; simp only [allowanceKey] at this
      rcases key with k | k <;> simp [h.post, allowanceKey, this, k] <;> split <;> simp [this, k]
    · rcases key with k | k <;> simp only [k, if_false] at hb <;> (try split at hb) <;> omega
  · -- mint
    have g1 := h.gate1; simp only [mint.amount] at g1
    have hb := bal_mint h u
    refine ⟨fun sp => ?_, ?_⟩
    · have := hna sp; simp only [allowanceKey] at this; simp [h.post, allowanceKey, this]
    · split at hb <;> omega
  · -- transfer
    have g1 := h.gate1; simp only [transfer.amount] at g1
    have hf := ne_of h.auth_from; simp only [transfer.«from»] at hf
    have hb := bal_transfer h u
    refine ⟨fun sp => ?_, ?_⟩
    · have := hna sp; simp only [allowanceKey] at this; simp [h.post, allowanceKey, this]
    · simp only [hf, if_false] at hb; split at hb <;> omega
  · -- transfer_from
    have g1 := h.gate1; have g2 := h.gate2
    have hb := bal_transfer_from h u
    have hna' := hna (st.call.argA "spender")
    simp only [allowanceKey] at hna'
    have key : st.call.arg "amount" = 0 ∨ u ≠ st.call.argA "from" := by
      by_cases hf : u = st.call.argA "from"
      · left; subst hf
        simp only [transfer_from.pre_has_Allowance, transfer_from.amount, transfer_from.«from»,
          transfer_from.spender, Allowance, hna', ne_eq, not_false_eq_true, if_true] at g1 g2
        omega
      · exact Or.inr hf
    simp only [transfer_from.amount] at g1
    refine ⟨fun sp => ?_, ?_⟩
    · have := hna sp; simp only [allowanceKey] at this
      rcases key with k | k <;> simp [h.post, allowanceKey, this, k] <;> split <;> simp [this, k]
    · rcases key with k | k <;> simp only [k, if_false] at hb <;> (try split at hb) <;> (try split at hb) <;> omega

/-- The inductive invariant behind `no_unauthorized_debit`. -/
theorem run_bystander {pool s tr t u} (hr : Run pool s tr t) (hb : Bystander pool u tr)
    (hna : NoAllowances s u) : NoAllowances t u ∧ balanceOf s u ≤ balanceOf t u := by
  induction hr with
  | nil => exact ⟨hna, Int.le_refl _⟩
  | cons st _ _ _ he ih =>
    obtain ⟨hp, hs⟩ := hb
    obtain ⟨h1, h2⟩ := ih ⟨hp, fun x hx => hs x (List.mem_cons_of_mem _ hx)⟩
    obtain ⟨h3, h4⟩ := step_bystander he (hs st List.mem_cons_self) h1
    exact ⟨h3, Int.le_trans h2 h4⟩

end Aux

namespace Locked

/-- No unauthorized debit, across any sequence of calls: a user who never signs and has
    granted no allowances never sees their balance go down. -/
theorem no_unauthorized_debit : ∀ pool s tr t u, Run pool s tr t → Bystander pool u tr →
    NoAllowances s u → balanceOf s u ≤ balanceOf t u :=
  fun _ _ _ _ _ hr hb hna => (Aux.run_bystander hr hb hna).2

/-- Only the admin creates tokens: a call that lowers no balance and raises one is signed by
    the admin. -/
theorem only_admin_mints : ∀ e ∈ entries, ∀ st, e st →
    (∀ a, balanceOf st.pre a ≤ balanceOf st.post a) → (∃ a, balanceOf st.pre a < balanceOf st.post a) →
    admin st.pre ∈ st.call.signers := by
  intro e he st h hle ⟨a, ha⟩
  simp only [entries, List.mem_cons, List.not_mem_nil, or_false] at he
  rcases he with rfl|rfl|rfl|rfl|rfl|rfl|rfl|rfl|rfl|rfl|rfl|rfl
  all_goals first
    | exact h.auth_Admin
    | (exfalso; rw [h.post] at ha; exact Int.lt_irrefl _ ha)
    | skip
  · rw [Aux.bal_approve h] at ha; exact absurd ha (Int.lt_irrefl _)
  · have g1 := h.gate1; simp only [burn.amount] at g1
    rw [Aux.bal_burn h] at ha; split at ha <;> omega
  · have g1 := h.gate1; simp only [burn_from.amount] at g1
    rw [Aux.bal_burn_from h] at ha; split at ha <;> omega
  · -- transfer: a positive amount lowers `from` unless `from = to`, where nothing changes
    have g1 := h.gate1; simp only [transfer.amount] at g1
    have hf := hle (st.call.argA "from")
    rw [Aux.bal_transfer h] at ha; rw [Aux.bal_transfer h] at hf
    revert ha hf g1
    generalize st.call.argA "to_muxed" = t; generalize st.call.argA "from" = f
    generalize st.call.arg "amount" = m
    intro g1 ha hf
    by_cases h1 : a = t <;> by_cases h2 : a = f <;> by_cases h3 : f = t <;> subst_vars <;> simp_all <;> omega
  · have g1 := h.gate1; simp only [transfer_from.amount] at g1
    have hf := hle (st.call.argA "from")
    rw [Aux.bal_transfer_from h] at ha; rw [Aux.bal_transfer_from h] at hf
    revert ha hf g1
    generalize st.call.argA "to" = t; generalize st.call.argA "from" = f
    generalize st.call.arg "amount" = m
    intro g1 ha hf
    by_cases h1 : a = t <;> by_cases h2 : a = f <;> by_cases h3 : f = t <;> subst_vars <;> simp_all <;> omega

/-- An expired allowance can't be spent. -/
theorem expired_allowance_unusable : ∀ st, transfer_from st →
    st.call.env "sequence" >
      st.pre (.fld (allowanceKey (st.call.argA "from") (st.call.argA "spender")) "live_until_ledger") →
    st.call.arg "amount" = 0 := by
  intro st h hs
  have g1 := h.gate1; have g2 := h.gate2
  simp only [allowanceKey] at hs
  simp only [transfer_from.pre_has_Allowance, transfer_from.pre_Allowance_live_until_ledger,
    transfer_from.pre_Allowance_amount, transfer_from.amount, transfer_from.«from», transfer_from.spender,
    Allowance, Allowance.live_until_ledger, Allowance.amount] at g1 g2
  split at g2 <;> (try split at g2) <;> omega

/-- Only the admin can change the admin. -/
theorem admin_change_authorized : ∀ e ∈ entries, ∀ st, e st → st.call.fn ≠ "__constructor" →
    admin st.post ≠ admin st.pre → admin st.pre ∈ st.call.signers := by
  intro e he st h _ hne
  simp only [entries, List.mem_cons, List.not_mem_nil, or_false] at he
  rcases he with rfl|rfl|rfl|rfl|rfl|rfl|rfl|rfl|rfl|rfl|rfl|rfl
  all_goals first
    | exact h.auth_Admin
    | (exfalso; apply hne; first | (obtain ⟨u, h⟩ := h; simp [h.post, admin]) | (simp [h.post, admin]; try (split <;> simp)))

/-- PROBE (approve's stored amount is not recovered): `approve` records the approved amount.
    (Provable on the current model: `approve.s1` writes `Allowance.amount` := `amount`.) -/
theorem approve_records_amount : ∀ st, approve st →
    st.post (.fld (allowanceKey (st.call.argA "from") (st.call.argA "spender")) "amount") =
      st.call.arg "amount" := by
  rintro st ⟨u, h⟩
  rw [h.post]; simp [allowanceKey]

/-- NON-VACUITY: a real transfer can happen. -/
theorem transfer_live :
    ∃ st, transfer st ∧ 0 < st.call.arg "amount" ∧ st.call.argA "from" ≠ st.call.argA "to_muxed" := by
  let c : Call := ⟨"transfer", 0, 1, fun _ => 1, fun n => if n = "from" then 2 else 3, [2], fun _ => 0⟩
  let p : Storage := fun _ => 1
  let st0 : Step := ⟨c, p, p, [], 0⟩
  refine ⟨⟨c, p, transfer.s2 st0, [Balance 2, .has (Balance 2), Balance 3, .has (Balance 3)], 2⟩,
    ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩, ?_, ?_⟩ <;> simp [c, p, st0, getOr0]

end Locked
