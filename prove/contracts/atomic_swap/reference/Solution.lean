/-
The locked statements. A solution must prove theorems with exactly these names and types
(checked by `Check.lean`); it may add any lemmas of its own. Theorems marked PROBE are
expected to fail on the current model; they record a known limitation.
-/
import Spec.Defs

open Contract Spec

namespace Locked

/-- The contract keeps nothing: a swap leaves its balance of every token unchanged (when
    neither party is the contract itself). -/
theorem swap_keeps_nothing : ∀ st, swap st →
    st.call.argA "a" ≠ st.call.self → st.call.argA "b" ≠ st.call.self →
    ∀ tok, bal tok st.post st.call.self = bal tok st.pre st.call.self := by
  intro st h ha hb tok
  rw [h.post]
  have ha' := Ne.symm ha; have hb' := Ne.symm hb
  simp only [swap.s6, swap.s5, swap.s4, swap.s3, swap.s2, swap.s1, bal_xfer, pool,
    swap.token_a, swap.token_b, swap.a, swap.b, swap.amt1, swap.amt2, swap.amt3, swap.amt4,
    swap.amt5, swap.amt6, swap.amount_a, swap.amount_b, swap.min_a_for_b, swap.min_b_for_a]
  simp only [ha', hb', and_false, and_true, if_false]
  by_cases h1 : tok = st.call.argA "token_a" <;> by_cases h2 : tok = st.call.argA "token_b"
  · simp only [if_pos h1, if_pos h2]; omega
  · simp only [if_pos h1, if_neg h2]; omega
  · simp only [if_neg h1, if_pos h2]; omega
  · simp only [if_neg h1, if_neg h2]; omega

/-- Each party gives exactly what the other is guaranteed (distinct parties and tokens). -/
theorem swap_exact : ∀ st, swap st →
    st.call.argA "a" ≠ st.call.self → st.call.argA "b" ≠ st.call.self →
    st.call.argA "a" ≠ st.call.argA "b" → st.call.argA "token_a" ≠ st.call.argA "token_b" →
    bal (st.call.argA "token_a") st.post (st.call.argA "a") =
      bal (st.call.argA "token_a") st.pre (st.call.argA "a") - st.call.arg "min_a_for_b" ∧
    bal (st.call.argA "token_a") st.post (st.call.argA "b") =
      bal (st.call.argA "token_a") st.pre (st.call.argA "b") + st.call.arg "min_a_for_b" ∧
    bal (st.call.argA "token_b") st.post (st.call.argA "b") =
      bal (st.call.argA "token_b") st.pre (st.call.argA "b") - st.call.arg "min_b_for_a" ∧
    bal (st.call.argA "token_b") st.post (st.call.argA "a") =
      bal (st.call.argA "token_b") st.pre (st.call.argA "a") + st.call.arg "min_b_for_a" := by
  intro st h ha hb hab ht
  rw [h.post]
  have hba := Ne.symm hab; have htb := Ne.symm ht
  simp only [swap.s6, swap.s5, swap.s4, swap.s3, swap.s2, swap.s1, bal_xfer, pool,
    swap.token_a, swap.token_b, swap.a, swap.b, swap.amt1, swap.amt2, swap.amt3, swap.amt4,
    swap.amt5, swap.amt6, swap.amount_a, swap.amount_b, swap.min_a_for_b, swap.min_b_for_a]
  simp [ha, hb, hab, hba, ht, htb]
  omega

/-- Anyone who didn't sign is unaffected. -/
theorem swap_bystander : ∀ st, swap st → ∀ u tok, u ∉ st.call.signers → u ≠ st.call.self →
    bal tok st.post u = bal tok st.pre u := by
  intro st h u tok hu hs
  have hua : u ≠ st.call.argA "a" := fun e => hu (e ▸ h.auth_a)
  have hub : u ≠ st.call.argA "b" := fun e => hu (e ▸ h.auth_b)
  rw [h.post]
  simp only [swap.s6, swap.s5, swap.s4, swap.s3, swap.s2, swap.s1, bal_xfer, pool,
    swap.token_a, swap.token_b, swap.a, swap.b]
  simp [hua, hub, hs]

/-- NON-VACUITY: a swap moving both tokens can happen. -/
theorem swap_live :
    ∃ st, swap st ∧ 0 < st.call.arg "min_a_for_b" ∧ 0 < st.call.arg "min_b_for_a" := by
  let c : Call := ⟨"swap", 5, 0, (fun _ => 1),
    (fun n => if n = "a" then 1 else if n = "b" then 2 else if n = "token_a" then 10 else 11),
    [1, 2], (fun _ => 0)⟩
  let pre : Storage := fun _ => 10
  let st0 : Step := ⟨c, pre, pre, [], 2⟩
  refine ⟨⟨c, pre, swap.s6 st0,
    [.bal (swap.token_a st0) (swap.a st0), .bal (swap.token_a st0) (pool st0),
      .bal (swap.token_a st0) (swap.b st0), .bal (swap.token_b st0) (swap.b st0),
      .bal (swap.token_b st0) (pool st0), .bal (swap.token_b st0) (swap.a st0)], 2⟩, ?_, ?_, ?_⟩
  · refine ⟨rfl, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, rfl, rfl, rfl⟩ <;>
      simp [c, pre, xferOk, xfer, bal]
  · simp [c]
  · simp [c]

end Locked
