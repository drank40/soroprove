/-
The locked statements. A solution must prove theorems with exactly these names and types
(checked by `Check.lean`); it may add any lemmas of its own.
-/
import Spec.Defs

open Contract Spec

namespace Locked

/-- No theft, across any sequence of calls: a user who never signs keeps exactly their
    balance of every token and their pool shares. -/
theorem bystander_safe : ∀ pool s tr t u, Run pool s tr t → Bystander pool u tr →
    (∀ tok, bal tok t u = bal tok s u) ∧ t (.entry "Shares" u) = s (.entry "Shares" u) := sorry

/-- A call changes a user's token balance only if that user signed it. -/
theorem balance_change_authorized : ∀ e ∈ entries, ∀ st tok u, e st → u ≠ st.call.self →
    bal tok st.post u ≠ bal tok st.pre u → u ∈ st.call.signers := sorry

/-- No draining by swapping: from non-negative reserves, a swap never lowers the product
    of the stored reserves. -/
theorem swap_keeps_product : ∀ st, swap st → 0 ≤ reserveA st.pre → 0 ≤ reserveB st.pre →
    reserveA st.pre * reserveB st.pre ≤ reserveA st.post * reserveB st.post := sorry

/-- NON-VACUITY: a swap paying out tokens can happen. -/
theorem swap_live :
    ∃ st, swap st ∧ 0 < st.call.arg "out" := sorry

end Locked
