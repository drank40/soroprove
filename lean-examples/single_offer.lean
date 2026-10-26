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
  deriving DecidableEq, Inhabited, Repr

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

/-- the contract's own address (`e.current_contract_address()`). -/
@[simp] def pool (st : Step) : Addr := st.call.self

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

/-! ## Storage layout -/

@[simp] def Offer : Key := .var "Offer"
@[simp] def Offer.buy_price : Key := .fld Offer "buy_price"
@[simp] def Offer.buy_token : Key := .fld Offer "buy_token"
@[simp] def Offer.sell_price : Key := .fld Offer "sell_price"
@[simp] def Offer.sell_token : Key := .fld Offer "sell_token"
@[simp] def Offer.seller : Key := .fld Offer "seller"

namespace create
@[simp] def buy_price (st : Step) : Int := st.call.arg "buy_price"
@[simp] def buy_token (st : Step) : Addr := st.call.argA "buy_token"
@[simp] def sell_price (st : Step) : Int := st.call.arg "sell_price"
@[simp] def sell_token (st : Step) : Addr := st.call.argA "sell_token"
@[simp] def seller (st : Step) : Addr := st.call.argA "seller"
@[simp] def s1 (st : Step) : Storage :=
  ((((((st.pre).set Offer.buy_price (create.buy_price st)).set Offer.buy_token (create.buy_token st)).set Offer.sell_price (create.sell_price st)).set Offer.sell_token (create.sell_token st)).set Offer.seller (create.seller st)).set (.has Offer) 1
end create

/-- `create(seller: Address, sell_token: Address, buy_token: Address, sell_price: u32, buy_price: u32)`
    effects, in execution order (states `create.s1`, `create.s2`, …):
      write storage.Offer/2 := @struct:buy_price,buy_token,sell_price,sell_token,seller(buy_price, buy_token, sell_price, sell_token, seller)
    conditions to succeed:
      require_auth seller
      gate: buy_price ≥ 1
      gate: sell_price ≥ 1
      gate: @has(storage.Offer/1) ≠ 1
-/
def create : Step → Prop := fun st =>
  st.call.fn = "create" ∧
  st.call.caller ≠ pool st ∧
  (create.seller st) ∈ st.call.signers ∧   -- require_auth seller
  (create.buy_price st) ≥ 1 ∧   -- gate
  (create.sell_price st) ≥ 1 ∧   -- gate
  (st.pre (.has Offer)) ≠ 1 ∧   -- gate
  st.post = (create.s1 st) ∧
  st.writes = [Offer.buy_price, Offer.buy_token, Offer.sell_price, Offer.sell_token, Offer.seller, .has Offer] ∧
  st.ret = 2

/-- `get_offer()`
-/
def get_offer : Step → Prop := fun st => ∃ u : Unk,
  st.call.fn = "get_offer" ∧
  st.call.caller ≠ pool st ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (u.i 1)

namespace trade
@[simp] def buy_token_amount (st : Step) : Int := st.call.arg "buy_token_amount"
@[simp] def buyer (st : Step) : Addr := st.call.argA "buyer"
@[simp] def min_sell_token_amount (st : Step) : Int := st.call.arg "min_sell_token_amount"
@[simp] def amt1 (st : Step) : Int :=
  (trade.buy_token_amount st)
@[simp] def s1 (st : Step) : Storage :=
  xfer (st.pre Offer.buy_token) st.pre (trade.buyer st) (pool st) (trade.amt1 st)
@[simp] def amt2 (_st : Step) (u : Unk) : Int :=
  (u.i 1)
@[simp] def s2 (st : Step) (u : Unk) : Storage :=
  xfer (st.pre Offer.sell_token) (trade.s1 st) (pool st) (trade.buyer st) (trade.amt2 st u)
@[simp] def amt3 (st : Step) : Int :=
  (trade.buy_token_amount st)
@[simp] def s3 (st : Step) (u : Unk) : Storage :=
  xfer (st.pre Offer.buy_token) (trade.s2 st u) (pool st) (st.pre Offer.seller) (trade.amt3 st)
end trade

