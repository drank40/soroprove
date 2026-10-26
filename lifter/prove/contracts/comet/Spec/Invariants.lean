/-
The locked statements. A solution must prove theorems with exactly these names and types
(checked by `Check.lean`); it may add any lemmas of its own.

Comet weighted pool, mainnet CAS3FL6TLZKDGGSISDBWGGPXT3NRR4DYTZD7YOD3HMYO6LTJUVGRVEAM
(wasm 8abc2891…). The pool quotes every price from its books, `AllRecordData[t].balance`.
-/
import Spec.Defs

open Contract Spec

namespace Locked

/-- The books follow the money: a swap moves the pool's book of the token it receives by
    exactly what the pool's real balance of that token moved. (The user is not the pool
    itself: a contract can't authorize a call into itself on Soroban.) -/
theorem swap_books_track_input : ∀ st, swap_exact_amount_in st →
    swap_exact_amount_in.user st ≠ pool st →
    st.post (AllRecordData.balance (swap_exact_amount_in.token_in st))
      - st.pre (AllRecordData.balance (swap_exact_amount_in.token_in st))
    = bal (swap_exact_amount_in.token_in st) st.post (pool st)
      - bal (swap_exact_amount_in.token_in st) st.pre (pool st) := sorry

/-- NON-VACUITY: a swap can happen. -/
theorem swap_live : ∃ st, swap_exact_amount_in st := sorry

end Locked
