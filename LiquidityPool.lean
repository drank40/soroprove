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

@[simp] def TokenA : Key := .var "TokenA"
@[simp] def TokenB : Key := .var "TokenB"
@[simp] def TotalShares : Key := .var "TotalShares"
@[simp] def ReserveA : Key := .var "ReserveA"
@[simp] def ReserveB : Key := .var "ReserveB"
@[simp] def Shares (k1 : Addr) : Key := .entry "Shares" k1

namespace __constructor
@[simp] def token_a (st : Step) : Addr := st.call.argA "token_a"
@[simp] def token_b (st : Step) : Addr := st.call.argA "token_b"
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set TokenA (__constructor.token_a st)).set (.has TokenA) 1
@[simp] def s2 (st : Step) : Storage :=
  ((__constructor.s1 st).set TokenB (__constructor.token_b st)).set (.has TokenB) 1
@[simp] def s3 (st : Step) : Storage :=
  ((__constructor.s2 st).set TotalShares 0).set (.has TotalShares) 1
@[simp] def s4 (st : Step) : Storage :=
  ((__constructor.s3 st).set ReserveA 0).set (.has ReserveA) 1
@[simp] def s5 (st : Step) : Storage :=
  ((__constructor.s4 st).set ReserveB 0).set (.has ReserveB) 1
end __constructor

/-- `__constructor(token_a: Address, token_b: Address)`: it succeeds exactly when `__constructor.Spec` holds.
    Its effects, in execution order:
    * `__constructor.s1`: write `TokenA` := `__constructor.token_a st`
    * `__constructor.s2`: write `TokenB` := `__constructor.token_b st`
    * `__constructor.s3`: write `TotalShares` := `0`
    * `__constructor.s4`: write `ReserveA` := `0`
    * `__constructor.s5`: write `ReserveB` := `0`
-/
structure __constructor.Spec (st : Step) : Prop where
  fn : st.call.fn = "__constructor"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the call panics unless this holds -/
  gate1 : (__constructor.token_a st) < (__constructor.token_b st)
  post : st.post = (__constructor.s5 st)
  writes : st.writes = [TokenA, .has TokenA, TokenB, .has TokenB, TotalShares, .has TotalShares, ReserveA, .has ReserveA, ReserveB, .has ReserveB]
  ret : st.ret = 2

abbrev __constructor : Step → Prop := fun st => __constructor.Spec st

namespace balance_shares
@[simp] def user (st : Step) : Addr := st.call.argA "user"
end balance_shares

/-- `balance_shares(user: Address)`: it succeeds exactly when `balance_shares.Spec` holds.
-/
structure balance_shares.Spec (st : Step) : Prop where
  fn : st.call.fn = "balance_shares"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (getOr0 st.pre (Shares (balance_shares.user st)))

abbrev balance_shares : Step → Prop := fun st => balance_shares.Spec st

namespace deposit
@[simp] def desired_a (st : Step) : Int := st.call.arg "desired_a"
@[simp] def desired_b (st : Step) : Int := st.call.arg "desired_b"
@[simp] def min_a (st : Step) : Int := st.call.arg "min_a"
@[simp] def min_b (st : Step) : Int := st.call.arg "min_b"
@[simp] def to (st : Step) : Addr := st.call.argA "to"
@[simp] def amt1 (st : Step) : Int :=
  if (¬(((st.pre ReserveA) = 0) ∧ ((st.pre ReserveB) = 0))) ∧ ((Int.tdiv ((deposit.desired_a st) * (st.pre ReserveB)) (st.pre ReserveA)) > (deposit.desired_b st)) then (Int.tdiv ((deposit.desired_b st) * (st.pre ReserveA)) (st.pre ReserveB)) else (deposit.desired_a st)
@[simp] def s1 (st : Step) : Storage :=
  xfer (st.pre TokenA) st.pre (deposit.to st) (pool st) (deposit.amt1 st)
