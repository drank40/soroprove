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
@[simp] theorem Storage.set_get (s : Storage) (k k' : Key) (v : Int) :
    (s.set k v) k' = if k' = k then v else s k' := rfl
/-- a balance after a transfer: plus what came in, minus what went out. -/
@[simp] theorem bal_xfer (t t' : Addr) (s : Storage) (src dst : Addr) (amt : Int) (a : Addr) :
    bal t (xfer t' s src dst amt) a
      = bal t s a + (if t = t' ∧ a = dst then amt else 0) - (if t = t' ∧ a = src then amt else 0) := by
  simp only [bal, xfer, Storage.set_get, Key.bal.injEq]
  by_cases h1 : a = dst <;> by_cases h2 : a = src <;> by_cases h3 : t = t' <;> simp_all <;> omega
/-- a transfer touches only balances. -/
@[simp] theorem xfer_other (t : Addr) (s : Storage) (src dst : Addr) (amt : Int) (k : Key)
    (h : ∀ t a, k ≠ .bal t a) : xfer t s src dst amt k = s k := by
  simp only [xfer, Storage.set_get]; simp [h]
/-- a write to a key that isn't a balance leaves every balance alone. -/
@[simp] theorem bal_set (t : Addr) (s : Storage) (k : Key) (v : Int) (a : Addr) (h : ∀ t a, k ≠ .bal t a) :
    bal t (s.set k v) a = bal t s a := by
  simp only [bal, Storage.set_get]; simp [Ne.symm (h t a)]

/-- SEP-41: a transfer succeeds only for a non-negative amount the sender holds. -/
abbrev xferOk (t : Addr) (s : Storage) (src _dst : Addr) (amt : Int) : Prop := 0 ≤ amt ∧ amt ≤ bal t s src
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

/-- `create(seller: Address, sell_token: Address, buy_token: Address, sell_price: u32, buy_price: u32)`: it succeeds exactly when `create.Spec` holds.
    Its effects, in execution order:
    * `create.s1`: write `Offer.buy_price` := `create.buy_price st`, `Offer.buy_token` := `create.buy_token st`, `Offer.sell_price` := `create.sell_price st`, `Offer.sell_token` := `create.sell_token st`, `Offer.seller` := `create.seller st`
-/
structure create.Spec (st : Step) : Prop where
  fn : st.call.fn = "create"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `create.seller st` authorized the call (`require_auth`) -/
  auth_seller : (create.seller st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (create.buy_price st) ≥ 1
  /-- the call panics unless this holds -/
  gate2 : (create.sell_price st) ≥ 1
  /-- the call panics unless this holds -/
  gate3 : (st.pre (.has Offer)) ≠ 1
  post : st.post = (create.s1 st)
  writes : st.writes = [Offer.buy_price, Offer.buy_token, Offer.sell_price, Offer.sell_token, Offer.seller, .has Offer]
  ret : st.ret = 2

abbrev create : Step → Prop := fun st => create.Spec st

/-- `get_offer()`: it succeeds exactly when `get_offer.Spec` holds.
-/
structure get_offer.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "get_offer"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (u.i 1)

def get_offer : Step → Prop := fun st => ∃ u : Unk, get_offer.Spec st u

namespace trade
@[simp] def buy_token_amount (st : Step) : Int := st.call.arg "buy_token_amount"
@[simp] def buyer (st : Step) : Addr := st.call.argA "buyer"
@[simp] def min_sell_token_amount (st : Step) : Int := st.call.arg "min_sell_token_amount"
@[simp] def amt1 (st : Step) : Int :=
  trade.buy_token_amount st
@[simp] def s1 (st : Step) : Storage :=
  xfer (st.pre Offer.buy_token) st.pre (trade.buyer st) (pool st) (trade.amt1 st)
@[simp] def amt2 (_st : Step) (u : Unk) : Int :=
  u.i 4
@[simp] def s2 (st : Step) (u : Unk) : Storage :=
  xfer (st.pre Offer.sell_token) (trade.s1 st) (pool st) (trade.buyer st) (trade.amt2 st u)
@[simp] def amt3 (st : Step) : Int :=
  trade.amt1 st
@[simp] def s3 (st : Step) (u : Unk) : Storage :=
  xfer (st.pre Offer.buy_token) (trade.s2 st u) (pool st) (st.pre Offer.seller) (trade.amt3 st)
end trade

/-- `trade(buyer: Address, buy_token_amount: i128, min_sell_token_amount: i128)`: it succeeds exactly when `trade.Spec` holds.
    Its effects, in execution order:
    * `trade.s1`: transfer `trade.amt1 st` of token `st.pre Offer.buy_token` from `trade.buyer st` to `pool st`
    * `trade.s2`: transfer `trade.amt2 st u` of token `st.pre Offer.sell_token` from `pool st` to `trade.buyer st`
    * `trade.s3`: transfer `trade.amt3 st` of token `st.pre Offer.buy_token` from `pool st` to `st.pre Offer.seller`
-/
structure trade.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "trade"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer1 : xferOk (st.pre Offer.buy_token) st.pre (trade.buyer st) (pool st) (trade.amt1 st)
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer2 : xferOk (st.pre Offer.sell_token) (trade.s1 st) (pool st) (trade.buyer st) (trade.amt2 st u)
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer3 : xferOk (st.pre Offer.buy_token) (trade.s2 st u) (pool st) (st.pre Offer.seller) (trade.amt3 st)
  /-- `trade.buyer st` authorized the call (`require_auth`) -/
  auth_buyer : (trade.buyer st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (trade.min_sell_token_amount st) ≤ (u.g 4)
  post : st.post = (trade.s3 st u)
  writes : st.writes = [.bal (st.pre Offer.buy_token) (trade.buyer st), .bal (st.pre Offer.buy_token) (pool st), .bal (st.pre Offer.sell_token) (pool st), .bal (st.pre Offer.sell_token) (trade.buyer st), .bal (st.pre Offer.buy_token) (st.pre Offer.seller)]
  ret : st.ret = 2

def trade : Step → Prop := fun st => ∃ u : Unk, trade.Spec st u

namespace updt_price
@[simp] def buy_price (st : Step) : Int := st.call.arg "buy_price"
@[simp] def sell_price (st : Step) : Int := st.call.arg "sell_price"
@[simp] def s1 (st : Step) : Storage :=
  ((((((st.pre).set Offer.buy_price (updt_price.buy_price st)).set Offer.buy_token (st.pre Offer.buy_token)).set Offer.sell_price (updt_price.sell_price st)).set Offer.sell_token (st.pre Offer.sell_token)).set Offer.seller (st.pre Offer.seller)).set (.has Offer) 1
end updt_price

/-- `updt_price(sell_price: u32, buy_price: u32)`: it succeeds exactly when `updt_price.Spec` holds.
    Its effects, in execution order:
    * `updt_price.s1`: write `Offer.buy_price` := `updt_price.buy_price st`, `Offer.buy_token` := `st.pre Offer.buy_token`, `Offer.sell_price` := `updt_price.sell_price st`, `Offer.sell_token` := `st.pre Offer.sell_token`, `Offer.seller` := `st.pre Offer.seller`
-/
structure updt_price.Spec (st : Step) : Prop where
  fn : st.call.fn = "updt_price"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `st.pre Offer.seller` authorized the call (`require_auth`) -/
  auth_Offer_seller : (st.pre Offer.seller) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (updt_price.sell_price st) ≥ 1
  /-- the call panics unless this holds -/
  gate2 : (updt_price.buy_price st) ≥ 1
  post : st.post = (updt_price.s1 st)
  writes : st.writes = [Offer.buy_price, Offer.buy_token, Offer.sell_price, Offer.sell_token, Offer.seller, .has Offer]
  ret : st.ret = 2

abbrev updt_price : Step → Prop := fun st => updt_price.Spec st

namespace withdraw
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def token (st : Step) : Addr := st.call.argA "token"
@[simp] def amt1 (st : Step) : Int :=
  withdraw.amount st
@[simp] def s1 (st : Step) : Storage :=
  xfer (withdraw.token st) st.pre (pool st) (st.pre Offer.seller) (withdraw.amt1 st)
end withdraw

/-- `withdraw(token: Address, amount: i128)`: it succeeds exactly when `withdraw.Spec` holds.
    Its effects, in execution order:
    * `withdraw.s1`: transfer `withdraw.amt1 st` of token `withdraw.token st` from `pool st` to `st.pre Offer.seller`
-/
structure withdraw.Spec (st : Step) : Prop where
  fn : st.call.fn = "withdraw"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer1 : xferOk (withdraw.token st) st.pre (pool st) (st.pre Offer.seller) (withdraw.amt1 st)
  /-- `st.pre Offer.seller` authorized the call (`require_auth`) -/
  auth_Offer_seller : (st.pre Offer.seller) ∈ st.call.signers
  post : st.post = (withdraw.s1 st)
  writes : st.writes = [.bal (withdraw.token st) (pool st), .bal (withdraw.token st) (st.pre Offer.seller)]
  ret : st.ret = 2

abbrev withdraw : Step → Prop := fun st => withdraw.Spec st

/-- the contract's entry points (each a `Step → Prop`; the constructor runs
    only at deployment, so it is not one of them). -/
def entries : List (Step → Prop) := [create, get_offer, trade, updt_price, withdraw]

/-- Keys in temporary storage: they can expire between calls. -/
def temporary : Key → Bool
  | .fld k _ => temporary k
  | .has k => temporary k
  | _ => false

/-- What the rest of the ledger can do between two calls of the contract at `me`.
    Any token balance can change: other people's transfers, mints, tokens sent
    straight to the contract. The exception is the contract's own balances,
    which can only grow, since lowering them needs its authorization. The
    contract's own storage is untouched (only the contract writes it), except
    that temporary entries can expire. -/
def Outside (me : Addr) (s s' : Storage) : Prop :=
  ∀ k : Key, match k with
    | .bal t a => a = me → s (.bal t a) ≤ s' (.bal t a)
    | k => temporary k = true ∨ s' k = s k

/-- A history of the contract at `me`, from storage `s` to `t`: its calls (each
    admitted by one of its entry points) interleaved with outside activity. -/
inductive Run (me : Addr) : Storage → Storage → Prop
  | refl (s : Storage) : Run me s s
  | call {s : Storage} (st : Step) : Run me s st.pre → st.call.self = me →
      (∃ e ∈ entries, e st) → Run me s st.post
  | outside {s t t' : Storage} : Run me s t → Outside me t t' → Run me s t'

end Contract
