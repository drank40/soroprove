import StellarLean.SorobanTokenFacts

/-
  The Soroban token's `transfer` questions, each proved with `answer`.
  No proof strategy is chosen here: the statement is the question.

  New vocabulary is tagged `@[answer]` so `answer` can use it.
-/

namespace SorobanToken.Answers

open Query
open Spec (Addr)

/-! ## Vocabulary for this contract -/

/-- The sender sends to themselves. -/
@[answer] def toSelf : Question := fun st => st.call.caller = st.call.args.to

/-- The sender sends to someone else. -/
@[answer] def toSomeoneElse : Question := fun st => st.call.caller ≠ st.call.args.to

/-- The (ghost) list of holders is a proper list of accounts that includes
    both sides of the transfer. Needed to talk about the total supply. -/
@[answer] def tracked : Question := fun st =>
  st.call.holders.Nodup ∧ st.call.caller ∈ st.call.holders ∧ st.call.args.to ∈ st.call.holders

/-- Every balance fits in an i128 and is never negative. -/
@[answer] def validBalances : Invariant := fun s =>
  ∀ a, 0 ≤ Balance.read s a ∧ Balance.read s a ≤ I128_MAX

/-- A freshly deployed token: no balance set yet. -/
@[answer] def fresh : Invariant := fun s => ∀ a, s (.entry "Balance" a) = .none

/-! ## Questions -/

/-- Is the sender's balance reduced by the amount, when sending to someone else? -/
theorem sender_pays :
    contract ⊨ (changesBy Balance[caller] (- amount ·)).given toSomeoneElse := by answer

/-- Does the recipient get the amount, when sending to someone else? -/
theorem recipient_gets :
    contract ⊨ (changesBy Balance[recipient] amount).given toSomeoneElse := by answer

/-- Does sending to yourself leave your balance as it was? -/
theorem self_transfer_changes_nothing :
    contract ⊨ (unchanged Balance[caller]).given toSelf := by answer

/-- Is everyone else's balance left alone? -/
theorem others_untouched :
    contract ⊨ ∀ₛ user, (unchanged Balance[user]).except (isCaller user ∨ₛ isRecipient user) := by
  answer

/-- Can only the sender lose balance? -/
theorem only_sender_loses :
    contract ⊨ ∀ₛ user, (neverDecreases Balance[user]).except (isCaller user) := by answer

/-- Does sending more than you have fail? -/
theorem fails_if_insufficient (st : Step)
    (h : Balance.read st.pre st.call.caller < st.call.args.amt) : ¬ transfer st := by answer

/-- Does sending a negative amount fail? -/
theorem fails_if_negative (st : Step) (h : st.call.args.amt < 0) : ¬ transfer st := by answer

/-- Is the total supply unchanged (over tracked holders)? -/
theorem supply_unchanged : contract ⊨ (unchanged Balance.total).given tracked := by answer

/-- After any sequence of transfers from a fresh deploy, are all balances valid? -/
theorem balances_stay_valid {s : Storage} (h : contract.Reachable fresh s) :
    validBalances s := by answer

end SorobanToken.Answers
