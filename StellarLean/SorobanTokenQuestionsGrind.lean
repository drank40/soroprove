import StellarLean.SorobanToken

/-
  The questions of `SorobanTokenQuestions.lean`, answered with `grind`.

  `grind` does not unfold definitions on its own. The attributes below tell it
  which ones to unfold and which facts to use; they are `local`, so they apply
  to this file only and change nothing elsewhere.

  Theorems live in `SorobanToken.Grind` so they do not clash with the originals.
-/

namespace SorobanToken.Grind

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

/-! ## What `grind` may use -/

-- Equations: reading through `m[who]`, everyone's balance after a transfer,
-- and reading numbers back from storage.
attribute [local grind =] get_at get_at_addr balance_after ofVal_int ofVal_none

-- Definitions to unfold: the question bricks.
attribute [local grind] changesBy unchanged neverDecreases Question.given Question.except
  Question.all Question.or isCaller isRecipient caller recipient amount
  toSelf toSomeoneElse tracked

/-! ## Questions, answered -/

/-- Is the sender's balance reduced by the amount? Yes, when sending to someone else. -/
theorem sender_pays : contract ⊨ (changesBy Balance[caller] (- amount ·)).given toSomeoneElse :=
  contract_models fun _ _ => by grind

/-- Does the recipient get the amount? Yes, when sending to someone else. -/
theorem recipient_gets : contract ⊨ (changesBy Balance[recipient] amount).given toSomeoneElse :=
  contract_models fun _ _ => by grind

/-- Does sending to yourself change your balance? No. -/
theorem self_transfer_changes_nothing : contract ⊨ (unchanged Balance[caller]).given toSelf :=
  contract_models fun _ _ => by grind

/-- Does a transfer touch anyone else's balance? No. -/
theorem others_untouched :
    contract ⊨ ∀ₛ user, (unchanged Balance[user]).except (isCaller user ∨ₛ isRecipient user) :=
  contract_models fun _ _ => by grind

/-- Can a transfer lower anyone's balance except the sender's? No. -/
theorem only_sender_loses :
    contract ⊨ ∀ₛ user, (neverDecreases Balance[user]).except (isCaller user) :=
  contract_models fun _ _ => by grind [transfer]

/-- Can you send more than you have? No, the call fails. -/
theorem fails_if_insufficient (st : Step)
    (h : Balance.read st.pre st.call.caller < st.call.args.amt) : ¬ transfer st := by
  grind [transfer]

/-- Can you send a negative amount? No, the call fails. -/
theorem fails_if_negative (st : Step) (h : st.call.args.amt < 0) : ¬ transfer st := by
  grind [transfer]

/-! ## Total supply

  `grind` cannot match lemmas whose statement contains a lambda, so the
  per-account changes get names (`only`, `diff`). -/

/-- `d` at `w`, 0 elsewhere. -/
def only (w : Addr) (d : Int) : Addr → Int := fun a => if a = w then d else 0

/-- Pointwise `f - g + k`. -/
def diff (f g k : Addr → Int) : Addr → Int := fun a => f a - g a + k a

theorem sum_diff (hs : List Addr) (f g k : Addr → Int) :
    (hs.map (diff f g k)).sum = (hs.map f).sum - (hs.map g).sum + (hs.map k).sum := by
  induction hs <;> grind [diff]

theorem sum_only_absent (hs : List Addr) (w : Addr) (d : Int) (hw : w ∉ hs) :
    (hs.map (only w d)).sum = 0 := by
  induction hs <;> grind [only]

theorem sum_only (hs : List Addr) (w : Addr) (d : Int) (hnd : hs.Nodup) (hw : w ∈ hs) :
    (hs.map (only w d)).sum = d := by
  induction hs <;> grind [only, sum_only_absent]

/-- All balances after a transfer, as one function. -/
theorem read_post {st : Step} (h : transfer st) :
    Balance.read st.post = diff (Balance.read st.pre)
      (only st.call.caller st.call.args.amt) (only st.call.args.to st.call.args.amt) := by
  funext a
  grind [diff, only]

theorem get_total (m : Map Int) (c : Call) (s : Storage) :
    m.total.get c s = (c.holders.map (m.read s)).sum := rfl

theorem total_post {st : Step} (h : transfer st) :
    (st.call.holders.map (Balance.read st.post)).sum
      = (st.call.holders.map (Balance.read st.pre)).sum
        - (st.call.holders.map (only st.call.caller st.call.args.amt)).sum
        + (st.call.holders.map (only st.call.args.to st.call.args.amt)).sum := by
  grind only [read_post, sum_diff]

/-- Does a transfer change the total supply? No (counted over tracked holders). -/
theorem supply_unchanged : contract ⊨ (unchanged Balance.total).given tracked :=
  contract_models fun _ _ => by
    grind only [Question.given, unchanged, tracked, get_total, total_post, sum_only]

/-! ## An invariant: every balance fits in an i128 and is never negative -/

theorem balance_name : Balance.name = "Balance" := rfl

theorem read_spend (s : Storage) (w a : Addr) (x : Int) :
    Balance.read (spend s w x) a = if a = w then Balance.read s w - x else Balance.read s a := by
  grind [spend, Map.read_set, balance_name]

def validBalances : Invariant := fun s => ∀ a, 0 ≤ Balance.read s a ∧ Balance.read s a ≤ I128_MAX

/-- A freshly deployed token: no balance set yet. -/
def fresh : Invariant := fun s => ∀ a, s (.entry "Balance" a) = .none

/-- After any sequence of transfers from a fresh deploy, are all balances valid? Yes. -/
theorem balances_stay_valid {s : Storage} (h : contract.Reachable fresh s) : validBalances s :=
  contract.invariant validBalances
    (by grind [validBalances, fresh, Map.read, Balance, I128_MAX])
    (contract_models fun _ _ => by grind [validBalances, preserves, read_spend, transfer]) h

end SorobanToken.Grind
