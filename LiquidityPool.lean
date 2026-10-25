-- Auto-emitted by stellar-diver: a relational abstraction of the contract,
-- one `Step → Prop` per entrypoint, in the style of SorobanAmm.lean.
-- RECOVERED from bytecode: entrypoints + ABI args, SEP-41 transfer directions
-- (traced through the fastcc helpers), and the storage slots each writes/reads
-- (real DataKey names). UNINTERPRETED (nonlinear fee/share math): transfer
-- amounts and stored values, shown as `opaque` Step-indexed terms.

namespace Contract

abbrev Addr := Int

inductive Key where
  | var   (name : String)
  | entry (map : String) (k : Addr)
  deriving DecidableEq

abbrev Storage := Key → Int
def Storage.set (s : Storage) (k : Key) (v : Int) : Storage := fun k' => if k' = k then v else s k'

structure Call where
  fn     : String
  caller : Addr
  arg    : String → Int

structure Step where
  call   : Call
  pre    : Storage
  post   : Storage
  writes : List Key
  ret    : Int

/-- the pool's own address (`e.current_contract_address()`). -/
opaque pool : Addr

/-- a token ledger `m`'s balance of `a`. -/
def bal (m : String) (s : Storage) (a : Addr) : Int := s (.entry m a)
/-- storage after token `m` moves `amt` from `src` to `dst`. -/
def xfer (m : String) (s : Storage) (src dst : Addr) (amt : Int) : Storage :=
  (s.set (.entry m src) (bal m s src - amt)).set (.entry m dst) (bal m s dst + amt)

/-- `__constructor(token_a: Address, token_b: Address)`
    transfers: (none recovered)
    writes storage: ReserveA, ReserveB, TokenA, TokenB, TotalShares
-/
opaque __constructor_v_ReserveA : Step → Int
opaque __constructor_v_ReserveB : Step → Int
opaque __constructor_v_TokenA : Step → Int
opaque __constructor_v_TokenB : Step → Int
opaque __constructor_v_TotalShares : Step → Int
def __constructor : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "__constructor" ∧
  c ≠ pool ∧
  st.post = (((((st.pre.set (.var "ReserveA") (__constructor_v_ReserveA st)).set (.var "ReserveB") (__constructor_v_ReserveB st)).set (.var "TokenA") (__constructor_v_TokenA st)).set (.var "TokenB") (__constructor_v_TokenB st)).set (.var "TotalShares") (__constructor_v_TotalShares st)) ∧
  st.writes = [.var "ReserveA", .var "ReserveB", .var "TokenA", .var "TokenB", .var "TotalShares"] ∧
  st.ret = 0

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
  st.ret = balance_shares_ret st

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
def deposit : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := xfer "A.Balance" st.pre c pool (deposit_amt0 st)
  let s2 := xfer "B.Balance" s1 c pool (deposit_amt1 st)
  st.call.fn = "deposit" ∧
  c ≠ pool ∧
  st.post = ((((s2.set (.var "ReserveA") (deposit_v_ReserveA st)).set (.var "ReserveB") (deposit_v_ReserveB st)).set (.entry "Shares" c) (deposit_v_Shares st)).set (.var "TotalShares") (deposit_v_TotalShares st)) ∧
  st.writes = [.var "ReserveA", .var "ReserveB", .entry "Shares" c, .var "TotalShares"] ∧
  st.ret = 0

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
def swap : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := xfer "A.Balance" st.pre c pool (swap_amt0 st)
  let s2 := xfer "B.Balance" s1 pool c (swap_amt1 st)
  st.call.fn = "swap" ∧
  c ≠ pool ∧
  st.post = ((s2.set (.var "ReserveA") (swap_v_ReserveA st)).set (.var "ReserveB") (swap_v_ReserveB st)) ∧
  st.writes = [.var "ReserveA", .var "ReserveB"] ∧
  st.ret = 0

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
opaque withdraw_ret : Step → Int
def withdraw : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := xfer "A.Balance" st.pre pool c (withdraw_amt0 st)
  let s2 := xfer "B.Balance" s1 pool c (withdraw_amt1 st)
  st.call.fn = "withdraw" ∧
  c ≠ pool ∧
  st.post = ((((s2.set (.var "ReserveA") (withdraw_v_ReserveA st)).set (.var "ReserveB") (withdraw_v_ReserveB st)).set (.entry "Shares" c) (withdraw_v_Shares st)).set (.var "TotalShares") (withdraw_v_TotalShares st)) ∧
  st.writes = [.var "ReserveA", .var "ReserveB", .entry "Shares" c, .var "TotalShares"] ∧
  st.ret = withdraw_ret st

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [__constructor, balance_shares, deposit, swap, withdraw]

end Contract
