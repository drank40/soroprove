-- Auto-emitted by stellar-diver: a relational abstraction of the contract,
-- one `Step → Prop` per entrypoint, in the style of SorobanAmm.lean.
--
-- RECONSTRUCTED from the bytecode, in terms of call arguments, storage slots
-- (real DataKey names) and token ledgers:
--   * effects, in program order, as a chain of states s1, s2, …: SEP-41
--     transfers (`xfer`: ledger, from, to, amount) and storage writes, each
--     under the (non-panic) branch condition it runs in;
--   * every read sees the state at its program point (a balance read after a
--     transfer reads the post-transfer ledger; a slot read after a write
--     reads the write — e.g. a token's self-transfer nets to zero);
--   * guards: require_auth, every panic condition and `Err` return, as the
--     condition to pass.
-- Values are rebuilt through i128 helper routines (__muloti4 / __divti3), out-
-- pointer returns and by-reference closure captures on the wasm shadow stack.
--
-- STILL `opaque`: values from loops (e.g. an integer sqrt), composite keys,
-- tuple returns, and whatever the reconstruction could not resolve.
-- ASSUMES token ledgers are keyed by the storage slot holding the token
-- address (`"TokenA"`), i.e. distinct slots hold distinct tokens.
-- Reads/writes inside one helper call are ordered at the call's position.

namespace Contract

abbrev Addr := Int

inductive Key where
  | var   (name : String)
  | entry (map : String) (k : Addr)
  deriving DecidableEq, Inhabited

abbrev Storage := Key → Int
def Storage.set (s : Storage) (k : Key) (v : Int) : Storage := fun k' => if k' = k then v else s k'

structure Call where
  fn     : String
  caller : Addr
  arg    : String → Int   -- numeric args by name
  argA   : String → Addr  -- address args by name
  signed : Addr → Prop    -- addresses that authorized the call (require_auth)

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

/-- `create(seller: Address, sell_token: Address, buy_token: Address, sell_price: u32, buy_price: u32)`
    effects (reconstructed, in program order):
      write storage.Offer/54 := map_map_new_from_linear_memory
    guards (recovered panic/gate conditions):
      auth: caller signed as `seller` (require_auth)
      gate: buy_price ≥ 4294967296
      gate: sell_price ≥ 4294967296
-/
opaque create_e_g1 : Step → Int
def create : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (st.pre).set (.var "Offer") ((create_e_g1 st))
  st.call.fn = "create" ∧
  c ≠ pool ∧
  c = st.call.argA "seller" ∧   -- require_auth
  st.call.arg "buy_price" ≥ 4294967296 ∧   -- gate
  st.call.arg "sell_price" ≥ 4294967296 ∧   -- gate
  st.post = s1 ∧
  st.writes = [.var "Offer"] ∧
  st.ret = 0

/-- `get_offer()`
    transfers: (none recovered)
-/
opaque get_offer_ret : Step → Int
def get_offer : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "get_offer" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = get_offer_ret st

/-- `trade(buyer: Address, buy_token_amount: i128, min_sell_token_amount: i128)`
    effects (reconstructed, in program order):
      transfer (toString (st.call.argA "min_sell_token_amount")): buyer -> @pool : buy_token_amount
      transfer "Token?1" = Load: @pool -> buyer : Select(ICmp_SGT(Select(Or(ICmp_EQ(buy_token_amount, 0), ICmp_EQ(min_sell_token_amount, 0)), 0, Select(ICmp_SGT(buy_token_amount, -1), Select(ICmp_EQ(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (ICmp_NE(buy_token_amount, 0) - buy_token_amount)), 0), LShr((LShr(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (0 - buy_token_amount)), 32) * min_sell_token_amount), 32), (LShr((LShr(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (0 - buy_token_amount)), 32) * min_sell_token_amount), 32) + (Shl((LShr(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (ICmp_NE(buy_token_amount, 0) - buy_token_amount)), 32) * min_sell_token_amount), 32) + (And(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (ICmp_NE(buy_token_amount, 0) - buy_token_amount)), 4294967295) * min_sell_token_amount)))), (ICmp_NE((Shl((LShr(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (0 - buy_token_amount)), 32) * min_sell_token_amount), 32) + (And(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (0 - buy_token_amount)), 4294967295) * min_sell_token_amount)), 0) - Select(ICmp_EQ(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (ICmp_NE(buy_token_amount, 0) - buy_token_amount)), 0), LShr((LShr(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (0 - buy_token_amount)), 32) * min_sell_token_amount), 32), (LShr((LShr(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (0 - buy_token_amount)), 32) * min_sell_token_amount), 32) + (Shl((LShr(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (ICmp_NE(buy_token_amount, 0) - buy_token_amount)), 32) * min_sell_token_amount), 32) + (And(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (ICmp_NE(buy_token_amount, 0) - buy_token_amount)), 4294967295) * min_sell_token_amount))))))), -1), big, (0 - big))
      transfer (toString (st.call.argA "min_sell_token_amount")): @pool -> 0 : buy_token_amount
    guards (recovered panic/gate conditions):
      auth: caller signed as `buyer` (require_auth)
      gate: min_sell_token_amount ≤ Select(ICmp_SGT(Select(Or(ICmp_EQ(buy_token_amount, 0), ICmp_EQ(min_sell_token_amount, 0)), 0, Select(ICmp_SGT(buy_token_amount, -1), Select(ICmp_EQ(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (ICmp_NE(buy_token_amount, 0) - buy_token_amount)), 0), LShr((LShr(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (0 - buy_token_amount)), 32) * min_sell_token_amount), 32), (LShr((LShr(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (0 - buy_token_amount)), 32) * min_sell_token_amount), 32) + (Shl((LShr(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (ICmp_NE(buy_token_amount, 0) - buy_token_amount)), 32) * min_sell_token_amount), 32) + (And(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (ICmp_NE(buy_token_amount, 0) - buy_token_amount)), 4294967295) * min_sell_token_amount)))), (ICmp_NE((Shl((LShr(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (0 - buy_token_amount)), 32) * min_sell_token_amount), 32) + (And(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (0 - buy_token_amount)), 4294967295) * min_sell_token_amount)), 0) - Select(ICmp_EQ(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (ICmp_NE(buy_token_amount, 0) - buy_token_amount)), 0), LShr((LShr(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (0 - buy_token_amount)), 32) * min_sell_token_amount), 32), (LShr((LShr(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (0 - buy_token_amount)), 32) * min_sell_token_amount), 32) + (Shl((LShr(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (ICmp_NE(buy_token_amount, 0) - buy_token_amount)), 32) * min_sell_token_amount), 32) + (And(Select(ICmp_SGT(buy_token_amount, -1), buy_token_amount, (ICmp_NE(buy_token_amount, 0) - buy_token_amount)), 4294967295) * min_sell_token_amount))))))), -1), big, (0 - big))
