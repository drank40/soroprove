import StellarLean.Query

-- Auto-emitted by stellar-diver: a relational abstraction of the contract,
-- one `Step → Prop` per entrypoint, in the style of SorobanAmm.lean.
-- RECOVERED from bytecode: entrypoints + ABI args, SEP-41 transfer directions
-- (traced through the fastcc helpers), and the storage slots each writes/reads
-- (real DataKey names). UNINTERPRETED (nonlinear fee/share math): transfer
-- amounts and stored values, shown as `opaque` Step-indexed terms.
--
-- Not modelled: the token transfers' own checks (`XferOk`), the `to` / `user`
-- address arguments (the signer is `st.call.caller`), and `withdraw`'s
-- returned `(i128, i128)` pair.

namespace LiquidityPool

open Query
open Spec (Addr)

/-- the pool's own address (`e.current_contract_address()`). -/
opaque pool : Addr

/-! ## Storage layout -/

def TokenA      : Term Addr := var "TokenA"
def TokenB      : Term Addr := var "TokenB"
def TotalShares : Term Int  := var "TotalShares"
def ReserveA    : Term Int  := var "ReserveA"
def ReserveB    : Term Int  := var "ReserveB"
/-- `DataKey::Shares(Address)`. -/
def Shares      : Map Int   := ⟨"Shares"⟩
/-- The ledgers of token A and token B (storage of the token contracts). -/
def BalanceA    : Map Int   := ⟨"A.Balance"⟩
def BalanceB    : Map Int   := ⟨"B.Balance"⟩

/-- A number variable of the pool. -/
abbrev num (s : Storage) (name : String) : Int := read s name

/-! ## Arguments -/

def desiredA (c : Call) : Int := c.arg "desired_a"
def desiredB (c : Call) : Int := c.arg "desired_b"
def minA     (c : Call) : Int := c.arg "min_a"
def minB     (c : Call) : Int := c.arg "min_b"
def buyA     (c : Call) : Bool := c.arg "buy_a" != 0
def out      (c : Call) : Int := c.arg "out"
def inMax    (c : Call) : Int := c.arg "in_max"
def share    (c : Call) : Int := c.arg "share_amount"

/-! ## Calling a token: `token::Client::transfer(from, to, amount)` -/

def spendOn (m : Map Int) (s : Storage) (who : Addr) (amt : Int) : Storage :=
  s.set (.entry m.name who) (.int (m.read s who - amt))

def receiveOn (m : Map Int) (s : Storage) (who : Addr) (amt : Int) : Storage :=
  s.set (.entry m.name who) (.int (m.read s who + amt))

/-- storage after token `m` moves `amt` from `src` to `dst`. -/
def xfer (m : Map Int) (s : Storage) (src dst : Addr) (amt : Int) : Storage :=
  receiveOn m (spendOn m s src amt) dst amt

theorem xfer_apply (m : Map Int) (s : Storage) (src dst : Addr) (amt : Int) (k : Key)
    (h1 : k ≠ .entry m.name src) (h2 : k ≠ .entry m.name dst) :
    xfer m s src dst amt k = s k := by
  simp [xfer, receiveOn, spendOn, Storage.set, h1, h2]

/-! ## Deploy: `__constructor(token_a: Address, token_b: Address)`
    transfers: (none recovered)
    writes storage: ReserveA, ReserveB, TokenA, TokenB, TotalShares
-/
opaque __constructor_v_ReserveA : Step → Int
opaque __constructor_v_ReserveB : Step → Int
opaque __constructor_v_TokenA : Step → Addr
opaque __constructor_v_TokenB : Step → Addr
opaque __constructor_v_TotalShares : Step → Int
def __constructor : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "__constructor" ∧
  c ≠ pool ∧
  st.post = (((((st.pre.set (.var "ReserveA") (.int (__constructor_v_ReserveA st))).set (.var "ReserveB") (.int (__constructor_v_ReserveB st))).set (.var "TokenA") (.addr (__constructor_v_TokenA st))).set (.var "TokenB") (.addr (__constructor_v_TokenB st))).set (.var "TotalShares") (.int (__constructor_v_TotalShares st))) ∧
  st.writes = [.var "ReserveA", .var "ReserveB", .var "TokenA", .var "TokenB", .var "TotalShares"] ∧
  st.ret = .none

/-- Storage right after deploy: what some run of `__constructor` leaves. -/
def deployed : Invariant := fun s => ∃ st, __constructor st ∧ st.post = s

/-- `balance_shares(user: Address)`
    transfers: (none recovered)
-/
opaque balance_shares_ret : Step → Int
def balance_shares : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "balance_shares" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = .int (balance_shares_ret st)

/-- `deposit(to: Address, desired_a: i128, min_a: i128, desired_b: i128, min_b: i128)`
    transfers (direction recovered; amount uninterpreted):
      A.Balance: c -> pool
      B.Balance: c -> pool
    writes storage: ReserveA, ReserveB, Shares, TotalShares
-/
opaque deposit_amt0 : Step → Int
opaque deposit_amt1 : Step → Int
opaque deposit_v_ReserveA : Step → Int
opaque deposit_v_ReserveB : Step → Int
opaque deposit_v_Shares : Step → Int
opaque deposit_v_TotalShares : Step → Int

