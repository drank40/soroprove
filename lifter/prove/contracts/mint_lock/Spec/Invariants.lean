/-
The locked statements. A solution must prove theorems with exactly these names and types
(checked by `Check.lean`); it may add any lemmas of its own. Theorems marked PROBE are
expected to fail on the current model; they record a known limitation.
-/
import Spec.Defs

open Contract Spec

namespace Locked

/-- A mint succeeds only for a non-negative amount signed by the minter, who is the admin or
    a configured minter. -/
theorem mint_authorized : ∀ st, mint st →
    st.call.argA "minter" ∈ st.call.signers ∧ 0 ≤ st.call.arg "amount" ∧
    (admin st.pre = st.call.argA "minter" ∨
      st.pre (.has (minterKey (st.call.argA "contract") (st.call.argA "minter"))) = 1) := sorry

/-- Epoch limit, across any sequence of calls: while the admin doesn't reconfigure minter `m`
    for contract `c`, what `m` mints in an epoch starting unused stays within its limit. -/
theorem epoch_limit : ∀ pool s tr t c m e, Run pool s tr t →
    (∀ st ∈ tr, st.call.fn = "set_minter" →
      ¬(st.call.argA "contract" = c ∧ st.call.argA "minter" = m)) →
    s (.has (minterKey c m)) = 1 →
    0 ≤ s (.fld (minterKey c m) "limit") →
    s (.has (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e)) ≠ 1 →
    mintedIn c m e tr ≤ s (.fld (minterKey c m) "limit") := sorry

/-- Only the admin can reconfigure minters. -/
theorem set_minter_authorized : ∀ e ∈ entries, ∀ st c m, e st →
    st.post (.fld (minterKey c m) "limit") ≠ st.pre (.fld (minterKey c m) "limit") →
    admin st.pre ∈ st.call.signers := sorry

/-- PROBE (`token.mint` is a call the model doesn't interpret, so it opens every ledger): a
    mint changes no balance except the recipient's. -/
theorem mint_only_credits_to : ∀ st, mint st → ∀ u tok, u ≠ st.call.argA "to" →
    bal tok st.post u = bal tok st.pre u := sorry

/-- NON-VACUITY: a non-admin minter can mint. -/
theorem mint_live :
    ∃ st, mint st ∧ 0 < st.call.arg "amount" ∧ admin st.pre ≠ st.call.argA "minter" := sorry

end Locked