@[simp] def amt2 (st : Step) : Int :=
  if (¬(((st.pre ReserveA) = 0) ∧ ((st.pre ReserveB) = 0))) ∧ ((Int.tdiv ((deposit.desired_a st) * (st.pre ReserveB)) (st.pre ReserveA)) > (deposit.desired_b st)) then (deposit.desired_b st) else (if ¬(((st.pre ReserveA) = 0) ∧ ((st.pre ReserveB) = 0)) then (Int.tdiv ((deposit.desired_a st) * (st.pre ReserveB)) (st.pre ReserveA)) else (deposit.desired_b st))
@[simp] def s2 (st : Step) : Storage :=
  xfer (st.pre TokenB) (deposit.s1 st) (deposit.to st) (pool st) (deposit.amt2 st)
@[simp] def new_Shares (st : Step) (u : Unk) : Int :=
  (getOr0 (deposit.s2 st) (Shares (deposit.to st))) + ((u.i 1) - ((deposit.s2 st) TotalShares))
@[simp] def s3 (st : Step) (u : Unk) : Storage :=
  ((deposit.s2 st).set (Shares (deposit.to st)) (deposit.new_Shares st u)).set (.has (Shares (deposit.to st))) 1
@[simp] def new_TotalShares (st : Step) (u : Unk) : Int :=
  ((deposit.s2 st) TotalShares) + ((u.i 2) - ((deposit.s2 st) TotalShares))
@[simp] def s4 (st : Step) (u : Unk) : Storage :=
  ((deposit.s3 st u).set TotalShares (deposit.new_TotalShares st u)).set (.has TotalShares) 1
@[simp] def new_ReserveA (st : Step) : Int :=
  bal (st.pre TokenA) (deposit.s2 st) (pool st)
@[simp] def s5 (st : Step) (u : Unk) : Storage :=
  ((deposit.s4 st u).set ReserveA (deposit.new_ReserveA st)).set (.has ReserveA) 1
@[simp] def new_ReserveB (st : Step) : Int :=
  bal (st.pre TokenB) (deposit.s2 st) (pool st)
@[simp] def s6 (st : Step) (u : Unk) : Storage :=
  ((deposit.s5 st u).set ReserveB (deposit.new_ReserveB st)).set (.has ReserveB) 1
end deposit

/-- `deposit(to: Address, desired_a: i128, min_a: i128, desired_b: i128, min_b: i128)`: it succeeds exactly when `deposit.Spec` holds.
    Its effects, in execution order:
    * `deposit.s1`: transfer `deposit.amt1 st` of token `st.pre TokenA` from `deposit.to st` to `pool st`
    * `deposit.s2`: transfer `deposit.amt2 st` of token `st.pre TokenB` from `deposit.to st` to `pool st`
    * `deposit.s3`: write `Shares (deposit.to st)` := `deposit.new_Shares st u`
    * `deposit.s4`: write `TotalShares` := `deposit.new_TotalShares st u`
    * `deposit.s5`: write `ReserveA` := `deposit.new_ReserveA st`
    * `deposit.s6`: write `ReserveB` := `deposit.new_ReserveB st`
