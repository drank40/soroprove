/-
The locked statements. A solution must prove theorems with exactly these names and types
(checked by `Check.lean`); it may add any lemmas of its own. Theorems marked PROBE are
expected to fail on the current model; they record a known limitation.
-/
import Spec.Defs

open Contract Spec

namespace Locked

/-- Once created, the offer's seller and tokens never change, across any sequence of calls. -/
theorem offer_terms_fixed : ∀ pool s tr t, Run pool s tr t → created s →
    created t ∧ seller t = seller s ∧ sellToken t = sellToken s ∧ buyToken t = buyToken s := sorry

/-- A trade pays the seller exactly the buyer's payment. -/
theorem trade_pays_seller : ∀ st, trade st →
    seller st.pre ≠ st.call.self → seller st.pre ≠ st.call.argA "buyer" →
    sellToken st.pre ≠ buyToken st.pre →
    bal (buyToken st.pre) st.post (seller st.pre) =
      bal (buyToken st.pre) st.pre (seller st.pre) + st.call.arg "buy_token_amount" := sorry

/-- Only the seller can withdraw, and a withdrawal pays no one but the seller. -/
theorem withdraw_to_seller : ∀ st, withdraw st → seller st.pre ∈ st.call.signers ∧
    ∀ u tok, u ≠ st.call.self → u ≠ seller st.pre → bal tok st.post u = bal tok st.pre u := sorry

/-- PROBE (trade's `amount * sell_price / buy_price` is not recovered): the buyer receives at
    least `min_sell_token_amount` of the sell token. -/
theorem trade_respects_min : ∀ st, trade st →
    st.call.argA "buyer" ≠ st.call.self → sellToken st.pre ≠ buyToken st.pre →
    bal (sellToken st.pre) st.post (st.call.argA "buyer") ≥
      bal (sellToken st.pre) st.pre (st.call.argA "buyer") + st.call.arg "min_sell_token_amount" := sorry

/-- NON-VACUITY: a trade can happen. -/
theorem trade_live :
    ∃ st, trade st ∧ 0 < st.call.arg "buy_token_amount" := sorry

end Locked
