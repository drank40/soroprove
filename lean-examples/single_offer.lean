-- Auto-emitted by stellar-diver: a relational model of the contract, one
-- `Step → Prop` per entrypoint (in the style of SorobanAmm.lean), reconstructed
-- from the bytecode over call arguments, signers, storage and token ledgers.
--
-- It is built to OVER-approximate the contract: every successful invocation is
-- a step its entrypoint admits, for some choice of `u : Unk` (the values the
-- reconstruction leaves open). So a property proved of every admitted step
-- holds of the contract. Concretely:
--   * effects run in execution order as states s1, s2, …, each under the exact
--     condition its code runs in; a read sees the state at its program point;
--   * an effect the model doesn't interpret is not dropped: a call into another
--     contract leaves every token ledger open (`havoc`), an effect inside a
--     loop or past the analysis depth leaves all storage open;
--   * conditions to succeed: `require_auth` (the address is among the signers),
--     panics (`reach → pass`) and `Err` returns; a guard that can't be stated
--     is dropped, never guessed.
-- Storage keys: `.var` (unit variant), `.entry` / `.tup` (variants with one /
-- several fields), `.fld k f` (field f of the #[contracttype] struct at k),
-- `.has k` (k's presence: set → 1, remove → 0), `.bal t a` (token t's balance
-- of a). Struct arguments' fields are args named like `config.limit`.
--
-- Assumes: tokens the contract calls `transfer` / `balance` on behave per
-- SEP-41; addresses are encoded as `Addr` in the host's order (`obj_cmp`).

namespace Contract

abbrev Addr := Int

inductive Key where
  | var   (name : String)
  | entry (map : String) (k : Addr)
  | tup   (map : String) (ks : List Int)
  | fld   (base : Key) (f : String)
  | has   (k : Key)
  | bal   (t : Addr) (a : Addr)
  deriving DecidableEq, Inhabited

abbrev Storage := Key → Int
def Storage.set (s : Storage) (k : Key) (v : Int) : Storage := fun k' => if k' = k then v else s k'

structure Call where
  fn      : String
  caller  : Addr
  self    : Addr           -- the contract's own address
  arg     : String → Int   -- numeric args by name
  argA    : String → Addr  -- address args by name
  signers : List Addr      -- addresses that authorized the call (require_auth)
  env     : String → Int   -- ledger info (`sequence`, `timestamp`)

structure Step where
  call   : Call
  pre    : Storage
  post   : Storage
  writes : List Key
  ret    : Int

/-- Values the reconstruction leaves open, chosen per step. -/
structure Unk where
  i : Nat → Int      -- values
  g : Nat → Int      -- guard operands
  b : Nat → Bool     -- branch conditions
  k : Nat → Key      -- storage keys
  s : Nat → Storage  -- storage after an effect the model doesn't interpret

/-- token `t`'s balance of `a`. -/
def bal (t : Addr) (s : Storage) (a : Addr) : Int := s (.bal t a)
/-- storage after token `t` moves `amt` from `src` to `dst` (a self-transfer nets to zero). -/
def xfer (t : Addr) (s : Storage) (src dst : Addr) (amt : Int) : Storage :=
  let s1 := s.set (.bal t src) (bal t s src - amt)
  s1.set (.bal t dst) (bal t s1 dst + amt)
/-- storage after a call into another contract the model doesn't interpret: the
    contract's own storage is unchanged (Soroban forbids re-entry); token
    ledgers take `h`'s values. -/
def havoc (s h : Storage) : Storage := fun k => match k with
  | .bal t a => h (.bal t a)
  | _ => s k
/-- `get(k).unwrap_or(0)`: the value at `k`, or 0 when `base` (k's struct) is absent. -/
def getOr0 (s : Storage) (k : Key) (base : Key := k) : Int := if s (.has base) = 1 then s k else 0

/-- `create(seller: Address, sell_token: Address, buy_token: Address, sell_price: u32, buy_price: u32)`
    effects, in execution order:
      write storage.Offer/2 := @struct:buy_price,buy_token,sell_price,sell_token,seller(buy_price, buy_token, sell_price, sell_token, seller)
    conditions to succeed:
      require_auth seller
      gate: buy_price ≥ 1
      gate: sell_price ≥ 1
      gate: @has(storage.Offer/1) ≠ 1
-/
def create : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  let s1 := ((((((st.pre).set (.fld (.var "Offer") "buy_price") (st.call.arg "buy_price")).set (.fld (.var "Offer") "buy_token") (st.call.argA "buy_token")).set (.fld (.var "Offer") "sell_price") (st.call.arg "sell_price")).set (.fld (.var "Offer") "sell_token") (st.call.argA "sell_token")).set (.fld (.var "Offer") "seller") (st.call.argA "seller")).set (.has (.var "Offer")) (1)
  st.call.fn = "create" ∧
  c ≠ pool ∧
  st.call.argA "seller" ∈ st.call.signers ∧   -- require_auth seller
  st.call.arg "buy_price" ≥ 1 ∧   -- gate
  st.call.arg "sell_price" ≥ 1 ∧   -- gate
  (st.pre (.has (.var "Offer"))) ≠ 1 ∧   -- gate
  st.post = s1 ∧
  st.writes = [.fld (.var "Offer") "buy_price", .fld (.var "Offer") "buy_token", .fld (.var "Offer") "sell_price", .fld (.var "Offer") "sell_token", .fld (.var "Offer") "seller", .has (.var "Offer")] ∧
  st.ret = 2

/-- `get_offer()`
-/
def get_offer : Step → Prop := fun st => ∃ u : Unk,
  let c := st.call.caller
  let pool := st.call.self
  st.call.fn = "get_offer" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (u.i 1)

/-- `trade(buyer: Address, buy_token_amount: i128, min_sell_token_amount: i128)`
    effects, in execution order:
      transfer @field:buy_token(storage.Offer/8): buyer -> @pool : buy_token_amount
      transfer @field:sell_token(storage.Offer/8): @pool -> buyer : big
      transfer @field:buy_token(storage.Offer/8): @pool -> @field:seller(storage.Offer/8) : buy_token_amount
    conditions to succeed:
      require_auth buyer
      gate: min_sell_token_amount ≤ big
-/
def trade : Step → Prop := fun st => ∃ u : Unk,
  let c := st.call.caller
  let pool := st.call.self
  let s1 := xfer ((st.pre (.fld (.var "Offer") "buy_token"))) st.pre (st.call.argA "buyer") (pool) (st.call.arg "buy_token_amount")
  let s2 := xfer ((st.pre (.fld (.var "Offer") "sell_token"))) s1 (pool) (st.call.argA "buyer") ((u.i 1))
  let s3 := xfer ((st.pre (.fld (.var "Offer") "buy_token"))) s2 (pool) ((st.pre (.fld (.var "Offer") "seller"))) (st.call.arg "buy_token_amount")
  st.call.fn = "trade" ∧
  c ≠ pool ∧
  st.call.argA "buyer" ∈ st.call.signers ∧   -- require_auth buyer
  st.call.arg "min_sell_token_amount" ≤ (u.g 1) ∧   -- gate
  st.post = s3 ∧
  st.writes = [.bal ((st.pre (.fld (.var "Offer") "buy_token"))) (st.call.argA "buyer"), .bal ((st.pre (.fld (.var "Offer") "buy_token"))) (pool), .bal ((st.pre (.fld (.var "Offer") "sell_token"))) (pool), .bal ((st.pre (.fld (.var "Offer") "sell_token"))) (st.call.argA "buyer"), .bal ((st.pre (.fld (.var "Offer") "buy_token"))) ((st.pre (.fld (.var "Offer") "seller")))] ∧
  st.ret = 2

/-- `updt_price(sell_price: u32, buy_price: u32)`
    effects, in execution order:
      write storage.Offer/17 := @struct:buy_price,buy_token,sell_price,sell_token,seller(buy_price, @field:buy_token(storage.Offer/19), sell_price, @field:sell_token(storage.Offer/19), @field:seller(storage.Offer/19))
    conditions to succeed:
      require_auth @field:seller(storage.Offer/19)
      gate: sell_price ≥ 1
      gate: buy_price ≥ 1
-/
def updt_price : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  let s1 := ((((((st.pre).set (.fld (.var "Offer") "buy_price") (st.call.arg "buy_price")).set (.fld (.var "Offer") "buy_token") ((st.pre (.fld (.var "Offer") "buy_token")))).set (.fld (.var "Offer") "sell_price") (st.call.arg "sell_price")).set (.fld (.var "Offer") "sell_token") ((st.pre (.fld (.var "Offer") "sell_token")))).set (.fld (.var "Offer") "seller") ((st.pre (.fld (.var "Offer") "seller")))).set (.has (.var "Offer")) (1)
  st.call.fn = "updt_price" ∧
  c ≠ pool ∧
  (st.pre (.fld (.var "Offer") "seller")) ∈ st.call.signers ∧   -- require_auth @field:seller(storage.Offer/19)
  st.call.arg "sell_price" ≥ 1 ∧   -- gate
  st.call.arg "buy_price" ≥ 1 ∧   -- gate
  st.post = s1 ∧
  st.writes = [.fld (.var "Offer") "buy_price", .fld (.var "Offer") "buy_token", .fld (.var "Offer") "sell_price", .fld (.var "Offer") "sell_token", .fld (.var "Offer") "seller", .has (.var "Offer")] ∧
  st.ret = 2

/-- `withdraw(token: Address, amount: i128)`
    effects, in execution order:
      transfer token: @pool -> @field:seller(storage.Offer/21) : amount
    conditions to succeed:
      require_auth @field:seller(storage.Offer/21)
-/
def withdraw : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  let s1 := xfer (st.call.argA "token") st.pre (pool) ((st.pre (.fld (.var "Offer") "seller"))) (st.call.arg "amount")
  st.call.fn = "withdraw" ∧
  c ≠ pool ∧
  (st.pre (.fld (.var "Offer") "seller")) ∈ st.call.signers ∧   -- require_auth @field:seller(storage.Offer/21)
  st.post = s1 ∧
  st.writes = [.bal (st.call.argA "token") (pool), .bal (st.call.argA "token") ((st.pre (.fld (.var "Offer") "seller")))] ∧
  st.ret = 2

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [create, get_offer, trade, updt_price, withdraw]

end Contract
