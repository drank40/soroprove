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

/-- `__constructor(token_a: Address, token_b: Address)`
    effects, in execution order (states `__constructor.s1`, `__constructor.s2`, …):
      write storage.TokenA/1 := token_a
      write storage.TokenB/2 := token_b
      write storage.TotalShares/3 := 0
      write storage.ReserveA/4 := 0
      write storage.ReserveB/5 := 0
    conditions to succeed:
      gate: token_a < token_b
-/
def __constructor : Step → Prop := fun st =>
  st.call.fn = "__constructor" ∧
  st.call.caller ≠ pool st ∧
  (__constructor.token_a st) < (__constructor.token_b st) ∧   -- gate
  st.post = (__constructor.s5 st) ∧
  st.writes = [TokenA, .has TokenA, TokenB, .has TokenB, TotalShares, .has TotalShares, ReserveA, .has ReserveA, ReserveB, .has ReserveB] ∧
  st.ret = 2

namespace balance_shares
@[simp] def user (st : Step) : Addr := st.call.argA "user"
end balance_shares

/-- `balance_shares(user: Address)`
-/
def balance_shares : Step → Prop := fun st =>
  st.call.fn = "balance_shares" ∧
  st.call.caller ≠ pool st ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (getOr0 st.pre (Shares (balance_shares.user st)))

namespace deposit
@[simp] def desired_a (st : Step) : Int := st.call.arg "desired_a"
@[simp] def desired_b (st : Step) : Int := st.call.arg "desired_b"
@[simp] def min_a (st : Step) : Int := st.call.arg "min_a"
@[simp] def min_b (st : Step) : Int := st.call.arg "min_b"
@[simp] def to (st : Step) : Addr := st.call.argA "to"
@[simp] def amt1 (st : Step) : Int :=
  (if (¬(((st.pre ReserveA) = 0) ∧ ((st.pre ReserveB) = 0))) ∧ ((Int.tdiv ((deposit.desired_a st) * (st.pre ReserveB)) (st.pre ReserveA)) > (deposit.desired_b st)) then (Int.tdiv ((deposit.desired_b st) * (st.pre ReserveA)) (st.pre ReserveB)) else (deposit.desired_a st))
@[simp] def s1 (st : Step) : Storage :=
  xfer (st.pre TokenA) st.pre (deposit.to st) (pool st) (deposit.amt1 st)
@[simp] def amt2 (st : Step) : Int :=
  (if (¬(((st.pre ReserveA) = 0) ∧ ((st.pre ReserveB) = 0))) ∧ ((Int.tdiv ((deposit.desired_a st) * (st.pre ReserveB)) (st.pre ReserveA)) > (deposit.desired_b st)) then (deposit.desired_b st) else (if ¬(((st.pre ReserveA) = 0) ∧ ((st.pre ReserveB) = 0)) then (Int.tdiv ((deposit.desired_a st) * (st.pre ReserveB)) (st.pre ReserveA)) else (deposit.desired_b st)))
@[simp] def s2 (st : Step) : Storage :=
  xfer (st.pre TokenB) (deposit.s1 st) (deposit.to st) (pool st) (deposit.amt2 st)
@[simp] def s3 (st : Step) (u : Unk) : Storage :=
  ((deposit.s2 st).set (Shares (deposit.to st)) ((getOr0 (deposit.s2 st) (Shares (deposit.to st))) + ((u.i 1) - ((deposit.s2 st) TotalShares)))).set (.has (Shares (deposit.to st))) 1
@[simp] def s4 (st : Step) (u : Unk) : Storage :=
  ((deposit.s3 st u).set TotalShares (((deposit.s2 st) TotalShares) + ((u.i 2) - ((deposit.s2 st) TotalShares)))).set (.has TotalShares) 1
@[simp] def s5 (st : Step) (u : Unk) : Storage :=
  ((deposit.s4 st u).set ReserveA (bal (st.pre TokenA) (deposit.s2 st) (pool st))).set (.has ReserveA) 1
@[simp] def s6 (st : Step) (u : Unk) : Storage :=
  ((deposit.s5 st u).set ReserveB (bal (st.pre TokenB) (deposit.s2 st) (pool st))).set (.has ReserveB) 1
end deposit

