-- Proofs over the generated `single_offer.lean` model (appended to it by check.sh).
-- `Offer` is a #[contracttype] struct: the model stores it field by field.
open Contract

/-- `create` records the offer from its arguments. -/
theorem create_records_offer (st : Step) (h : create st) :
    st.post (.fld (.var "Offer") "seller") = st.call.argA "seller" ∧
    st.post (.fld (.var "Offer") "sell_token") = st.call.argA "sell_token" ∧
    st.post (.fld (.var "Offer") "buy_token") = st.call.argA "buy_token" := by
  obtain ⟨_, _, _, _, _, _, hpost, _⟩ := h
  rw [hpost]; simp [Storage.set]

/-- An offer can be created only once. -/
theorem create_once (a b : Step) (ha : create a) (hb : create b) (hseq : b.pre = a.post) : False := by
  obtain ⟨_, _, _, _, _, _, hpost, _⟩ := ha
  obtain ⟨_, _, _, _, _, hnot, _⟩ := hb
  rw [hseq, hpost] at hnot; simp [Storage.set] at hnot

/-- Re-pricing needs the seller's signature and changes neither the seller nor the tokens. -/
theorem updt_price_keeps_parties (st : Step) (h : updt_price st) :
    st.pre (.fld (.var "Offer") "seller") ∈ st.call.signers ∧
    st.post (.fld (.var "Offer") "seller") = st.pre (.fld (.var "Offer") "seller") ∧
    st.post (.fld (.var "Offer") "sell_token") = st.pre (.fld (.var "Offer") "sell_token") ∧
    st.post (.fld (.var "Offer") "buy_token") = st.pre (.fld (.var "Offer") "buy_token") := by
  obtain ⟨_, _, hsig, _, _, hpost, _⟩ := h
  refine ⟨hsig, ?_⟩
  rw [hpost]; simp [Storage.set]

/-- Only the recorded seller can withdraw, and the funds go to them. -/
theorem withdraw_to_seller (st : Step) (h : withdraw st)
    (hne : st.pre (.fld (.var "Offer") "seller") ≠ st.call.self) :
    st.pre (.fld (.var "Offer") "seller") ∈ st.call.signers ∧
    bal (st.call.argA "token") st.post (st.pre (.fld (.var "Offer") "seller"))
      = bal (st.call.argA "token") st.pre (st.pre (.fld (.var "Offer") "seller")) + st.call.arg "amount" := by
  obtain ⟨_, _, hsig, hpost, _⟩ := h
  refine ⟨hsig, ?_⟩
  rw [hpost]; simp [xfer, bal, Storage.set, hne]
