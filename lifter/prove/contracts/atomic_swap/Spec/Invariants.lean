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
    ∀ tok, bal tok st.post st.call.self = bal tok st.pre st.call.self := sorry

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
      bal (st.call.argA "token_b") st.pre (st.call.argA "a") + st.call.arg "min_b_for_a" := sorry

/-- Anyone who didn't sign is unaffected. -/
theorem swap_bystander : ∀ st, swap st → ∀ u tok, u ∉ st.call.signers → u ≠ st.call.self →
    bal tok st.post u = bal tok st.pre u := sorry

/-- NON-VACUITY: a swap moving both tokens can happen. -/
theorem swap_live :
    ∃ st, swap st ∧ 0 < st.call.arg "min_a_for_b" ∧ 0 < st.call.arg "min_b_for_a" := sorry

end Locked