/-- `deposit(to: Address, desired_a: i128, min_a: i128, desired_b: i128, min_b: i128)`
    effects, in execution order (states `deposit.s1`, `deposit.s2`, …; amounts `deposit.amt1`, …):
      transfer storage.TokenA/6: to -> @pool : Select(@and(@not(@and(ICmp_EQ(storage.ReserveA/14, 0), ICmp_EQ(storage.ReserveB/16, 0))), ICmp_SGT(((desired_a * storage.ReserveB/16) / storage.ReserveA/14), desired_b)), ((desired_b * storage.ReserveA/14) / storage.ReserveB/16), desired_a)
      transfer storage.TokenB/6: to -> @pool : Select(@and(@not(@and(ICmp_EQ(storage.ReserveA/14, 0), ICmp_EQ(storage.ReserveB/16, 0))), ICmp_SGT(((desired_a * storage.ReserveB/16) / storage.ReserveA/14), desired_b)), desired_b, Select(@not(@and(ICmp_EQ(storage.ReserveA/14, 0), ICmp_EQ(storage.ReserveB/16, 0))), ((desired_a * storage.ReserveB/16) / storage.ReserveA/14), desired_b))
      write @map:Shares(to, @at(20)) := (Select(@not(ICmp_EQ(@has(@map:Shares(to, @at(22))), 1)), 0, @map:Shares(to, @at(23))) + (big - storage.TotalShares/36))
      write storage.TotalShares/39 := (storage.TotalShares/41 + (big - storage.TotalShares/36))
      write storage.ReserveA/42 := @call:balance(storage.TokenA/6, @vec(@pool), @at(26))
      write storage.ReserveB/43 := @call:balance(storage.TokenB/6, @vec(@pool), @at(28))
    conditions to succeed:
      require_auth to
      gate: ((desired_a * storage.ReserveB/16) / storage.ReserveA/14) ≥ min_b   [when ¬(((st.pre (ReserveA)) = 0) ∧ ((st.pre (ReserveB)) = 0)) ∧ ¬((Int.tdiv ((deposit.desired_a st) * (st.pre (ReserveB))) (st.pre (ReserveA))) > (deposit.desired_b st))]
      gate: desired_a ≥ ((desired_b * storage.ReserveA/14) / storage.ReserveB/16)   [when ¬(((st.pre (ReserveA)) = 0) ∧ ((st.pre (ReserveB)) = 0)) ∧ (Int.tdiv ((deposit.desired_a st) * (st.pre (ReserveB))) (st.pre (ReserveA))) > (deposit.desired_b st)]
      gate: ((desired_b * storage.ReserveA/14) / storage.ReserveB/16) ≥ min_a   [when ¬(((st.pre (ReserveA)) = 0) ∧ ((st.pre (ReserveB)) = 0)) ∧ (Int.tdiv ((deposit.desired_a st) * (st.pre (ReserveB))) (st.pre (ReserveA))) > (deposit.desired_b st)]
-/
def deposit : Step → Prop := fun st => ∃ u : Unk,
  st.call.fn = "deposit" ∧
  st.call.caller ≠ pool st ∧
  (deposit.to st) ∈ st.call.signers ∧   -- require_auth to
  ((¬(((st.pre ReserveA) = 0) ∧ ((st.pre ReserveB) = 0)) ∧ ¬((Int.tdiv ((deposit.desired_a st) * (st.pre ReserveB)) (st.pre ReserveA)) > (deposit.desired_b st))) → (Int.tdiv ((deposit.desired_a st) * (st.pre ReserveB)) (st.pre ReserveA)) ≥ (deposit.min_b st)) ∧   -- gate
  ((¬(((st.pre ReserveA) = 0) ∧ ((st.pre ReserveB) = 0)) ∧ (Int.tdiv ((deposit.desired_a st) * (st.pre ReserveB)) (st.pre ReserveA)) > (deposit.desired_b st)) → (deposit.desired_a st) ≥ (Int.tdiv ((deposit.desired_b st) * (st.pre ReserveA)) (st.pre ReserveB))) ∧   -- gate
  ((¬(((st.pre ReserveA) = 0) ∧ ((st.pre ReserveB) = 0)) ∧ (Int.tdiv ((deposit.desired_a st) * (st.pre ReserveB)) (st.pre ReserveA)) > (deposit.desired_b st)) → (Int.tdiv ((deposit.desired_b st) * (st.pre ReserveA)) (st.pre ReserveB)) ≥ (deposit.min_a st)) ∧   -- gate
  st.post = (deposit.s6 st u) ∧
  st.writes = [.bal (st.pre TokenA) (deposit.to st), .bal (st.pre TokenA) (pool st), .bal (st.pre TokenB) (deposit.to st), .bal (st.pre TokenB) (pool st), (Shares (deposit.to st)), .has (Shares (deposit.to st)), TotalShares, .has TotalShares, ReserveA, .has ReserveA, ReserveB, .has ReserveB] ∧
  st.ret = 2

