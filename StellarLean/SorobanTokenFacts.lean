import StellarLean.SorobanToken
import StellarLean.Answer

/-
  Facts about the Soroban token's `transfer` for the `answer` tactic.

  Nothing here is specific to a question: it is what a WASM → Lean converter
  would emit for every entry point, mechanically, from the code:
  * which entry points the contract has;
  * each precondition (each `panic!` that did not fire);
  * the effect on storage: every balance after the call, and the change of
    a sum of balances.
-/

namespace SorobanToken

open Query
open Spec (Addr)

/-! ## Entry points -/

/-- A step of the contract is a step of one of its entry points
    (with more entry points: `transfer st ∨ mint st ∨ …`). -/
@[answer →] theorem step_of_contract {st : Step} (h : contract.Steps st) : transfer st := by
  obtain ⟨e, he, hst⟩ := h
  simp only [contract, List.mem_cons, List.not_mem_nil, or_false] at he
  subst he
  exact hst

/-! ## Storage layout -/

@[answer =] theorem balance_name : Balance.name = "Balance" := rfl

/-! ## Preconditions: what is true whenever `transfer` succeeds -/

theorem read_spend (s : Storage) (w a : Addr) (x : Int) :
    Balance.read (spend s w x) a = if a = w then Balance.read s w - x else Balance.read s a := by
  grind [spend, Map.read_set, balance_name, ofVal_int]

/-- `check_nonnegative_amount` -/
@[answer →] theorem transfer_nonneg {st : Step} (h : transfer st) : 0 ≤ st.call.args.amt := h.1

/-- `spend_balance`: "insufficient balance" -/
@[answer →] theorem transfer_funded {st : Step} (h : transfer st) :
    st.call.args.amt ≤ Balance.read st.pre st.call.caller := h.2.1

/-- `receive_balance`: `balance + amount` fits in an i128 -/
@[answer →] theorem transfer_fits {st : Step} (h : transfer st) :
    Balance.read st.pre st.call.args.to
      - (if st.call.args.to = st.call.caller then st.call.args.amt else 0)
      + st.call.args.amt ≤ I128_MAX := by
  have := h.2.2.1
  rw [read_spend] at this
  grind

/-! ## Effects on storage -/

/-- Frame: only the two balances are written. -/
@[answer =] theorem transfer_frame {st : Step} (h : transfer st) (k : Key)
    (h1 : k ≠ .entry "Balance" st.call.caller) (h2 : k ≠ .entry "Balance" st.call.args.to) :
    st.post k = st.pre k :=
  contract.framed _ (by simp [contract]) st h k (by rw [h.2.2.2.2.1]; simp [h1, h2])

/-- Return value: `transfer` returns nothing. -/
@[answer →] theorem transfer_ret {st : Step} (h : transfer st) : st.ret = .none := h.2.2.2.2.2

attribute [answer =] balance_after

/-- The change of any sum of balances. -/
@[answer =] theorem sum_after {st : Step} (h : transfer st) (hs : List Addr) :
    (hs.map (Balance.read st.post)).sum
      = (hs.map (Balance.read st.pre)).sum
        - (hs.map (only st.call.caller st.call.args.amt)).sum
        + (hs.map (only st.call.args.to st.call.args.amt)).sum := by
  have : Balance.read st.post = diff (Balance.read st.pre)
      (only st.call.caller st.call.args.amt) (only st.call.args.to st.call.args.amt) := by
    funext a
    grind [diff, only, balance_after]
  rw [this, sum_diff]

/-! ## Reading storage -/

@[answer =] theorem read_def (s : Storage) (a : Addr) :
    Balance.read s a = Stored.ofVal (s (.entry Balance.name a)) := rfl

@[answer =] theorem I128_MAX_eq : I128_MAX = 2 ^ 127 - 1 := rfl

end SorobanToken
