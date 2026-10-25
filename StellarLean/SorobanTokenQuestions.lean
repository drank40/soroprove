import StellarLean.SorobanToken

/-
  Questions about the Soroban token's `transfer` (modelled in
  `StellarLean/SorobanToken.lean`). Each theorem statement is a question;
  its proof is the answer.
-/

namespace SorobanToken

open Query
open Spec (Addr)

/-! ## Extra bricks for this contract -/

/-- The sender sends to themselves. -/
def toSelf : Question := fun st => st.call.caller = st.call.args.to

/-- The sender sends to someone else. -/
def toSomeoneElse : Question := fun st => st.call.caller ≠ st.call.args.to

/-- The (ghost) list of holders is a proper list of accounts that includes
    both sides of the transfer. Needed to talk about the total supply. -/
def tracked : Question := fun st =>
  st.call.holders.Nodup ∧ st.call.caller ∈ st.call.holders ∧ st.call.args.to ∈ st.call.holders

/-! ## Questions, answered -/

/-- Is the sender's balance reduced by the amount? Yes, when sending to someone else. -/
theorem sender_pays : contract ⊨ (changesBy Balance[caller] (- amount ·)).given toSomeoneElse :=
  contract_models fun st h hne => by
    have hne : st.call.caller ≠ st.call.args.to := hne
    simp only [changesBy, get_at, caller, amount, balance_after h]
    simp [hne]
    omega

/-- Does the recipient get the amount? Yes, when sending to someone else. -/
theorem recipient_gets : contract ⊨ (changesBy Balance[recipient] amount).given toSomeoneElse :=
  contract_models fun st h hne => by
    have hne : st.call.caller ≠ st.call.args.to := hne
    simp only [changesBy, get_at, recipient, amount, balance_after h]
    simp [Ne.symm hne]

/-- Does sending to yourself change your balance? No. -/
theorem self_transfer_changes_nothing : contract ⊨ (unchanged Balance[caller]).given toSelf :=
  contract_models fun st h hself => by
    have hself : st.call.caller = st.call.args.to := hself
    simp only [unchanged, get_at, caller, balance_after h]
    simp [← hself]

/-- Does a transfer touch anyone else's balance? No, and the frame rule
    answers it without looking at what transfer computes. -/
theorem others_untouched :
    contract ⊨ ∀ₛ user, (unchanged Balance[user]).except (isCaller user ∨ₛ isRecipient user) :=
  contract_models fun st h user => by
    by_cases hu : user = st.call.caller ∨ user = st.call.args.to
    · exact Or.inl hu
    · refine Or.inr ((Balance[user] : Term Int).frame (contract.framed _ (by simp [contract]) st h)
        fun k hr hw => ?_)
      rw [h.2.2.2.2.1] at hw
      have hr : k = .entry "Balance" user := hr
      subst hr
      simp at hw
      exact hu hw

/-- Can a transfer lower anyone's balance except the sender's? No. -/
theorem only_sender_loses :
    contract ⊨ ∀ₛ user, (neverDecreases Balance[user]).except (isCaller user) :=
  contract_models fun st h user => by
    by_cases hu : user = st.call.caller
    · exact Or.inl hu
    · refine Or.inr ?_
      have := h.1
      simp only [neverDecreases, get_at_addr, balance_after h]
      split <;> simp_all <;> omega

/-- Can you send more than you have? No, the call fails. -/
theorem fails_if_insufficient (st : Step)
    (h : Balance.read st.pre st.call.caller < st.call.args.amt) : ¬ transfer st :=
  fun ht => by have := ht.2.1; omega

/-- Can you send a negative amount? No, the call fails. -/
theorem fails_if_negative (st : Step) (h : st.call.args.amt < 0) : ¬ transfer st :=
  fun ht => by have := ht.1; omega

/-! ## Total supply -/

theorem sum_split (hs : List Addr) (f g k : Addr → Int) :
    (hs.map fun a => f a - g a + k a).sum = (hs.map f).sum - (hs.map g).sum + (hs.map k).sum := by
  induction hs with
  | nil => simp
  | cons x t ih => simp only [List.map_cons, List.sum_cons, ih]; omega

theorem sum_single (hs : List Addr) (hnd : hs.Nodup) (w : Addr) (hw : w ∈ hs) (d : Int) :
    (hs.map fun a => if a = w then d else 0).sum = d := by
  have := Spec.sum_update hs hnd (fun _ => 0) w d
  simp only [Int.zero_add, hw, ↓reduceIte] at this
  have hz : (hs.map fun _ => (0 : Int)).sum = 0 := by
    clear this hnd hw
    induction hs <;> simp_all
  omega

/-- Does a transfer change the total supply? No (counted over tracked holders). -/
theorem supply_unchanged : contract ⊨ (unchanged Balance.total).given tracked :=
  contract_models fun st h ⟨hnd, hc, ht⟩ => by
    simp only [unchanged, Map.total]
    rw [List.map_congr_left fun a _ => balance_after h a, sum_split,
      sum_single _ hnd _ hc, sum_single _ hnd _ ht]
    omega

/-! ## An invariant: every balance fits in an i128 and is never negative -/

def validBalances : Invariant := fun s => ∀ a, 0 ≤ Balance.read s a ∧ Balance.read s a ≤ I128_MAX

/-- A freshly deployed token: no balance set yet. -/
def fresh : Invariant := fun s => ∀ a, s (.entry "Balance" a) = .none

/-- After any sequence of transfers from a fresh deploy, are all balances valid? Yes. -/
theorem balances_stay_valid {s : Storage} (h : contract.Reachable fresh s) : validBalances s := by
  refine contract.invariant validBalances (fun s h0 a => ?_) (contract_models fun st h hv a => ?_) h
  · have : Balance.read s a = 0 := by simp [Map.read, Balance, h0 a]
    simp [this, I128_MAX]
  · have ⟨hpos, hfund, hfit, _⟩ := h
    have hs1 : Balance.read (spend st.pre st.call.caller st.call.args.amt) st.call.args.to
        = Balance.read st.pre st.call.args.to
          - (if st.call.args.to = st.call.caller then st.call.args.amt else 0) := by
      simp only [spend]
      rw [show "Balance" = Balance.name from rfl, Map.read_set]
      split <;> simp_all
    have hva := hv a
    have hvt := hv st.call.args.to
    have hvc := hv st.call.caller
    rw [balance_after h]
    rw [hs1] at hfit
    by_cases ha : a = st.call.args.to <;> by_cases hc : a = st.call.caller <;>
      by_cases htc : st.call.args.to = st.call.caller <;> simp_all <;> omega

end SorobanToken
