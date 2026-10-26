/-
The locked statements. A solution must prove theorems with exactly these names and types
(checked by `Check.lean`); it may add any lemmas of its own. Theorems marked PROBE are
expected to fail on the current model; they record a known limitation.
-/
import Spec.Defs

open Contract Spec

namespace Locked

/-- No unauthorized debit, across any sequence of calls: a user who never signs and has
    granted no allowances never sees their balance go down. -/
theorem no_unauthorized_debit : ∀ pool s tr t u, Run pool s tr t → Bystander pool u tr →
    NoAllowances s u → balanceOf s u ≤ balanceOf t u := sorry

/-- Only the admin creates tokens: a call that lowers no balance and raises one is signed by
    the admin. -/
theorem only_admin_mints : ∀ e ∈ entries, ∀ st, e st →
    (∀ a, balanceOf st.pre a ≤ balanceOf st.post a) → (∃ a, balanceOf st.pre a < balanceOf st.post a) →
    admin st.pre ∈ st.call.signers := sorry

/-- An expired allowance can't be spent. -/
theorem expired_allowance_unusable : ∀ st, transfer_from st →
    st.call.env "sequence" >
      st.pre (.fld (allowanceKey (st.call.argA "from") (st.call.argA "spender")) "live_until_ledger") →
    st.call.arg "amount" = 0 := sorry

/-- Only the admin can change the admin. -/
theorem admin_change_authorized : ∀ e ∈ entries, ∀ st, e st → st.call.fn ≠ "__constructor" →
    admin st.post ≠ admin st.pre → admin st.pre ∈ st.call.signers := sorry

/-- `approve` records the approved amount. (A probe until the emitter recovered path-dependent
    stores, slice dfdfe44: it was then unprovable, `approve` stored an open value.) -/
theorem approve_records_amount : ∀ st, approve st →
    st.post (.fld (allowanceKey (st.call.argA "from") (st.call.argA "spender")) "amount") =
      st.call.arg "amount" := sorry

/-- NON-VACUITY: a real transfer can happen. -/
theorem transfer_live :
    ∃ st, transfer st ∧ 0 < st.call.arg "amount" ∧ st.call.argA "from" ≠ st.call.argA "to_muxed" := sorry

end Locked
