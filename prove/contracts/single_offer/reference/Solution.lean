/-
The locked statements. A solution must prove theorems with exactly these names and types
(checked by `Check.lean`); it may add any lemmas of its own. Theorems marked PROBE are
expected to fail on the current model; they record a known limitation.
-/
import Spec.Defs

open Contract Spec

namespace Locked

/-- One step preserves the offer's presence and terms once created. -/
theorem step_keeps (st : Step) (he : ∃ e ∈ entries, e st) (hc : created st.pre) :
    created st.post ∧ seller st.post = seller st.pre ∧ sellToken st.post = sellToken st.pre ∧
      buyToken st.post = buyToken st.pre := by
  unfold created at *
  simp only [seller, sellToken, buyToken]
  simp only [entries, List.mem_cons, List.not_mem_nil, or_false] at he
  obtain ⟨e, he, hst⟩ := he
  rcases he with rfl | rfl | rfl | rfl | rfl
  · exact absurd (by simpa using hc) hst.gate3
  · obtain ⟨u, h⟩ := hst; rw [h.post]; exact ⟨hc, rfl, rfl, rfl⟩
  · obtain ⟨u, h⟩ := hst; rw [h.post]; simp [xfer]; exact hc
  · rw [hst.post]; simp
  · rw [hst.post]; simp [xfer]; exact hc

/-- Once created, the offer's seller and tokens never change, across any sequence of calls. -/
theorem offer_terms_fixed : ∀ pool s tr t, Run pool s tr t → created s →
    created t ∧ seller t = seller s ∧ sellToken t = sellToken s ∧ buyToken t = buyToken s := by
  intro pool s tr t hr hc
  induction hr with
  | nil => exact ⟨hc, rfl, rfl, rfl⟩
  | cons st _ _ _ he ih =>
    obtain ⟨h1, h2, h3, h4⟩ := ih
    obtain ⟨k1, k2, k3, k4⟩ := step_keeps st he h1
    exact ⟨k1, k2.trans h2, k3.trans h3, k4.trans h4⟩

/-- A trade pays the seller exactly the buyer's payment. -/
theorem trade_pays_seller : ∀ st, trade st →
    seller st.pre ≠ st.call.self → seller st.pre ≠ st.call.argA "buyer" →
    sellToken st.pre ≠ buyToken st.pre →
    bal (buyToken st.pre) st.post (seller st.pre) =
      bal (buyToken st.pre) st.pre (seller st.pre) + st.call.arg "buy_token_amount" := by
  intro st ⟨u, h⟩ h1 h2 h3
  simp only [seller, sellToken, buyToken] at *
  rw [h.post]
  simp [h1, h2]

/-- Only the seller can withdraw, and a withdrawal pays no one but the seller. -/
theorem withdraw_to_seller : ∀ st, withdraw st → seller st.pre ∈ st.call.signers ∧
    ∀ u tok, u ≠ st.call.self → u ≠ seller st.pre → bal tok st.post u = bal tok st.pre u := by
  intro st h
  refine ⟨h.auth_Offer_seller, ?_⟩
  intro u tok h1 h2
  simp only [seller] at h2
  rw [h.post]
  simp [h1, h2]

/-- PROBE (trade's `amount * sell_price / buy_price` is not recovered): the buyer receives at
    least `min_sell_token_amount` of the sell token. -/
theorem trade_respects_min : ∀ st, trade st →
    st.call.argA "buyer" ≠ st.call.self → sellToken st.pre ≠ buyToken st.pre →
    bal (sellToken st.pre) st.post (st.call.argA "buyer") ≥
      bal (sellToken st.pre) st.pre (st.call.argA "buyer") + st.call.arg "min_sell_token_amount" := sorry

/-- A concrete pre-state: sell token 1, buy token 2, seller 3, every balance 10. -/
def preS : Storage := fun k =>
  if k = Offer.sell_token then 1 else if k = Offer.buy_token then 2
  else if k = Offer.seller then 3 else 10

@[simp] theorem bal_preS (t a : Addr) : bal t preS a = 10 := by simp [bal, preS]

/-- The open values of `tradeStep`: the buyer gets `out`, the slippage gate sees `mn`. -/
def tradeU (mn out : Int) : Unk :=
  ⟨fun _ => out, fun _ => mn, fun _ => false, fun _ => .var "", fun _ _ => 0⟩

/-- The call of a trade by buyer 5 against the contract at 0, paying `amt`, demanding `mn`. -/
def tradeCall (amt mn : Int) : Call :=
  { fn := "trade", caller := 7, self := 0,
    arg := fun n => if n = "buy_token_amount" then amt
      else if n = "min_sell_token_amount" then mn else 0,
    argA := fun n => if n = "buyer" then 5 else 0,
    signers := [5], env := fun _ => 0 }

def tradeStep0 (amt mn : Int) : Step :=
  { call := tradeCall amt mn, pre := preS, post := preS, writes := [], ret := 2 }

def tradeStep (amt mn out : Int) : Step :=
  { tradeStep0 amt mn with
    post := trade.s3 (tradeStep0 amt mn) (tradeU mn out),
    writes := [.bal 2 5, .bal 2 0, .bal 1 0, .bal 1 5, .bal 2 3] }

theorem tradeStep_spec (amt mn out : Int) (h0 : 0 ≤ amt) (h1 : amt ≤ 10) (h2 : 0 ≤ out)
    (h3 : out ≤ 10) : trade.Spec (tradeStep amt mn out) (tradeU mn out) := by
  constructor <;> simp [tradeStep, tradeStep0, tradeCall, tradeU, xferOk, preS] <;> omega

/-- `trade_respects_min` is false for this model: the amount sent to the buyer (`u.i 4`) is
    left unconstrained by the reconstruction, and the slippage gate compares
    `min_sell_token_amount` with an unrelated open value (`u.g 4`). So a trade that pays the
    buyer nothing while demanding 1 is admitted. -/
theorem trade_respects_min_false : ¬ (∀ st, trade st →
    st.call.argA "buyer" ≠ st.call.self → sellToken st.pre ≠ buyToken st.pre →
    bal (sellToken st.pre) st.post (st.call.argA "buyer") ≥
      bal (sellToken st.pre) st.pre (st.call.argA "buyer") + st.call.arg "min_sell_token_amount") := by
  intro h
  have := h (tradeStep 0 1 0) ⟨_, tradeStep_spec 0 1 0 (by omega) (by omega) (by omega) (by omega)⟩
    (by simp [tradeStep, tradeStep0, tradeCall])
    (by simp [tradeStep, tradeStep0, sellToken, buyToken, preS])
  simp [tradeStep, tradeStep0, tradeCall, tradeU, sellToken, preS] at this

/-- NON-VACUITY: a trade can happen. -/
theorem trade_live :
    ∃ st, trade st ∧ 0 < st.call.arg "buy_token_amount" :=
  ⟨tradeStep 1 0 0, ⟨_, tradeStep_spec 1 0 0 (by omega) (by omega) (by omega) (by omega)⟩,
    by simp [tradeStep, tradeStep0, tradeCall]⟩

end Locked