/-- `get_rsrvs()`
-/
def get_rsrvs : Step → Prop := fun st => ∃ u : Unk,
  st.call.fn = "get_rsrvs" ∧
  st.call.caller ≠ pool st ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (u.i 0)

namespace swap
@[simp] def buy_a (st : Step) : Int := st.call.arg "buy_a"
@[simp] def in_max (st : Step) : Int := st.call.arg "in_max"
@[simp] def out (st : Step) : Int := st.call.arg "out"
@[simp] def to (st : Step) : Addr := st.call.argA "to"
@[simp] def amt1 (st : Step) : Int :=
  ((Int.tdiv (((if (swap.buy_a st) = 0 then (st.pre ReserveA) else (st.pre ReserveB)) * (swap.out st)) * 1000) (((if (swap.buy_a st) = 0 then (st.pre ReserveB) else (st.pre ReserveA)) - (swap.out st)) * 997)) + 1)
@[simp] def s1 (st : Step) : Storage :=
  xfer (if ¬((swap.buy_a st) = 0) then (st.pre TokenB) else (st.pre TokenA)) st.pre (swap.to st) (pool st) (swap.amt1 st)
@[simp] def amt2 (st : Step) : Int :=
  (swap.out st)
@[simp] def s2 (st : Step) : Storage :=
  xfer (if (swap.buy_a st) = 0 then (st.pre TokenB) else (st.pre TokenA)) (swap.s1 st) (pool st) (swap.to st) (swap.amt2 st)
@[simp] def s3 (st : Step) : Storage :=
  ((swap.s2 st).set ReserveA ((bal (st.pre TokenA) (swap.s1 st) (pool st)) - (if ¬((swap.buy_a st) = 0) then (swap.out st) else 0))).set (.has ReserveA) 1
@[simp] def s4 (st : Step) : Storage :=
  ((swap.s3 st).set ReserveB ((bal (st.pre TokenB) (swap.s1 st) (pool st)) - (if ¬((swap.buy_a st) = 0) then 0 else (swap.out st)))).set (.has ReserveB) 1
end swap

/-- `swap(to: Address, buy_a: bool, out: i128, in_max: i128)`
    effects, in execution order (states `swap.s1`, `swap.s2`, …; amounts `swap.amt1`, …):
      transfer Select(@not(@isfalse(buy_a)), storage.TokenB/6, storage.TokenA/6): to -> @pool : ((((Select(@isfalse(buy_a), storage.ReserveA/59, storage.ReserveB/61) * out) * 1000) / ((Select(@isfalse(buy_a), storage.ReserveB/61, storage.ReserveA/59) - out) * 997)) + 1)
      transfer Select(@isfalse(buy_a), storage.TokenB/6, storage.TokenA/6): @pool -> to : out
      write storage.ReserveA/78 := (@call:balance(storage.TokenA/6, @vec(@pool), @at(72)) - Select(@not(@isfalse(buy_a)), out, 0))
      write storage.ReserveB/79 := (@call:balance(storage.TokenB/6, @vec(@pool), @at(76)) - Select(@not(@isfalse(buy_a)), 0, out))
    conditions to succeed:
      require_auth to
      gate: Select(@isfalse(buy_a), storage.ReserveB/61, storage.ReserveA/59) ≥ out
      gate: ((((Select(@isfalse(buy_a), storage.ReserveA/59, storage.ReserveB/61) * out) * 1000) / ((Select(@isfalse(buy_a), storage.ReserveB/61, storage.ReserveA/59) - out) * 997)) + 1) ≤ in_max
      gate: (((1000 * storage.ReserveA/59) + Select(@not(ICmp_SLE(((@call:balance(storage.TokenA/6, @vec(@pool), @at(72)) - storage.ReserveA/59) - Select(@not(@isfalse(buy_a)), out, 0)), 0)), (997 * ((@call:balance(storage.TokenA/6, @vec(@pool), @at(72)) - storage.ReserveA/59) - Select(@not(@isfalse(buy_a)), out, 0))), (1000 * ((@call:balance(storage.TokenA/6, @vec(@pool), @at(72)) - storage.ReserveA/59) - Select(@not(@isfalse(buy_a)), out, 0))))) * ((1000 * storage.ReserveB/61) + Select(@not(ICmp_SLE(((@call:balance(storage.TokenB/6, @vec(@pool), @at(76)) - storage.ReserveB/61) - Select(@not(@isfalse(buy_a)), 0, out)), 0)), (997 * ((@call:balance(storage.TokenB/6, @vec(@pool), @at(76)) - storage.ReserveB/61) - Select(@not(@isfalse(buy_a)), 0, out))), (1000 * ((@call:balance(storage.TokenB/6, @vec(@pool), @at(76)) - storage.ReserveB/61) - Select(@not(@isfalse(buy_a)), 0, out)))))) ≥ ((storage.ReserveA/59 * 1000) * (storage.ReserveB/61 * 1000))