/-- `trade(buyer: Address, buy_token_amount: i128, min_sell_token_amount: i128)`
    effects, in execution order (states `trade.s1`, `trade.s2`, …; amounts `trade.amt1`, …):
      transfer @field:buy_token(storage.Offer/8): buyer -> @pool : buy_token_amount
      transfer @field:sell_token(storage.Offer/8): @pool -> buyer : big
      transfer @field:buy_token(storage.Offer/8): @pool -> @field:seller(storage.Offer/8) : buy_token_amount
    conditions to succeed:
      require_auth buyer
      gate: min_sell_token_amount ≤ big
-/
def trade : Step → Prop := fun st => ∃ u : Unk,
  st.call.fn = "trade" ∧
  st.call.caller ≠ pool st ∧
  (trade.buyer st) ∈ st.call.signers ∧   -- require_auth buyer
  (trade.min_sell_token_amount st) ≤ (u.g 1) ∧   -- gate
  st.post = (trade.s3 st u) ∧
  st.writes = [.bal (st.pre Offer.buy_token) (trade.buyer st), .bal (st.pre Offer.buy_token) (pool st), .bal (st.pre Offer.sell_token) (pool st), .bal (st.pre Offer.sell_token) (trade.buyer st), .bal (st.pre Offer.buy_token) (st.pre Offer.seller)] ∧
  st.ret = 2

namespace updt_price
@[simp] def buy_price (st : Step) : Int := st.call.arg "buy_price"
@[simp] def sell_price (st : Step) : Int := st.call.arg "sell_price"
@[simp] def s1 (st : Step) : Storage :=
  ((((((st.pre).set Offer.buy_price (updt_price.buy_price st)).set Offer.buy_token (st.pre Offer.buy_token)).set Offer.sell_price (updt_price.sell_price st)).set Offer.sell_token (st.pre Offer.sell_token)).set Offer.seller (st.pre Offer.seller)).set (.has Offer) 1
end updt_price

/-- `updt_price(sell_price: u32, buy_price: u32)`
    effects, in execution order (states `updt_price.s1`, `updt_price.s2`, …):
      write storage.Offer/17 := @struct:buy_price,buy_token,sell_price,sell_token,seller(buy_price, @field:buy_token(storage.Offer/19), sell_price, @field:sell_token(storage.Offer/19), @field:seller(storage.Offer/19))
    conditions to succeed:
      require_auth @field:seller(storage.Offer/19)
      gate: sell_price ≥ 1
      gate: buy_price ≥ 1
-/
def updt_price : Step → Prop := fun st =>
  st.call.fn = "updt_price" ∧
  st.call.caller ≠ pool st ∧
  (st.pre Offer.seller) ∈ st.call.signers ∧   -- require_auth @field:seller(storage.Offer/19)
  (updt_price.sell_price st) ≥ 1 ∧   -- gate
  (updt_price.buy_price st) ≥ 1 ∧   -- gate
  st.post = (updt_price.s1 st) ∧
  st.writes = [Offer.buy_price, Offer.buy_token, Offer.sell_price, Offer.sell_token, Offer.seller, .has Offer] ∧
  st.ret = 2

namespace withdraw
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def token (st : Step) : Addr := st.call.argA "token"
@[simp] def amt1 (st : Step) : Int :=
  (withdraw.amount st)
@[simp] def s1 (st : Step) : Storage :=
  xfer (withdraw.token st) st.pre (pool st) (st.pre Offer.seller) (withdraw.amt1 st)
end withdraw

/-- `withdraw(token: Address, amount: i128)`
    effects, in execution order (states `withdraw.s1`, `withdraw.s2`, …; amounts `withdraw.amt1`, …):
      transfer token: @pool -> @field:seller(storage.Offer/21) : amount
    conditions to succeed:
      require_auth @field:seller(storage.Offer/21)
-/
def withdraw : Step → Prop := fun st =>
  st.call.fn = "withdraw" ∧
  st.call.caller ≠ pool st ∧
  (st.pre Offer.seller) ∈ st.call.signers ∧   -- require_auth @field:seller(storage.Offer/21)
  st.post = (withdraw.s1 st) ∧
  st.writes = [.bal (withdraw.token st) (pool st), .bal (withdraw.token st) (st.pre Offer.seller)] ∧
  st.ret = 2

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [create, get_offer, trade, updt_price, withdraw]

end Contract
