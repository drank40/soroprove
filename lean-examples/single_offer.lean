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
-- Storage keys: `.var` (unit variant), `.entry` / `.tup` (variants with one /
-- several fields), `.fld k f` (field f of the #[contracttype] struct stored at
-- k, nested structs field by field) and `.has k` (k's presence: set → 1,
-- remove → 0). Struct arguments' fields are args named `config.limit`.
--
-- STILL `opaque`: values from loops (e.g. an integer sqrt), tuple and whole-
-- struct returns, enum values carried as data, and whatever the
-- reconstruction could not resolve (a branch condition so becomes an opaque
-- `Step → Bool`, never `False`).
-- ASSUMES token ledgers are keyed by the storage slot holding the token
-- address (`"TokenA"`, `"Offer.buy_token"`), i.e. distinct slots hold
-- distinct tokens; an absent key reads as 0 (`get(k).unwrap_or(0)`); the
-- host's address order (`obj_cmp`) is the order on `Addr`; loops terminate.
-- Reads/writes inside one helper call are ordered at the call's position.

namespace Contract

abbrev Addr := Int

inductive Key where
  | var   (name : String)
  | entry (map : String) (k : Addr)
  | tup   (map : String) (ks : List Int)   -- a multi-field key variant, `Minter(a, b)`
  | fld   (base : Key) (f : String)   -- a field of the #[contracttype] struct at `base`
  | has   (k : Key)                   -- k's presence (1 = set): `has(k)`, written by set/remove
  deriving DecidableEq, Inhabited

abbrev Storage := Key → Int
def Storage.set (s : Storage) (k : Key) (v : Int) : Storage := fun k' => if k' = k then v else s k'

structure Call where
  fn     : String
  caller : Addr
  arg    : String → Int   -- numeric args by name
  argA   : String → Addr  -- address args by name
  signed : Addr → Prop    -- addresses that authorized the call (require_auth)
  env    : String → Int   -- ledger info (`sequence`, `timestamp`)

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
  let s1 := s.set (.entry m src) (bal m s src - amt)   -- (a self-transfer nets to zero)
  s1.set (.entry m dst) (bal m s1 dst + amt)

/-- `create(seller: Address, sell_token: Address, buy_token: Address, sell_price: u32, buy_price: u32)`
    effects (reconstructed, in program order):
      write storage.Offer/54 := @struct:buy_price,buy_token,sell_price,sell_token,seller(buy_price, buy_token, sell_price, sell_token, seller)
    guards (recovered panic/gate conditions):
      auth: caller signed as `seller` (require_auth)
      gate: buy_price ≥ 1
      gate: sell_price ≥ 1
      gate: @has(storage.Offer/27) ≠ 1
-/
def create : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := ((((((st.pre).set (.fld (.var "Offer") "buy_price") (st.call.arg "buy_price")).set (.fld (.var "Offer") "buy_token") (st.call.argA "buy_token")).set (.fld (.var "Offer") "sell_price") (st.call.arg "sell_price")).set (.fld (.var "Offer") "sell_token") (st.call.argA "sell_token")).set (.fld (.var "Offer") "seller") (st.call.argA "seller")).set (.has (.var "Offer")) (1)
  st.call.fn = "create" ∧
  c ≠ pool ∧
  c = st.call.argA "seller" ∧   -- require_auth
  st.call.arg "buy_price" ≥ 1 ∧   -- gate
  st.call.arg "sell_price" ≥ 1 ∧   -- gate
  (st.pre (.has (.var "Offer"))) ≠ 1 ∧   -- gate
  st.post = s1 ∧
  st.writes = [.fld (.var "Offer") "buy_price", .fld (.var "Offer") "buy_token", .fld (.var "Offer") "sell_price", .fld (.var "Offer") "sell_token", .fld (.var "Offer") "seller", .has (.var "Offer")] ∧
  st.ret = 0

/-- `get_offer()`
    effects (reconstructed, in program order):
-/
opaque get_offer_e_g1 : Step → Int
def get_offer : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "get_offer" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (get_offer_e_g1 st)