namespace Deposit
variable (st : Step)
def s1 : Storage := xfer BalanceA st.pre st.call.caller pool (deposit_amt0 st)
def s2 : Storage := xfer BalanceB (s1 st) st.call.caller pool (deposit_amt1 st)
end Deposit

open Deposit in
def deposit : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "deposit" ∧
  c ≠ pool ∧
  st.post = (((((s2 st).set (.var "ReserveA") (.int (deposit_v_ReserveA st))).set (.var "ReserveB") (.int (deposit_v_ReserveB st))).set (.entry "Shares" c) (.int (deposit_v_Shares st))).set (.var "TotalShares") (.int (deposit_v_TotalShares st))) ∧
  st.writes = [.entry "A.Balance" c, .entry "A.Balance" pool, .entry "B.Balance" c,
    .entry "B.Balance" pool, .var "ReserveA", .var "ReserveB", .entry "Shares" c, .var "TotalShares"] ∧
  st.ret = .none

/-- `swap(to: Address, buy_a: bool, out: i128, in_max: i128)`
    transfers (direction recovered; amount uninterpreted):
      A.Balance: c -> pool
      B.Balance: pool -> c
    writes storage: ReserveA, ReserveB
-/
opaque swap_amt0 : Step → Int
opaque swap_amt1 : Step → Int
opaque swap_v_ReserveA : Step → Int
opaque swap_v_ReserveB : Step → Int

namespace Swap
variable (st : Step)
def s1 : Storage := xfer BalanceA st.pre st.call.caller pool (swap_amt0 st)
def s2 : Storage := xfer BalanceB (s1 st) pool st.call.caller (swap_amt1 st)
end Swap

open Swap in
def swap : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "swap" ∧
  c ≠ pool ∧
  st.post = (((s2 st).set (.var "ReserveA") (.int (swap_v_ReserveA st))).set (.var "ReserveB") (.int (swap_v_ReserveB st))) ∧
  st.writes = [.entry "A.Balance" c, .entry "A.Balance" pool, .entry "B.Balance" pool,
    .entry "B.Balance" c, .var "ReserveA", .var "ReserveB"] ∧
  st.ret = .none

/-- `withdraw(to: Address, share_amount: i128, min_a: i128, min_b: i128)`
    transfers (direction recovered; amount uninterpreted):
      A.Balance: pool -> c
      B.Balance: pool -> c
    writes storage: ReserveA, ReserveB, Shares, TotalShares
-/
opaque withdraw_amt0 : Step → Int
opaque withdraw_amt1 : Step → Int
opaque withdraw_v_ReserveA : Step → Int
opaque withdraw_v_ReserveB : Step → Int
opaque withdraw_v_Shares : Step → Int
opaque withdraw_v_TotalShares : Step → Int

namespace Withdraw
variable (st : Step)
def s1 : Storage := xfer BalanceA st.pre pool st.call.caller (withdraw_amt0 st)
def s2 : Storage := xfer BalanceB (s1 st) pool st.call.caller (withdraw_amt1 st)
end Withdraw

open Withdraw in
def withdraw : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "withdraw" ∧
  c ≠ pool ∧
  st.post = (((((s2 st).set (.var "ReserveA") (.int (withdraw_v_ReserveA st))).set (.var "ReserveB") (.int (withdraw_v_ReserveB st))).set (.entry "Shares" c) (.int (withdraw_v_Shares st))).set (.var "TotalShares") (.int (withdraw_v_TotalShares st))) ∧
  st.writes = [.entry "A.Balance" pool, .entry "A.Balance" c, .entry "B.Balance" pool,
    .entry "B.Balance" c, .var "ReserveA", .var "ReserveB", .entry "Shares" c, .var "TotalShares"]

/-! ## The contract -/

/-- the contract's entry points (each a `Step → Prop`). -/
def contract : Contract where
  entries := [balance_shares, deposit, swap, withdraw]
  framed e he st h k hk := by
    simp only [List.mem_cons, List.not_mem_nil, or_false] at he
    rcases he with rfl | rfl | rfl | rfl
    · exact h.2.2.1 ▸ rfl
    · obtain ⟨-, -, hpost, hw, -⟩ := h
      rw [hw] at hk
      simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hk
      rw [hpost]
      simp only [Storage.set, hk, ite_false, Deposit.s2, Deposit.s1]
      rw [xfer_apply BalanceB _ _ _ _ _ hk.2.2.1 hk.2.2.2.1, xfer_apply BalanceA _ _ _ _ _ hk.1 hk.2.1]
    · obtain ⟨-, -, hpost, hw, -⟩ := h
      rw [hw] at hk
      simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hk
      rw [hpost]
      simp only [Storage.set, hk, ite_false, Swap.s2, Swap.s1]
      rw [xfer_apply BalanceB _ _ _ _ _ hk.2.2.1 hk.2.2.2.1, xfer_apply BalanceA _ _ _ _ _ hk.1 hk.2.1]
    · obtain ⟨-, -, hpost, hw⟩ := h
      rw [hw] at hk
      simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hk
      rw [hpost]
      simp only [Storage.set, hk, ite_false, Withdraw.s2, Withdraw.s1]
      rw [xfer_apply BalanceB _ _ _ _ _ hk.2.2.1 hk.2.2.2.1, xfer_apply BalanceA _ _ _ _ _ hk.1 hk.2.1]

end LiquidityPool
