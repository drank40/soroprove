/-
The locked statements. A solution must prove theorems with exactly these names and types
(checked by `Check.lean`); it may add any lemmas of its own. Theorems marked PROBE are
expected to fail on the current model; they record a known limitation.
-/
import Spec.Defs

open Contract Spec

namespace Locked

/-- Pays out once: from a fresh contract, any sequence of calls has at most one deposit and
    at most as many claims as deposits. -/
theorem claim_at_most_once : ∀ pool s tr t, Run pool s tr t → ¬ initialized s → ¬ funded s →
    calls "deposit" tr ≤ 1 ∧ calls "claim" tr ≤ calls "deposit" tr := sorry

/-- `claim` needs the claimant's signature and pays them exactly the recorded amount in the
    recorded token. -/
theorem claim_pays_recorded : ∀ st, claim st → st.call.argA "claimant" ≠ st.call.self →
    st.call.argA "claimant" ∈ st.call.signers ∧
    bal (st.pre (.fld (.var "Balance") "token")) st.post (st.call.argA "claimant") =
      bal (st.pre (.fld (.var "Balance") "token")) st.pre (st.call.argA "claimant") +
        st.pre (.fld (.var "Balance") "amount") := sorry

/-- NON-VACUITY: a claim paying a positive amount can happen. -/
theorem claim_live :
    ∃ st, claim st ∧ 0 < st.pre (.fld (.var "Balance") "amount") := sorry

end Locked
