import StellarLean.Query

/-
  `transfer` from Soroban's token example (stellar/soroban-examples, token/),
  translated by hand the way a WASM → Lean converter would describe it.

    fn transfer(e: Env, from: Address, to_muxed: MuxedAddress, amount: i128) {
        from.require_auth();
        check_nonnegative_amount(amount);            // panics if amount < 0
        e.storage().instance().extend_ttl(...);
        spend_balance(&e, from.clone(), amount);
        let to: Address = to_muxed.address();
        receive_balance(&e, to.clone(), amount);
        events::Transfer { ... }.publish(&e);
    }

    fn read_balance(e, addr) -> i128      // `Balance(addr)` in persistent storage, unset = 0
    fn spend_balance(e, addr, amount)     // panics "insufficient balance" if balance < amount,
                                          // else writes balance - amount
    fn receive_balance(e, addr, amount)   // writes balance + amount (panics on i128 overflow)

  Left out, because they do not change balances: TTL extensions, the event,
  and the muxed id of `to_muxed` (only its address is used).
-/

namespace SorobanToken

open Query
open Spec (Addr)

/-! ## Storage layout -/

/-- `DataKey::Balance(Address)`, in persistent storage. -/
def Balance : Map Int := ⟨"Balance"⟩

def I128_MAX : Int := 2 ^ 127 - 1

/-- `spend_balance`: the storage after taking `amount` from `who`. -/
def spend (s : Storage) (who : Addr) (amount : Int) : Storage :=
  s.set (.entry "Balance" who) (.int (Balance.read s who - amount))

/-- `receive_balance`: the storage after giving `amount` to `who`. -/
def receive (s : Storage) (who : Addr) (amount : Int) : Storage :=
  s.set (.entry "Balance" who) (.int (Balance.read s who + amount))

/-! ## The entry point -/

/-- `transfer(from, to, amount)`. The caller is `from` (`from.require_auth()`);
    `to` and `amount` are the call's arguments. Each `panic!` means the call
    fails: there is no step. -/
def transfer : Step → Prop := fun st =>
  let sender := st.call.caller
  let to     := st.call.args.to
  let amount := st.call.args.amt
  let s1     := spend st.pre sender amount
  0 ≤ amount ∧                                    -- check_nonnegative_amount
  amount ≤ Balance.read st.pre sender ∧           -- "insufficient balance"
  Balance.read s1 to + amount ≤ I128_MAX ∧        -- `balance + amount` fits in i128
  st.post = receive s1 to amount ∧
  st.writes = [.entry "Balance" sender, .entry "Balance" to] ∧
  st.ret = .none

theorem post_eq {st : Step} (h : transfer st) :
    st.post = receive (spend st.pre st.call.caller st.call.args.amt)
      st.call.args.to st.call.args.amt := h.2.2.2.1

/-- Every balance after a transfer, in one formula. It also covers sending to
    yourself: both terms apply and cancel. -/
theorem balance_after {st : Step} (h : transfer st) (a : Addr) :
    Balance.read st.post a = Balance.read st.pre a
      - (if a = st.call.caller then st.call.args.amt else 0)
      + (if a = st.call.args.to then st.call.args.amt else 0) := by
  rw [post_eq h]
  simp only [receive, spend]
  rw [show "Balance" = Balance.name from rfl, Map.read_set, Map.read_set, Map.read_set]
  by_cases ht : a = st.call.args.to <;> by_cases hc : a = st.call.caller <;>
    simp_all <;> omega

def contract : Contract where
  entries := [transfer]
  framed e he st h k hk := by
    simp only [List.mem_cons, List.not_mem_nil, or_false] at he
    subst he
    rw [post_eq h]
    rw [h.2.2.2.2.1] at hk
    simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hk
    simp [receive, spend, Storage.set, hk.1, hk.2]

theorem contract_models {P : Question} (h : ∀ st, transfer st → P st) : contract ⊨ P := by
  intro e he
  simp only [contract, List.mem_cons, List.not_mem_nil, or_false] at he
  subst he
  exact h

end SorobanToken