-/
def swap : Step → Prop := fun st =>
  st.call.fn = "swap" ∧
  st.call.caller ≠ pool st ∧
  (swap.to st) ∈ st.call.signers ∧   -- require_auth to
  (if (swap.buy_a st) = 0 then (st.pre ReserveB) else (st.pre ReserveA)) ≥ (swap.out st) ∧   -- gate
  ((Int.tdiv (((if (swap.buy_a st) = 0 then (st.pre ReserveA) else (st.pre ReserveB)) * (swap.out st)) * 1000) (((if (swap.buy_a st) = 0 then (st.pre ReserveB) else (st.pre ReserveA)) - (swap.out st)) * 997)) + 1) ≤ (swap.in_max st) ∧   -- gate
  (((1000 * (st.pre ReserveA)) + (if ¬((((bal (st.pre TokenA) (swap.s1 st) (pool st)) - (st.pre ReserveA)) - (if ¬((swap.buy_a st) = 0) then (swap.out st) else 0)) ≤ 0) then (997 * (((bal (st.pre TokenA) (swap.s1 st) (pool st)) - (st.pre ReserveA)) - (if ¬((swap.buy_a st) = 0) then (swap.out st) else 0))) else (1000 * (((bal (st.pre TokenA) (swap.s1 st) (pool st)) - (st.pre ReserveA)) - (if ¬((swap.buy_a st) = 0) then (swap.out st) else 0))))) * ((1000 * (st.pre ReserveB)) + (if ¬((((bal (st.pre TokenB) (swap.s1 st) (pool st)) - (st.pre ReserveB)) - (if ¬((swap.buy_a st) = 0) then 0 else (swap.out st))) ≤ 0) then (997 * (((bal (st.pre TokenB) (swap.s1 st) (pool st)) - (st.pre ReserveB)) - (if ¬((swap.buy_a st) = 0) then 0 else (swap.out st)))) else (1000 * (((bal (st.pre TokenB) (swap.s1 st) (pool st)) - (st.pre ReserveB)) - (if ¬((swap.buy_a st) = 0) then 0 else (swap.out st))))))) ≥ (((st.pre ReserveA) * 1000) * ((st.pre ReserveB) * 1000)) ∧   -- gate
  st.post = (swap.s4 st) ∧
  st.writes = [.bal (if ¬((swap.buy_a st) = 0) then (st.pre TokenB) else (st.pre TokenA)) (swap.to st), .bal (if ¬((swap.buy_a st) = 0) then (st.pre TokenB) else (st.pre TokenA)) (pool st), .bal (if (swap.buy_a st) = 0 then (st.pre TokenB) else (st.pre TokenA)) (pool st), .bal (if (swap.buy_a st) = 0 then (st.pre TokenB) else (st.pre TokenA)) (swap.to st), ReserveA, .has ReserveA, ReserveB, .has ReserveB] ∧
  st.ret = 2

namespace withdraw
@[simp] def min_a (st : Step) : Int := st.call.arg "min_a"
@[simp] def min_b (st : Step) : Int := st.call.arg "min_b"
@[simp] def share_amount (st : Step) : Int := st.call.arg "share_amount"
@[simp] def to (st : Step) : Addr := st.call.argA "to"
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set (Shares (withdraw.to st)) ((getOr0 st.pre (Shares (withdraw.to st))) - (withdraw.share_amount st))).set (.has (Shares (withdraw.to st))) 1
@[simp] def s2 (st : Step) : Storage :=
  ((withdraw.s1 st).set TotalShares ((st.pre TotalShares) - (withdraw.share_amount st))).set (.has TotalShares) 1
@[simp] def amt1 (st : Step) : Int :=
  (Int.tdiv ((bal (st.pre TokenA) st.pre (pool st)) * (withdraw.share_amount st)) (st.pre TotalShares))
@[simp] def s3 (st : Step) : Storage :=
  xfer (st.pre TokenA) (withdraw.s2 st) (pool st) (withdraw.to st) (withdraw.amt1 st)