-/
opaque trade_e_g1 : Step → Int
opaque trade_e_g2 : Step → Int
opaque trade_e_g3 : Step → Int
opaque trade_g1 : Step → Int
opaque trade_g2 : Step → Int
opaque trade_g3 : Step → Int
def trade : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := xfer (toString (st.call.argA "min_sell_token_amount")) st.pre (st.call.argA "buyer") (pool) (st.call.arg "buy_token_amount")
  let s2 := xfer "Token?1" s1 (pool) (st.call.argA "buyer") ((if (trade_e_g1 st) > -1 then (trade_e_g2 st) else (0 - (trade_e_g3 st))))
  let s3 := xfer (toString (st.call.argA "min_sell_token_amount")) s2 (pool) (0) (st.call.arg "buy_token_amount")
  st.call.fn = "trade" ∧
  c ≠ pool ∧
  c = st.call.argA "buyer" ∧   -- require_auth
  st.call.arg "min_sell_token_amount" ≤ (if (trade_g1 st) > -1 then (trade_g2 st) else (0 - (trade_g3 st))) ∧   -- gate
  st.post = s3 ∧
  st.writes = [.entry (toString (st.call.argA "min_sell_token_amount")) (st.call.argA "buyer"), .entry (toString (st.call.argA "min_sell_token_amount")) (pool), .entry "Token?1" (pool), .entry "Token?1" (st.call.argA "buyer"), .entry (toString (st.call.argA "min_sell_token_amount")) (0)] ∧
  st.ret = 0

/-- `updt_price(sell_price: u32, buy_price: u32)`
    effects (reconstructed, in program order):
      write storage.Offer/32 := map_map_new_from_linear_memory
    guards (recovered panic/gate conditions):
      gate: sell_price ≥ 4294967296
      gate: buy_price ≥ 4294967296
-/
opaque updt_price_e_g1 : Step → Int
def updt_price : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (st.pre).set (.var "Offer") ((updt_price_e_g1 st))
  st.call.fn = "updt_price" ∧
  c ≠ pool ∧
  st.call.arg "sell_price" ≥ 4294967296 ∧   -- gate
  st.call.arg "buy_price" ≥ 4294967296 ∧   -- gate
  st.post = s1 ∧
  st.writes = [.var "Offer"] ∧
  st.ret = 0

/-- `withdraw(token: Address, amount: i128)`
    effects (reconstructed, in program order):
      transfer (toString (st.call.argA "token")): @pool -> 0 : amount
-/
def withdraw : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := xfer (toString (st.call.argA "token")) st.pre (pool) (0) (st.call.arg "amount")
  st.call.fn = "withdraw" ∧
  c ≠ pool ∧
  st.post = s1 ∧
  st.writes = [.entry (toString (st.call.argA "token")) (pool), .entry (toString (st.call.argA "token")) (0)] ∧
  st.ret = 0

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [create, get_offer, trade, updt_price, withdraw]

end Contract