-/
structure deposit.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "deposit"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer1 : xferOk (st.pre TokenA) st.pre (deposit.to st) (pool st) (deposit.amt1 st)
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer2 : xferOk (st.pre TokenB) (deposit.s1 st) (deposit.to st) (pool st) (deposit.amt2 st)
  /-- `deposit.to st` authorized the call (`require_auth`) -/
  auth_to : (deposit.to st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : ((¬(((st.pre ReserveA) = 0) ∧ ((st.pre ReserveB) = 0)) ∧ ¬((Int.tdiv ((deposit.desired_a st) * (st.pre ReserveB)) (st.pre ReserveA)) > (deposit.desired_b st))) → (Int.tdiv ((deposit.desired_a st) * (st.pre ReserveB)) (st.pre ReserveA)) ≥ (deposit.min_b st))
  /-- the call panics unless this holds -/
  gate2 : ((¬(((st.pre ReserveA) = 0) ∧ ((st.pre ReserveB) = 0)) ∧ (Int.tdiv ((deposit.desired_a st) * (st.pre ReserveB)) (st.pre ReserveA)) > (deposit.desired_b st)) → (deposit.desired_a st) ≥ (Int.tdiv ((deposit.desired_b st) * (st.pre ReserveA)) (st.pre ReserveB)))
  /-- the call panics unless this holds -/
  gate3 : ((¬(((st.pre ReserveA) = 0) ∧ ((st.pre ReserveB) = 0)) ∧ (Int.tdiv ((deposit.desired_a st) * (st.pre ReserveB)) (st.pre ReserveA)) > (deposit.desired_b st)) → (Int.tdiv ((deposit.desired_b st) * (st.pre ReserveA)) (st.pre ReserveB)) ≥ (deposit.min_a st))
  post : st.post = (deposit.s6 st u)
  writes : st.writes = [.bal (st.pre TokenA) (deposit.to st), .bal (st.pre TokenA) (pool st), .bal (st.pre TokenB) (deposit.to st), .bal (st.pre TokenB) (pool st), (Shares (deposit.to st)), .has (Shares (deposit.to st)), TotalShares, .has TotalShares, ReserveA, .has ReserveA, ReserveB, .has ReserveB]
  ret : st.ret = 2

def deposit : Step → Prop := fun st => ∃ u : Unk, deposit.Spec st u

/-- `get_rsrvs()`: it succeeds exactly when `get_rsrvs.Spec` holds.
-/
structure get_rsrvs.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "get_rsrvs"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (u.i 0)

def get_rsrvs : Step → Prop := fun st => ∃ u : Unk, get_rsrvs.Spec st u

namespace swap
@[simp] def buy_a (st : Step) : Int := st.call.arg "buy_a"
@[simp] def in_max (st : Step) : Int := st.call.arg "in_max"
@[simp] def out (st : Step) : Int := st.call.arg "out"
@[simp] def to (st : Step) : Addr := st.call.argA "to"
@[simp] def amt1 (st : Step) : Int :=
  (Int.tdiv (((if (swap.buy_a st) = 0 then (st.pre ReserveA) else (st.pre ReserveB)) * (swap.out st)) * 1000) (((if (swap.buy_a st) = 0 then (st.pre ReserveB) else (st.pre ReserveA)) - (swap.out st)) * 997)) + 1
@[simp] def s1 (st : Step) : Storage :=
  xfer (if (swap.buy_a st) ≠ 0 then (st.pre TokenB) else (st.pre TokenA)) st.pre (swap.to st) (pool st) (swap.amt1 st)
@[simp] def amt2 (st : Step) : Int :=
  swap.out st
@[simp] def s2 (st : Step) : Storage :=
  xfer (if (swap.buy_a st) = 0 then (st.pre TokenB) else (st.pre TokenA)) (swap.s1 st) (pool st) (swap.to st) (swap.amt2 st)
@[simp] def new_ReserveA (st : Step) : Int :=
  (bal (st.pre TokenA) (swap.s1 st) (pool st)) - (if (swap.buy_a st) ≠ 0 then (swap.amt2 st) else 0)
@[simp] def s3 (st : Step) : Storage :=
  ((swap.s2 st).set ReserveA (swap.new_ReserveA st)).set (.has ReserveA) 1
@[simp] def new_ReserveB (st : Step) : Int :=
  (bal (st.pre TokenB) (swap.s1 st) (pool st)) - (if (swap.buy_a st) ≠ 0 then 0 else (swap.amt2 st))
@[simp] def s4 (st : Step) : Storage :=
  ((swap.s3 st).set ReserveB (swap.new_ReserveB st)).set (.has ReserveB) 1
end swap

/-- `swap(to: Address, buy_a: bool, out: i128, in_max: i128)`: it succeeds exactly when `swap.Spec` holds.
    Its effects, in execution order:
    * `swap.s1`: transfer `swap.amt1 st` of token `if (swap.buy_a st) ≠ 0 then (st.pre TokenB) else (st.pre TokenA)` from `swap.to st` to `pool st`
    * `swap.s2`: transfer `swap.amt2 st` of token `if (swap.buy_a st) = 0 then (st.pre TokenB) else (st.pre TokenA)` from `pool st` to `swap.to st`
    * `swap.s3`: write `ReserveA` := `swap.new_ReserveA st`
    * `swap.s4`: write `ReserveB` := `swap.new_ReserveB st`
-/
structure swap.Spec (st : Step) : Prop where
  fn : st.call.fn = "swap"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer1 : xferOk (if (swap.buy_a st) ≠ 0 then (st.pre TokenB) else (st.pre TokenA)) st.pre (swap.to st) (pool st) (swap.amt1 st)
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer2 : xferOk (if (swap.buy_a st) = 0 then (st.pre TokenB) else (st.pre TokenA)) (swap.s1 st) (pool st) (swap.to st) (swap.amt2 st)
  /-- `swap.to st` authorized the call (`require_auth`) -/
  auth_to : (swap.to st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (if (swap.buy_a st) = 0 then (st.pre ReserveB) else (st.pre ReserveA)) ≥ (swap.amt2 st)
  /-- the call panics unless this holds -/
  gate2 : (swap.amt1 st) ≤ (swap.in_max st)
  /-- the call panics unless this holds -/
  gate3 : (((1000 * (st.pre ReserveA)) + (if (((bal (st.pre TokenA) (swap.s1 st) (pool st)) - (st.pre ReserveA)) - (if (swap.buy_a st) ≠ 0 then (swap.amt2 st) else 0)) > 0 then (997 * (((bal (st.pre TokenA) (swap.s1 st) (pool st)) - (st.pre ReserveA)) - (if (swap.buy_a st) ≠ 0 then (swap.amt2 st) else 0))) else (1000 * (((bal (st.pre TokenA) (swap.s1 st) (pool st)) - (st.pre ReserveA)) - (if (swap.buy_a st) ≠ 0 then (swap.amt2 st) else 0))))) * ((1000 * (st.pre ReserveB)) + (if (((bal (st.pre TokenB) (swap.s1 st) (pool st)) - (st.pre ReserveB)) - (if (swap.buy_a st) ≠ 0 then 0 else (swap.amt2 st))) > 0 then (997 * (((bal (st.pre TokenB) (swap.s1 st) (pool st)) - (st.pre ReserveB)) - (if (swap.buy_a st) ≠ 0 then 0 else (swap.amt2 st)))) else (1000 * (((bal (st.pre TokenB) (swap.s1 st) (pool st)) - (st.pre ReserveB)) - (if (swap.buy_a st) ≠ 0 then 0 else (swap.amt2 st))))))) ≥ (((st.pre ReserveA) * 1000) * ((st.pre ReserveB) * 1000))
  post : st.post = (swap.s4 st)
  writes : st.writes = [.bal (if (swap.buy_a st) ≠ 0 then (st.pre TokenB) else (st.pre TokenA)) (swap.to st), .bal (if (swap.buy_a st) ≠ 0 then (st.pre TokenB) else (st.pre TokenA)) (pool st), .bal (if (swap.buy_a st) = 0 then (st.pre TokenB) else (st.pre TokenA)) (pool st), .bal (if (swap.buy_a st) = 0 then (st.pre TokenB) else (st.pre TokenA)) (swap.to st), ReserveA, .has ReserveA, ReserveB, .has ReserveB]
  ret : st.ret = 2

abbrev swap : Step → Prop := fun st => swap.Spec st

namespace withdraw
@[simp] def min_a (st : Step) : Int := st.call.arg "min_a"
@[simp] def min_b (st : Step) : Int := st.call.arg "min_b"
@[simp] def share_amount (st : Step) : Int := st.call.arg "share_amount"
@[simp] def to (st : Step) : Addr := st.call.argA "to"
@[simp] def new_Shares (st : Step) : Int :=
  (getOr0 st.pre (Shares (withdraw.to st))) - (withdraw.share_amount st)
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set (Shares (withdraw.to st)) (withdraw.new_Shares st)).set (.has (Shares (withdraw.to st))) 1
@[simp] def new_TotalShares (st : Step) : Int :=
  (st.pre TotalShares) - (withdraw.share_amount st)
@[simp] def s2 (st : Step) : Storage :=
  ((withdraw.s1 st).set TotalShares (withdraw.new_TotalShares st)).set (.has TotalShares) 1
@[simp] def amt1 (st : Step) : Int :=
  Int.tdiv ((bal (st.pre TokenA) st.pre (pool st)) * (withdraw.share_amount st)) (st.pre TotalShares)
@[simp] def s3 (st : Step) : Storage :=
  xfer (st.pre TokenA) (withdraw.s2 st) (pool st) (withdraw.to st) (withdraw.amt1 st)
@[simp] def amt2 (st : Step) : Int :=
  Int.tdiv ((bal (st.pre TokenB) st.pre (pool st)) * (withdraw.share_amount st)) (st.pre TotalShares)
@[simp] def s4 (st : Step) : Storage :=
  xfer (st.pre TokenB) (withdraw.s3 st) (pool st) (withdraw.to st) (withdraw.amt2 st)
@[simp] def new_ReserveA (st : Step) : Int :=
  (bal (st.pre TokenA) st.pre (pool st)) - (withdraw.amt1 st)
@[simp] def s5 (st : Step) : Storage :=
  ((withdraw.s4 st).set ReserveA (withdraw.new_ReserveA st)).set (.has ReserveA) 1
@[simp] def new_ReserveB (st : Step) : Int :=
  (bal (st.pre TokenB) st.pre (pool st)) - (withdraw.amt2 st)
@[simp] def s6 (st : Step) : Storage :=
  ((withdraw.s5 st).set ReserveB (withdraw.new_ReserveB st)).set (.has ReserveB) 1
end withdraw

/-- `withdraw(to: Address, share_amount: i128, min_a: i128, min_b: i128)`: it succeeds exactly when `withdraw.Spec` holds.
    Its effects, in execution order:
    * `withdraw.s1`: write `Shares (withdraw.to st)` := `withdraw.new_Shares st`
    * `withdraw.s2`: write `TotalShares` := `withdraw.new_TotalShares st`
    * `withdraw.s3`: transfer `withdraw.amt1 st` of token `st.pre TokenA` from `pool st` to `withdraw.to st`
    * `withdraw.s4`: transfer `withdraw.amt2 st` of token `st.pre TokenB` from `pool st` to `withdraw.to st`
    * `withdraw.s5`: write `ReserveA` := `withdraw.new_ReserveA st`
    * `withdraw.s6`: write `ReserveB` := `withdraw.new_ReserveB st`
-/
structure withdraw.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "withdraw"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer1 : xferOk (st.pre TokenA) (withdraw.s2 st) (pool st) (withdraw.to st) (withdraw.amt1 st)
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer2 : xferOk (st.pre TokenB) (withdraw.s3 st) (pool st) (withdraw.to st) (withdraw.amt2 st)
  /-- `withdraw.to st` authorized the call (`require_auth`) -/
  auth_to : (withdraw.to st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (getOr0 st.pre (Shares (withdraw.to st))) ≥ (withdraw.share_amount st)
  /-- the call panics unless this holds -/
  gate2 : (withdraw.amt1 st) ≥ (withdraw.min_a st)
  /-- the call panics unless this holds -/
  gate3 : (withdraw.amt2 st) ≥ (withdraw.min_b st)
  post : st.post = (withdraw.s6 st)
  writes : st.writes = [(Shares (withdraw.to st)), .has (Shares (withdraw.to st)), TotalShares, .has TotalShares, .bal (st.pre TokenA) (pool st), .bal (st.pre TokenA) (withdraw.to st), .bal (st.pre TokenB) (pool st), .bal (st.pre TokenB) (withdraw.to st), ReserveA, .has ReserveA, ReserveB, .has ReserveB]
  ret : st.ret = (u.i 0)

def withdraw : Step → Prop := fun st => ∃ u : Unk, withdraw.Spec st u

/-- the contract's entry points (each a `Step → Prop`; the constructor runs
    only at deployment, so it is not one of them). -/
def entries : List (Step → Prop) := [balance_shares, deposit, get_rsrvs, swap, withdraw]

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