@[simp] def amt2 (st : Step) : Int :=
  (Int.tdiv ((bal (st.pre TokenB) st.pre (pool st)) * (withdraw.share_amount st)) (st.pre TotalShares))
@[simp] def s4 (st : Step) : Storage :=
  xfer (st.pre TokenB) (withdraw.s3 st) (pool st) (withdraw.to st) (withdraw.amt2 st)
@[simp] def s5 (st : Step) : Storage :=
  ((withdraw.s4 st).set ReserveA ((bal (st.pre TokenA) st.pre (pool st)) - (Int.tdiv ((bal (st.pre TokenA) st.pre (pool st)) * (withdraw.share_amount st)) (st.pre TotalShares)))).set (.has ReserveA) 1
@[simp] def s6 (st : Step) : Storage :=
  ((withdraw.s5 st).set ReserveB ((bal (st.pre TokenB) st.pre (pool st)) - (Int.tdiv ((bal (st.pre TokenB) st.pre (pool st)) * (withdraw.share_amount st)) (st.pre TotalShares)))).set (.has ReserveB) 1
end withdraw

/-- `withdraw(to: Address, share_amount: i128, min_a: i128, min_b: i128)`
    effects, in execution order (states `withdraw.s1`, `withdraw.s2`, …; amounts `withdraw.amt1`, …):
      write @map:Shares(to, @at(91)) := (Select(@not(ICmp_EQ(@has(@map:Shares(to, @at(92))), 1)), 0, @map:Shares(to, @at(93))) - share_amount)
      write storage.TotalShares/95 := (storage.TotalShares/97 - share_amount)
      transfer storage.TokenA/6: @pool -> to : ((@call:balance(storage.TokenA/6, @vec(@pool), @at(85)) * share_amount) / storage.TotalShares/88)
      transfer storage.TokenB/6: @pool -> to : ((@call:balance(storage.TokenB/6, @vec(@pool), @at(90)) * share_amount) / storage.TotalShares/88)
      write storage.ReserveA/98 := (@call:balance(storage.TokenA/6, @vec(@pool), @at(85)) - ((@call:balance(storage.TokenA/6, @vec(@pool), @at(85)) * share_amount) / storage.TotalShares/88))
      write storage.ReserveB/99 := (@call:balance(storage.TokenB/6, @vec(@pool), @at(90)) - ((@call:balance(storage.TokenB/6, @vec(@pool), @at(90)) * share_amount) / storage.TotalShares/88))
    conditions to succeed:
      require_auth to
      gate: Select(@not(ICmp_EQ(@has(@map:Shares(to, @at(106))), 1)), 0, @map:Shares(to, @at(107))) ≥ share_amount
      gate: ((@call:balance(storage.TokenA/6, @vec(@pool), @at(85)) * share_amount) / storage.TotalShares/88) ≥ min_a
      gate: ((@call:balance(storage.TokenB/6, @vec(@pool), @at(90)) * share_amount) / storage.TotalShares/88) ≥ min_b
      gate: Select(@not(ICmp_EQ(@has(@map:Shares(to, @at(92))), 1)), 0, @map:Shares(to, @at(93))) ≥ share_amount
-/
def withdraw : Step → Prop := fun st => ∃ u : Unk,
  st.call.fn = "withdraw" ∧
  st.call.caller ≠ pool st ∧
  (withdraw.to st) ∈ st.call.signers ∧   -- require_auth to
  (getOr0 st.pre (Shares (withdraw.to st))) ≥ (withdraw.share_amount st) ∧   -- gate
  (Int.tdiv ((bal (st.pre TokenA) st.pre (pool st)) * (withdraw.share_amount st)) (st.pre TotalShares)) ≥ (withdraw.min_a st) ∧   -- gate
  (Int.tdiv ((bal (st.pre TokenB) st.pre (pool st)) * (withdraw.share_amount st)) (st.pre TotalShares)) ≥ (withdraw.min_b st) ∧   -- gate
  st.post = (withdraw.s6 st) ∧
  st.writes = [(Shares (withdraw.to st)), .has (Shares (withdraw.to st)), TotalShares, .has TotalShares, .bal (st.pre TokenA) (pool st), .bal (st.pre TokenA) (withdraw.to st), .bal (st.pre TokenB) (pool st), .bal (st.pre TokenB) (withdraw.to st), ReserveA, .has ReserveA, ReserveB, .has ReserveB] ∧
  st.ret = (u.i 0)

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [__constructor, balance_shares, deposit, get_rsrvs, swap, withdraw]

end Contract