/-- `trade(buyer: Address, buy_token_amount: i128, min_sell_token_amount: i128)`
    effects (reconstructed, in program order):
      transfer "Offer.buy_token": buyer -> @pool : buy_token_amount
      transfer "Offer.sell_token": @pool -> buyer : big
      transfer "Offer.buy_token": @pool -> @field:seller(storage.Offer/46) : buy_token_amount
    guards (recovered panic/gate conditions):
      auth: caller signed as `buyer` (require_auth)
      gate: min_sell_token_amount ≤ big
-/
opaque trade_e_g1 : Step → Int
opaque trade_g1 : Step → Int
def trade : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := xfer "Offer.buy_token" st.pre (st.call.argA "buyer") (pool) (st.call.arg "buy_token_amount")
  let s2 := xfer "Offer.sell_token" s1 (pool) (st.call.argA "buyer") ((trade_e_g1 st))
  let s3 := xfer "Offer.buy_token" s2 (pool) ((st.pre (.fld (.var "Offer") "seller"))) (st.call.arg "buy_token_amount")
  st.call.fn = "trade" ∧
  c ≠ pool ∧
  c = st.call.argA "buyer" ∧   -- require_auth
  st.call.arg "min_sell_token_amount" ≤ (trade_g1 st) ∧   -- gate
  st.post = s3 ∧
  st.writes = [.entry "Offer.buy_token" (st.call.argA "buyer"), .entry "Offer.buy_token" (pool), .entry "Offer.sell_token" (pool), .entry "Offer.sell_token" (st.call.argA "buyer"), .entry "Offer.buy_token" ((st.pre (.fld (.var "Offer") "seller")))] ∧
  st.ret = 0

/-- `updt_price(sell_price: u32, buy_price: u32)`
    effects (reconstructed, in program order):
      write storage.Offer/30 := @struct:buy_price,buy_token,sell_price,sell_token,seller(buy_price, @field:buy_token(storage.Offer/20), sell_price, @field:sell_token(storage.Offer/20), @field:seller(storage.Offer/20))
    guards (recovered panic/gate conditions):
      gate: sell_price ≥ 1
      gate: buy_price ≥ 1
-/
def updt_price : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := ((((((st.pre).set (.fld (.var "Offer") "buy_price") (st.call.arg "buy_price")).set (.fld (.var "Offer") "buy_token") ((st.pre (.fld (.var "Offer") "buy_token")))).set (.fld (.var "Offer") "sell_price") (st.call.arg "sell_price")).set (.fld (.var "Offer") "sell_token") ((st.pre (.fld (.var "Offer") "sell_token")))).set (.fld (.var "Offer") "seller") ((st.pre (.fld (.var "Offer") "seller")))).set (.has (.var "Offer")) (1)
  st.call.fn = "updt_price" ∧
  c ≠ pool ∧
  st.call.signed (st.pre (.fld (.var "Offer") "seller")) ∧   -- require_auth
  st.call.arg "sell_price" ≥ 1 ∧   -- gate
  st.call.arg "buy_price" ≥ 1 ∧   -- gate
  st.post = s1 ∧
  st.writes = [.fld (.var "Offer") "buy_price", .fld (.var "Offer") "buy_token", .fld (.var "Offer") "sell_price", .fld (.var "Offer") "sell_token", .fld (.var "Offer") "seller", .has (.var "Offer")] ∧
  st.ret = 0

/-- `withdraw(token: Address, amount: i128)`
    effects (reconstructed, in program order):
      transfer (toString (st.call.argA "token")): @pool -> @field:seller(storage.Offer/27) : amount
-/
def withdraw : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := xfer (toString (st.call.argA "token")) st.pre (pool) ((st.pre (.fld (.var "Offer") "seller"))) (st.call.arg "amount")
  st.call.fn = "withdraw" ∧
  c ≠ pool ∧
  st.call.signed (st.pre (.fld (.var "Offer") "seller")) ∧   -- require_auth
  st.post = s1 ∧
  st.writes = [.entry (toString (st.call.argA "token")) (pool), .entry (toString (st.call.argA "token")) ((st.pre (.fld (.var "Offer") "seller")))] ∧
  st.ret = 0

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [create, get_offer, trade, updt_price, withdraw]

end Contract
