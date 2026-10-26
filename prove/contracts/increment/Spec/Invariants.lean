/-
The locked statements. A solution must prove theorems with exactly these names and types
(checked by `Check.lean`); it may add any lemmas of its own. Theorems marked PROBE are
expected to fail on the current model; they record a known limitation.
-/
import Spec.Defs

open Contract Spec

namespace Locked

/-- Across any sequence of calls the counter grows by exactly one per call. -/
theorem counts_calls : ∀ pool s tr t, Run pool s tr t → counter t = counter s + tr.length := sorry

/-- `increment` returns the new count. -/
theorem returns_new_count : ∀ st, increment st → st.ret = counter st.post := sorry

/-- PROBE (the u32 overflow trap is not modeled): from a fresh contract the counter stays
    within u32. -/
theorem counter_fits_u32 : ∀ pool s tr t, Run pool s tr t → counter s = 0 →
    counter t ≤ 4294967295 := sorry

/-- NON-VACUITY: increment can run. -/
theorem increment_live :
    ∃ st, increment st := sorry

end Locked
