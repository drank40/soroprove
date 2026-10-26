-- Proofs over the generated `single_offer.lean` model (appended to it by check.sh).
-- `Offer` is a #[contracttype] struct: the model stores it field by field
-- (`Offer.seller`, `Offer.sell_token`, …).
open Contract

/-- `create` records the offer from its arguments. -/
theorem create_records_offer (st : Step) (h : create st) :
    st.post Offer.seller = create.seller st ∧
    st.post Offer.sell_token = create.sell_token st ∧
    st.post Offer.buy_token = create.buy_token st := by
  rw [h.post]; simp

/-- An offer can be created only once. -/
theorem create_once (a b : Step) (ha : create a) (hb : create b) (hseq : b.pre = a.post) : False := by
  have h := hb.gate3
  rw [hseq, ha.post] at h; simp at h

/-- Re-pricing needs the seller's signature and changes neither the seller nor the tokens. -/
theorem updt_price_keeps_parties (st : Step) (h : updt_price st) :
    st.pre Offer.seller ∈ st.call.signers ∧
    st.post Offer.seller = st.pre Offer.seller ∧
    st.post Offer.sell_token = st.pre Offer.sell_token ∧
    st.post Offer.buy_token = st.pre Offer.buy_token := by
  refine ⟨h.auth_Offer_seller, ?_⟩
  rw [h.post]; simp

/-- A trade pays the recorded seller the buyer's `buy_token_amount`, in the recorded buy token. -/
theorem trade_pays_seller (st : Step) (h : trade st)
    (hs : st.pre Offer.seller ≠ pool st) (hb : st.pre Offer.seller ≠ trade.buyer st)
    (ht : st.pre Offer.buy_token ≠ st.pre Offer.sell_token) :
    bal (st.pre Offer.buy_token) st.post (st.pre Offer.seller)
      = bal (st.pre Offer.buy_token) st.pre (st.pre Offer.seller) + trade.buy_token_amount st := by
  obtain ⟨u, h⟩ := h
  simp at hs hb ht
  rw [h.post]; simp [hs, hb, ht]

/-- Only the recorded seller can withdraw, and the funds go to them. -/
theorem withdraw_to_seller (st : Step) (h : withdraw st) (hne : st.pre Offer.seller ≠ pool st) :
    st.pre Offer.seller ∈ st.call.signers ∧
    bal (withdraw.token st) st.post (st.pre Offer.seller)
      = bal (withdraw.token st) st.pre (st.pre Offer.seller) + withdraw.amount st := by
  refine ⟨h.auth_Offer_seller, ?_⟩
  simp at hne
  rw [h.post]; simp [hne]
