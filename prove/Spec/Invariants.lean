/-
The locked statements. A solution must prove theorems with exactly these names and types
(checked by `Check.lean`); it may add any lemmas of its own.
-/
import Spec.Defs

open Contract Spec

namespace Locked

/-- A nonce is never executed twice, across any sequence of transactions. -/
theorem no_replay : ∀ s, Reach s → s.used.Nodup := sorry

/-- The vault never pays out more than was deposited. -/
theorem solvent : ∀ s, Reach s → Solvent s := sorry

/-- Only the owner can change the signing key. -/
theorem key_owner_only : ∀ s a, Reach s → guard s a → (step s a).pubKey ≠ s.pubKey →
    ∃ k, a = .setPubKey s.owner k := sorry

/-- Non-vacuity: a signed withdrawal can actually happen. -/
theorem withdraw_live : ∃ s, Reach s ∧ 0 < s.withdrawn := sorry

end Locked
