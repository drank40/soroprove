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
-- `.elem m k` (entry k of the host `Map` stored at m), `.has k` (k's presence:
-- set → 1, remove → 0), `.bal t a` (token t's balance of a). Struct arguments'
-- fields are args named like `config.limit`.
--
-- Assumes: tokens the contract calls `transfer` / `transfer_from` / `approve` /
-- `balance` on behave per SEP-41; addresses are encoded as `Addr` in the host's
-- order (`obj_cmp`).

namespace Contract

abbrev Addr := Int

inductive Key where
  | var   (name : String)
  | entry (map : String) (k : Addr)
  | tup   (map : String) (ks : List Int)
  | fld   (base : Key) (f : String)
  | elem  (map : Key) (k : Int)
  | has   (k : Key)
  | bal   (t : Addr) (a : Addr)
  deriving DecidableEq, Inhabited, Repr

abbrev Storage := Key → Int
def Storage.set (s : Storage) (k : Key) (v : Int) : Storage := fun k' => if k' = k then v else s k'
/-- `k` is `m` or a part of the value stored at `m` (a field, a map entry, presence). -/
def Key.under (m : Key) : Key → Bool
  | .fld b f => .fld b f == m || Key.under m b
  | .elem b k => .elem b k == m || Key.under m b
  | .has b => .has b == m || Key.under m b
  | k => k == m
/-- storage after an opaque write to `m`: everything stored under `m` takes `h`'s values. -/
def Storage.setUnder (s : Storage) (m : Key) (h : Storage) : Storage := fun k => if Key.under m k then h k else s k

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

@[simp] def TotalShares : Key := .var "TotalShares"
@[simp] def Balance (k1 : Addr) : Key := .entry "Balance" k1
@[simp] def SwapFee : Key := .var "SwapFee"
@[simp] def AllRecordData : Key := .var "AllRecordData"
@[simp] def AllTokenVec : Key := .var "AllTokenVec"
@[simp] def METADATA : Key := .var "METADATA"
@[simp] def METADATA.decimal : Key := .fld METADATA "decimal"
@[simp] def METADATA.name : Key := .fld METADATA "name"
@[simp] def METADATA.symbol : Key := .fld METADATA "symbol"
@[simp] def Controller : Key := .var "Controller"
@[simp] def AllRecordData.get (k1 : Int) : Key := .elem AllRecordData k1
@[simp] def AllRecordData.balance (k1 : Int) : Key := .fld (AllRecordData.get k1) "balance"
@[simp] def AllRecordData.index (k1 : Int) : Key := .fld (AllRecordData.get k1) "index"
@[simp] def AllRecordData.scalar (k1 : Int) : Key := .fld (AllRecordData.get k1) "scalar"
@[simp] def AllRecordData.weight (k1 : Int) : Key := .fld (AllRecordData.get k1) "weight"
@[simp] def Allowance (k1 : Int) (k2 : Int) : Key := .tup "Allowance" [k1, k2]
@[simp] def Allowance.expiration_ledger (k1 : Int) (k2 : Int) : Key := .fld (Allowance k1 k2) "expiration_ledger"
@[simp] def Allowance.amount (k1 : Int) (k2 : Int) : Key := .fld (Allowance k1 k2) "amount"

namespace init
@[simp] def controller (st : Step) : Addr := st.call.argA "controller"
@[simp] def swap_fee (st : Step) : Int := st.call.arg "swap_fee"
@[simp] def tokens (st : Step) : Int := st.call.arg "tokens"
@[simp] def tokens.len (st : Step) : Int := st.call.arg "tokens.len"
@[simp] def s1 (st : Step) (u : Unk) : Storage :=
  if (u.b 1) = true then (u.s 2) else st.pre
@[simp] def new_TotalShares (st : Step) (u : Unk) : Int :=
  (getOr0 (init.s1 st u) TotalShares) + 1000000000
@[simp] def s2 (st : Step) (u : Unk) : Storage :=
  ((init.s1 st u).set TotalShares (init.new_TotalShares st u)).set (.has TotalShares) 1
@[simp] def new_Balance (st : Step) (u : Unk) : Int :=
  (getOr0 (init.s2 st u) (Balance (init.controller st))) + 1000000000
@[simp] def s3 (st : Step) (u : Unk) : Storage :=
  ((init.s2 st u).set (Balance (init.controller st)) (init.new_Balance st u)).set (.has (Balance (init.controller st))) 1
@[simp] def s4 (st : Step) (u : Unk) : Storage :=
  ((init.s3 st u).set SwapFee (init.swap_fee st)).set (.has SwapFee) 1
@[simp] def new_AllRecordData (st : Step) (u : Unk) : Int :=
  if (init.tokens.len st) < 1 then (u.i 3) else (u.i 4)
@[simp] def s5 (st : Step) (u : Unk) : Storage :=
  ((init.s4 st u).set AllRecordData (init.new_AllRecordData st u)).set (.has AllRecordData) 1
@[simp] def s6 (st : Step) (u : Unk) : Storage :=
  ((init.s5 st u).set AllTokenVec (init.tokens st)).set (.has AllTokenVec) 1
@[simp] def s7 (st : Step) (u : Unk) : Storage :=
  ((((init.s6 st u).set METADATA.decimal 7).set METADATA.name (u.i 5)).set METADATA.symbol (u.i 6)).set (.has METADATA) 1
@[simp] def s8 (st : Step) (u : Unk) : Storage :=
  ((init.s7 st u).set Controller (init.controller st)).set (.has Controller) 1
end init

/-- `init(controller: Address, tokens: Vec<Address>, weights: Vec<i128>, balances: Vec<i128>, swap_fee: i128)`: it succeeds exactly when `init.Spec` holds.
    Its effects, in execution order:
    * `init.s1`: an effect the model doesn't interpret (in a loop, or too deep): all storage open, when `(u.b 1) = true`
    * `init.s2`: write `TotalShares` := `init.new_TotalShares st u`
    * `init.s3`: write `Balance (init.controller st)` := `init.new_Balance st u`
    * `init.s4`: write `SwapFee` := `init.swap_fee st`
    * `init.s5`: write `AllRecordData` := `init.new_AllRecordData st u`
    * `init.s6`: write `AllTokenVec` := `init.tokens st`
    * `init.s7`: write `METADATA.decimal` := `7`, `METADATA.name` := `u.i 5`, `METADATA.symbol` := `u.i 6`
    * `init.s8`: write `Controller` := `init.controller st`
-/
structure init.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "init"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `init.controller st` authorized the call (`require_auth`) -/
  auth_controller : (init.controller st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (u.g 1) ≠ 1
  /-- the call panics unless this holds -/
  gate2 : (init.tokens.len st) ≥ 2
  /-- the call panics unless this holds -/
  gate3 : (init.tokens.len st) < 1
  /-- the call panics unless this holds -/
  gate4 : (u.g 2) < 4294967296
  /-- the call panics unless this holds -/
  gate5 : ((init.swap_fee st) + -1000001) ≥ -999991
  /-- the call panics unless this holds -/
  gate6 : (u.g 3) < 4294967296
  post : st.post = (init.s8 st u)
  writes : st.writes = [TotalShares, .has TotalShares, (Balance (init.controller st)), .has (Balance (init.controller st)), SwapFee, .has SwapFee, AllRecordData, .has AllRecordData, AllTokenVec, .has AllTokenVec, METADATA.decimal, METADATA.name, METADATA.symbol, .has METADATA, Controller, .has Controller]
  ret : st.ret = 2

def init : Step → Prop := fun st => ∃ u : Unk, init.Spec st u

namespace gulp
@[simp] def t (st : Step) : Addr := st.call.argA "t"
@[simp] def new_AllRecordData_index (st : Step) : Int :=
  st.pre (AllRecordData.index (gulp.t st))
@[simp] def new_AllRecordData_scalar (st : Step) : Int :=
  st.pre (AllRecordData.scalar (gulp.t st))
@[simp] def new_AllRecordData_weight (st : Step) : Int :=
  st.pre (AllRecordData.weight (gulp.t st))
@[simp] def s1 (st : Step) (u : Unk) : Storage :=
  ((((((st.pre).set (AllRecordData.balance (gulp.t st)) (u.i 1)).set (AllRecordData.index (gulp.t st)) (gulp.new_AllRecordData_index st)).set (AllRecordData.scalar (gulp.t st)) (gulp.new_AllRecordData_scalar st)).set (AllRecordData.weight (gulp.t st)) (gulp.new_AllRecordData_weight st)).set (.has (AllRecordData.get (gulp.t st))) 1).set (.has AllRecordData) 1
end gulp

/-- `gulp(t: Address)`: it succeeds exactly when `gulp.Spec` holds.
    Its effects, in execution order:
    * `gulp.s1`: write `AllRecordData.balance (gulp.t st)` := `u.i 1`, `AllRecordData.index (gulp.t st)` := `gulp.new_AllRecordData_index st`, `AllRecordData.scalar (gulp.t st)` := `gulp.new_AllRecordData_scalar st`, `AllRecordData.weight (gulp.t st)` := `gulp.new_AllRecordData_weight st`
-/
structure gulp.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "gulp"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the call panics unless this holds -/
  gate1 : (st.pre (.has (AllRecordData.get (gulp.t st)))) = 1
  post : st.post = (gulp.s1 st u)
  writes : st.writes = [(AllRecordData.balance (gulp.t st)), (AllRecordData.index (gulp.t st)), (AllRecordData.scalar (gulp.t st)), (AllRecordData.weight (gulp.t st)), .has (AllRecordData.get (gulp.t st)), .has AllRecordData]
  ret : st.ret = 2

def gulp : Step → Prop := fun st => ∃ u : Unk, gulp.Spec st u

namespace join_pool
@[simp] def pool_amount_out (st : Step) : Int := st.call.arg "pool_amount_out"
@[simp] def user (st : Step) : Addr := st.call.argA "user"
@[simp] def s1 (st : Step) (u : Unk) : Storage :=
  if (u.b 1) = true then (u.s 2) else st.pre
@[simp] def new_AllRecordData (st : Step) (u : Unk) : Int :=
  if (u.i 3) < 1 then (st.pre AllRecordData) else (u.i 4)
@[simp] def s2 (st : Step) (u : Unk) : Storage :=
  ((join_pool.s1 st u).set AllRecordData (join_pool.new_AllRecordData st u)).set (.has AllRecordData) 1
@[simp] def new_TotalShares (st : Step) (u : Unk) : Int :=
  (getOr0 (join_pool.s2 st u) TotalShares) + (join_pool.pool_amount_out st)
@[simp] def s3 (st : Step) (u : Unk) : Storage :=
  ((join_pool.s2 st u).set TotalShares (join_pool.new_TotalShares st u)).set (.has TotalShares) 1
@[simp] def new_Balance (st : Step) (u : Unk) : Int :=
  (getOr0 (join_pool.s3 st u) (Balance (join_pool.user st))) + (join_pool.pool_amount_out st)
@[simp] def s4 (st : Step) (u : Unk) : Storage :=
  ((join_pool.s3 st u).set (Balance (join_pool.user st)) (join_pool.new_Balance st u)).set (.has (Balance (join_pool.user st))) 1
end join_pool

/-- `join_pool(pool_amount_out: i128, max_amounts_in: Vec<i128>, user: Address)`: it succeeds exactly when `join_pool.Spec` holds.
    Its effects, in execution order:
    * `join_pool.s1`: an effect the model doesn't interpret (in a loop, or too deep): all storage open, when `(u.b 1) = true`
    * `join_pool.s2`: write `AllRecordData` := `join_pool.new_AllRecordData st u`
    * `join_pool.s3`: write `TotalShares` := `join_pool.new_TotalShares st u`
    * `join_pool.s4`: write `Balance (join_pool.user st)` := `join_pool.new_Balance st u`
-/
structure join_pool.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "join_pool"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `join_pool.user st` authorized the call (`require_auth`) -/
  auth_user : (join_pool.user st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : ¬(if (join_pool.pool_amount_out st) = 0 then (join_pool.pool_amount_out st) = 0 else (join_pool.pool_amount_out st) < 1)
  post : st.post = (join_pool.s4 st u)
  writes : st.writes = [AllRecordData, .has AllRecordData, TotalShares, .has TotalShares, (Balance (join_pool.user st)), .has (Balance (join_pool.user st))]
  ret : st.ret = 2

def join_pool : Step → Prop := fun st => ∃ u : Unk, join_pool.Spec st u

namespace exit_pool
@[simp] def pool_amount_in (st : Step) : Int := st.call.arg "pool_amount_in"
@[simp] def user (st : Step) : Addr := st.call.argA "user"
@[simp] def new_Balance (st : Step) : Int :=
  (getOr0 st.pre (Balance (exit_pool.user st))) - (exit_pool.pool_amount_in st)
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set (Balance (exit_pool.user st)) (exit_pool.new_Balance st)).set (.has (Balance (exit_pool.user st))) 1
@[simp] def new_Balance_2 (st : Step) : Int :=
  (getOr0 (exit_pool.s1 st) (Balance (pool st))) + (exit_pool.pool_amount_in st)
@[simp] def s2 (st : Step) : Storage :=
  ((exit_pool.s1 st).set (Balance (pool st)) (exit_pool.new_Balance_2 st)).set (.has (Balance (pool st))) 1
@[simp] def new_Balance_3 (st : Step) : Int :=
  (getOr0 (exit_pool.s2 st) (Balance (pool st))) - (exit_pool.pool_amount_in st)
@[simp] def s3 (st : Step) : Storage :=
  ((exit_pool.s2 st).set (Balance (pool st)) (exit_pool.new_Balance_3 st)).set (.has (Balance (pool st))) 1
@[simp] def new_TotalShares (st : Step) : Int :=
  (getOr0 (exit_pool.s2 st) TotalShares) - (exit_pool.pool_amount_in st)
@[simp] def s4 (st : Step) : Storage :=
  ((exit_pool.s3 st).set TotalShares (exit_pool.new_TotalShares st)).set (.has TotalShares) 1
@[simp] def s5 (st : Step) (u : Unk) : Storage :=
  if (u.b 1) = true then (u.s 2) else (exit_pool.s4 st)
@[simp] def new_AllRecordData (st : Step) (u : Unk) : Int :=
  if (u.i 3) < 1 then (st.pre AllRecordData) else (u.i 4)
@[simp] def s6 (st : Step) (u : Unk) : Storage :=
  ((exit_pool.s5 st u).set AllRecordData (exit_pool.new_AllRecordData st u)).set (.has AllRecordData) 1
end exit_pool

/-- `exit_pool(pool_amount_in: i128, min_amounts_out: Vec<i128>, user: Address)`: it succeeds exactly when `exit_pool.Spec` holds.
    Its effects, in execution order:
    * `exit_pool.s1`: write `Balance (exit_pool.user st)` := `exit_pool.new_Balance st`
    * `exit_pool.s2`: write `Balance (pool st)` := `exit_pool.new_Balance_2 st`
    * `exit_pool.s3`: write `Balance (pool st)` := `exit_pool.new_Balance_3 st`
    * `exit_pool.s4`: write `TotalShares` := `exit_pool.new_TotalShares st`
    * `exit_pool.s5`: an effect the model doesn't interpret (in a loop, or too deep): all storage open, when `(u.b 1) = true`
    * `exit_pool.s6`: write `AllRecordData` := `exit_pool.new_AllRecordData st u`
-/
structure exit_pool.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "exit_pool"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `exit_pool.user st` authorized the call (`require_auth`) -/
  auth_user : (exit_pool.user st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : ¬(if (exit_pool.pool_amount_in st) = 0 then (exit_pool.pool_amount_in st) = 0 else (exit_pool.pool_amount_in st) < 1)
  post : st.post = (exit_pool.s6 st u)
  writes : st.writes = [(Balance (exit_pool.user st)), .has (Balance (exit_pool.user st)), (Balance (pool st)), .has (Balance (pool st)), TotalShares, .has TotalShares, AllRecordData, .has AllRecordData]
  ret : st.ret = 2

def exit_pool : Step → Prop := fun st => ∃ u : Unk, exit_pool.Spec st u

namespace swap_exact_amount_in
@[simp] def max_price (st : Step) : Int := st.call.arg "max_price"
@[simp] def min_amount_out (st : Step) : Int := st.call.arg "min_amount_out"
@[simp] def token_amount_in (st : Step) : Int := st.call.arg "token_amount_in"
@[simp] def token_in (st : Step) : Addr := st.call.argA "token_in"
@[simp] def token_out (st : Step) : Addr := st.call.argA "token_out"
@[simp] def user (st : Step) : Addr := st.call.argA "user"
@[simp] def amt1 (st : Step) : Int :=
  swap_exact_amount_in.token_amount_in st
@[simp] def s1 (st : Step) : Storage :=
  xfer (swap_exact_amount_in.token_in st) st.pre (swap_exact_amount_in.user st) (pool st) (swap_exact_amount_in.amt1 st)
@[simp] def amt2 (_st : Step) (u : Unk) : Int :=
  u.i 1
@[simp] def s2 (st : Step) (u : Unk) : Storage :=
  xfer (swap_exact_amount_in.token_out st) (swap_exact_amount_in.s1 st) (pool st) (swap_exact_amount_in.user st) (swap_exact_amount_in.amt2 st u)
@[simp] def key_AllRecordData_balance (st : Step) : Key :=
  AllRecordData.balance (swap_exact_amount_in.token_out st)
@[simp] def new_AllRecordData_balance (st : Step) : Int :=
  (st.pre (AllRecordData.balance (swap_exact_amount_in.token_in st))) + (swap_exact_amount_in.amt1 st)
@[simp] def new_AllRecordData_index (st : Step) : Int :=
  st.pre (AllRecordData.index (swap_exact_amount_in.token_in st))
@[simp] def new_AllRecordData_scalar (st : Step) : Int :=
  st.pre (AllRecordData.scalar (swap_exact_amount_in.token_in st))
@[simp] def new_AllRecordData_weight (st : Step) : Int :=
  st.pre (AllRecordData.weight (swap_exact_amount_in.token_in st))
@[simp] def new_AllRecordData_balance_2 (st : Step) (u : Unk) : Int :=
  (st.pre (swap_exact_amount_in.key_AllRecordData_balance st)) - (u.i 2)
@[simp] def new_AllRecordData_index_2 (st : Step) : Int :=
  st.pre (AllRecordData.index (swap_exact_amount_in.token_out st))
@[simp] def new_AllRecordData_scalar_2 (st : Step) : Int :=
  st.pre (AllRecordData.scalar (swap_exact_amount_in.token_out st))
@[simp] def new_AllRecordData_weight_2 (st : Step) : Int :=
  st.pre (AllRecordData.weight (swap_exact_amount_in.token_out st))
@[simp] def s3 (st : Step) (u : Unk) : Storage :=
  (((((((((((swap_exact_amount_in.s2 st u).set (AllRecordData.balance (swap_exact_amount_in.token_in st)) (swap_exact_amount_in.new_AllRecordData_balance st)).set (AllRecordData.index (swap_exact_amount_in.token_in st)) (swap_exact_amount_in.new_AllRecordData_index st)).set (AllRecordData.scalar (swap_exact_amount_in.token_in st)) (swap_exact_amount_in.new_AllRecordData_scalar st)).set (AllRecordData.weight (swap_exact_amount_in.token_in st)) (swap_exact_amount_in.new_AllRecordData_weight st)).set (.has (AllRecordData.get (swap_exact_amount_in.token_in st))) 1).set (swap_exact_amount_in.key_AllRecordData_balance st) (swap_exact_amount_in.new_AllRecordData_balance_2 st u)).set (AllRecordData.index (swap_exact_amount_in.token_out st)) (swap_exact_amount_in.new_AllRecordData_index_2 st)).set (AllRecordData.scalar (swap_exact_amount_in.token_out st)) (swap_exact_amount_in.new_AllRecordData_scalar_2 st)).set (AllRecordData.weight (swap_exact_amount_in.token_out st)) (swap_exact_amount_in.new_AllRecordData_weight_2 st)).set (.has (AllRecordData.get (swap_exact_amount_in.token_out st))) 1).set (.has AllRecordData) 1
end swap_exact_amount_in

/-- `swap_exact_amount_in(token_in: Address, token_amount_in: i128, token_out: Address, min_amount_out: i128, max_price: i128, user: Address)`: it succeeds exactly when `swap_exact_amount_in.Spec` holds.
    Its effects, in execution order:
    * `swap_exact_amount_in.s1`: transfer `swap_exact_amount_in.amt1 st` of token `swap_exact_amount_in.token_in st` from `swap_exact_amount_in.user st` to `pool st`
    * `swap_exact_amount_in.s2`: transfer `swap_exact_amount_in.amt2 st u` of token `swap_exact_amount_in.token_out st` from `pool st` to `swap_exact_amount_in.user st`
    * `swap_exact_amount_in.s3`: write `AllRecordData.balance (swap_exact_amount_in.token_in st)` := `swap_exact_amount_in.new_AllRecordData_balance st`, `AllRecordData.index (swap_exact_amount_in.token_in st)` := `swap_exact_amount_in.new_AllRecordData_index st`, `AllRecordData.scalar (swap_exact_amount_in.token_in st)` := `swap_exact_amount_in.new_AllRecordData_scalar st`, `AllRecordData.weight (swap_exact_amount_in.token_in st)` := `swap_exact_amount_in.new_AllRecordData_weight st`, `swap_exact_amount_in.key_AllRecordData_balance st` := `swap_exact_amount_in.new_AllRecordData_balance_2 st u`, `AllRecordData.index (swap_exact_amount_in.token_out st)` := `swap_exact_amount_in.new_AllRecordData_index_2 st`, `AllRecordData.scalar (swap_exact_amount_in.token_out st)` := `swap_exact_amount_in.new_AllRecordData_scalar_2 st`, `AllRecordData.weight (swap_exact_amount_in.token_out st)` := `swap_exact_amount_in.new_AllRecordData_weight_2 st`
-/
structure swap_exact_amount_in.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "swap_exact_amount_in"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer1 : xferOk (swap_exact_amount_in.token_in st) st.pre (swap_exact_amount_in.user st) (pool st) (swap_exact_amount_in.amt1 st)
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer2 : xferOk (swap_exact_amount_in.token_out st) (swap_exact_amount_in.s1 st) (pool st) (swap_exact_amount_in.user st) (swap_exact_amount_in.amt2 st u)
  /-- `swap_exact_amount_in.user st` authorized the call (`require_auth`) -/
  auth_user : (swap_exact_amount_in.user st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : ¬(if (swap_exact_amount_in.amt1 st) = 0 then (swap_exact_amount_in.amt1 st) = 0 else (swap_exact_amount_in.amt1 st) < 1)
  /-- the call panics unless this holds -/
  gate2 : (swap_exact_amount_in.min_amount_out st) ≥ 0
  /-- the call panics unless this holds -/
  gate3 : (if (u.g 1) = 69 then (swap_exact_amount_in.max_price st) else (u.g 2)) ≥ 0
  /-- the call panics unless this holds -/
  gate4 : (st.pre (.has (AllRecordData.get (swap_exact_amount_in.token_in st)))) = 1
  /-- the call panics unless this holds -/
  gate5 : (st.pre (.has (AllRecordData.get (swap_exact_amount_in.token_out st)))) = 1
  /-- the call panics unless this holds -/
  gate6 : (u.g 3) ≥ (swap_exact_amount_in.amt1 st)
  post : st.post = (swap_exact_amount_in.s3 st u)
  writes : st.writes = [.bal (swap_exact_amount_in.token_in st) (swap_exact_amount_in.user st), .bal (swap_exact_amount_in.token_in st) (pool st), .bal (swap_exact_amount_in.token_out st) (pool st), .bal (swap_exact_amount_in.token_out st) (swap_exact_amount_in.user st), (AllRecordData.balance (swap_exact_amount_in.token_in st)), (AllRecordData.index (swap_exact_amount_in.token_in st)), (AllRecordData.scalar (swap_exact_amount_in.token_in st)), (AllRecordData.weight (swap_exact_amount_in.token_in st)), .has (AllRecordData.get (swap_exact_amount_in.token_in st)), (swap_exact_amount_in.key_AllRecordData_balance st), (AllRecordData.index (swap_exact_amount_in.token_out st)), (AllRecordData.scalar (swap_exact_amount_in.token_out st)), (AllRecordData.weight (swap_exact_amount_in.token_out st)), .has (AllRecordData.get (swap_exact_amount_in.token_out st)), .has AllRecordData]
  ret : st.ret = (u.i 0)

def swap_exact_amount_in : Step → Prop := fun st => ∃ u : Unk, swap_exact_amount_in.Spec st u

namespace swap_exact_amount_out
@[simp] def max_amount_in (st : Step) : Int := st.call.arg "max_amount_in"
@[simp] def max_price (st : Step) : Int := st.call.arg "max_price"
@[simp] def token_amount_out (st : Step) : Int := st.call.arg "token_amount_out"
@[simp] def token_in (st : Step) : Addr := st.call.argA "token_in"
@[simp] def token_out (st : Step) : Addr := st.call.argA "token_out"
@[simp] def user (st : Step) : Addr := st.call.argA "user"
@[simp] def pre_AllRecordData_balance (st : Step) : Int :=
  st.pre (AllRecordData.balance (swap_exact_amount_out.token_out st))
@[simp] def amt1 (_st : Step) (u : Unk) : Int :=
  u.i 1
@[simp] def s1 (st : Step) (u : Unk) : Storage :=
  xfer (swap_exact_amount_out.token_in st) st.pre (swap_exact_amount_out.user st) (pool st) (swap_exact_amount_out.amt1 st u)
@[simp] def amt2 (st : Step) : Int :=
  swap_exact_amount_out.token_amount_out st
@[simp] def s2 (st : Step) (u : Unk) : Storage :=
  xfer (swap_exact_amount_out.token_out st) (swap_exact_amount_out.s1 st u) (pool st) (swap_exact_amount_out.user st) (swap_exact_amount_out.amt2 st)
@[simp] def key_AllRecordData_balance (st : Step) : Key :=
  AllRecordData.balance (swap_exact_amount_out.token_in st)
@[simp] def key_AllRecordData_scalar (st : Step) : Key :=
  AllRecordData.scalar (swap_exact_amount_out.token_out st)
@[simp] def key_AllRecordData_weight (st : Step) : Key :=
  AllRecordData.weight (swap_exact_amount_out.token_out st)
@[simp] def new_AllRecordData_balance (st : Step) (u : Unk) : Int :=
  (u.i 2) + (st.pre (swap_exact_amount_out.key_AllRecordData_balance st))
@[simp] def new_AllRecordData_index (st : Step) : Int :=
  st.pre (AllRecordData.index (swap_exact_amount_out.token_in st))
@[simp] def new_AllRecordData_scalar (st : Step) : Int :=
  st.pre (AllRecordData.scalar (swap_exact_amount_out.token_in st))
@[simp] def new_AllRecordData_weight (st : Step) : Int :=
  st.pre (AllRecordData.weight (swap_exact_amount_out.token_in st))
@[simp] def new_AllRecordData_balance_2 (st : Step) : Int :=
  (swap_exact_amount_out.pre_AllRecordData_balance st) - (swap_exact_amount_out.amt2 st)
@[simp] def new_AllRecordData_index_2 (st : Step) : Int :=
  st.pre (AllRecordData.index (swap_exact_amount_out.token_out st))
@[simp] def new_AllRecordData_scalar_2 (st : Step) : Int :=
  st.pre (swap_exact_amount_out.key_AllRecordData_scalar st)
@[simp] def new_AllRecordData_weight_2 (st : Step) : Int :=
  st.pre (swap_exact_amount_out.key_AllRecordData_weight st)
@[simp] def s3 (st : Step) (u : Unk) : Storage :=
  (((((((((((swap_exact_amount_out.s2 st u).set (swap_exact_amount_out.key_AllRecordData_balance st) (swap_exact_amount_out.new_AllRecordData_balance st u)).set (AllRecordData.index (swap_exact_amount_out.token_in st)) (swap_exact_amount_out.new_AllRecordData_index st)).set (AllRecordData.scalar (swap_exact_amount_out.token_in st)) (swap_exact_amount_out.new_AllRecordData_scalar st)).set (AllRecordData.weight (swap_exact_amount_out.token_in st)) (swap_exact_amount_out.new_AllRecordData_weight st)).set (.has (AllRecordData.get (swap_exact_amount_out.token_in st))) 1).set (swap_exact_amount_out.key_AllRecordData_balance st) (swap_exact_amount_out.new_AllRecordData_balance_2 st)).set (AllRecordData.index (swap_exact_amount_out.token_out st)) (swap_exact_amount_out.new_AllRecordData_index_2 st)).set (swap_exact_amount_out.key_AllRecordData_scalar st) (swap_exact_amount_out.new_AllRecordData_scalar_2 st)).set (swap_exact_amount_out.key_AllRecordData_weight st) (swap_exact_amount_out.new_AllRecordData_weight_2 st)).set (.has (AllRecordData.get (swap_exact_amount_out.token_out st))) 1).set (.has AllRecordData) 1
end swap_exact_amount_out

/-- `swap_exact_amount_out(token_in: Address, max_amount_in: i128, token_out: Address, token_amount_out: i128, max_price: i128, user: Address)`: it succeeds exactly when `swap_exact_amount_out.Spec` holds.
    Its effects, in execution order:
    * `swap_exact_amount_out.s1`: transfer `swap_exact_amount_out.amt1 st u` of token `swap_exact_amount_out.token_in st` from `swap_exact_amount_out.user st` to `pool st`
    * `swap_exact_amount_out.s2`: transfer `swap_exact_amount_out.amt2 st` of token `swap_exact_amount_out.token_out st` from `pool st` to `swap_exact_amount_out.user st`
    * `swap_exact_amount_out.s3`: write `swap_exact_amount_out.key_AllRecordData_balance st` := `swap_exact_amount_out.new_AllRecordData_balance st u`, `AllRecordData.index (swap_exact_amount_out.token_in st)` := `swap_exact_amount_out.new_AllRecordData_index st`, `AllRecordData.scalar (swap_exact_amount_out.token_in st)` := `swap_exact_amount_out.new_AllRecordData_scalar st`, `AllRecordData.weight (swap_exact_amount_out.token_in st)` := `swap_exact_amount_out.new_AllRecordData_weight st`, `swap_exact_amount_out.key_AllRecordData_balance st` := `swap_exact_amount_out.new_AllRecordData_balance_2 st`, `AllRecordData.index (swap_exact_amount_out.token_out st)` := `swap_exact_amount_out.new_AllRecordData_index_2 st`, `swap_exact_amount_out.key_AllRecordData_scalar st` := `swap_exact_amount_out.new_AllRecordData_scalar_2 st`, `swap_exact_amount_out.key_AllRecordData_weight st` := `swap_exact_amount_out.new_AllRecordData_weight_2 st`
-/
structure swap_exact_amount_out.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "swap_exact_amount_out"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer1 : xferOk (swap_exact_amount_out.token_in st) st.pre (swap_exact_amount_out.user st) (pool st) (swap_exact_amount_out.amt1 st u)
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer2 : xferOk (swap_exact_amount_out.token_out st) (swap_exact_amount_out.s1 st u) (pool st) (swap_exact_amount_out.user st) (swap_exact_amount_out.amt2 st)
  /-- `swap_exact_amount_out.user st` authorized the call (`require_auth`) -/
  auth_user : (swap_exact_amount_out.user st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : ¬(if (swap_exact_amount_out.amt2 st) = 0 then (swap_exact_amount_out.amt2 st) = 0 else (swap_exact_amount_out.amt2 st) < 1)
  /-- the call panics unless this holds -/
  gate2 : ¬(if (swap_exact_amount_out.max_amount_in st) = 0 then (swap_exact_amount_out.max_amount_in st) = 0 else (swap_exact_amount_out.max_amount_in st) < 1)
  /-- the call panics unless this holds -/
  gate3 : (if (u.g 1) = 69 then (swap_exact_amount_out.max_price st) else (u.g 2)) ≥ 0
  /-- the call panics unless this holds -/
  gate4 : (st.pre (.has (AllRecordData.get (swap_exact_amount_out.token_in st)))) = 1
  /-- the call panics unless this holds -/
  gate5 : (st.pre (.has (AllRecordData.get (swap_exact_amount_out.token_out st)))) = 1
  /-- the call panics unless this holds -/
  gate6 : (u.g 3) ≥ (swap_exact_amount_out.amt2 st)
  /-- the call panics unless this holds -/
  gate7 : (swap_exact_amount_out.amt2 st) ≤ (swap_exact_amount_out.pre_AllRecordData_balance st)
  post : st.post = (swap_exact_amount_out.s3 st u)
  writes : st.writes = [.bal (swap_exact_amount_out.token_in st) (swap_exact_amount_out.user st), .bal (swap_exact_amount_out.token_in st) (pool st), .bal (swap_exact_amount_out.token_out st) (pool st), .bal (swap_exact_amount_out.token_out st) (swap_exact_amount_out.user st), (swap_exact_amount_out.key_AllRecordData_balance st), (AllRecordData.index (swap_exact_amount_out.token_in st)), (AllRecordData.scalar (swap_exact_amount_out.token_in st)), (AllRecordData.weight (swap_exact_amount_out.token_in st)), .has (AllRecordData.get (swap_exact_amount_out.token_in st)), (AllRecordData.index (swap_exact_amount_out.token_out st)), (swap_exact_amount_out.key_AllRecordData_scalar st), (swap_exact_amount_out.key_AllRecordData_weight st), .has (AllRecordData.get (swap_exact_amount_out.token_out st)), .has AllRecordData]
  ret : st.ret = (u.i 0)

def swap_exact_amount_out : Step → Prop := fun st => ∃ u : Unk, swap_exact_amount_out.Spec st u

namespace dep_tokn_amt_in_get_lp_tokns_out
@[simp] def min_pool_amount_out (st : Step) : Int := st.call.arg "min_pool_amount_out"
@[simp] def token_amount_in (st : Step) : Int := st.call.arg "token_amount_in"
@[simp] def token_in (st : Step) : Addr := st.call.argA "token_in"
@[simp] def user (st : Step) : Addr := st.call.argA "user"
@[simp] def key_AllRecordData_balance (st : Step) : Key :=
  AllRecordData.balance (dep_tokn_amt_in_get_lp_tokns_out.token_in st)
@[simp] def key_AllRecordData_index (st : Step) : Key :=
  AllRecordData.index (dep_tokn_amt_in_get_lp_tokns_out.token_in st)
@[simp] def key_AllRecordData_scalar (st : Step) : Key :=
  AllRecordData.scalar (dep_tokn_amt_in_get_lp_tokns_out.token_in st)
@[simp] def key_AllRecordData_weight (st : Step) : Key :=
  AllRecordData.weight (dep_tokn_amt_in_get_lp_tokns_out.token_in st)
@[simp] def key_AllRecordData_get (st : Step) : Key :=
  AllRecordData.get (dep_tokn_amt_in_get_lp_tokns_out.token_in st)
@[simp] def new_AllRecordData_balance (st : Step) : Int :=
  (st.pre (dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_balance st)) + (dep_tokn_amt_in_get_lp_tokns_out.token_amount_in st)
@[simp] def new_AllRecordData_index (st : Step) : Int :=
  st.pre (dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_index st)
@[simp] def new_AllRecordData_scalar (st : Step) : Int :=
  st.pre (dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_scalar st)
@[simp] def new_AllRecordData_weight (st : Step) : Int :=
  st.pre (dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_weight st)
@[simp] def s1 (st : Step) : Storage :=
  ((((((st.pre).set (dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_balance st) (dep_tokn_amt_in_get_lp_tokns_out.new_AllRecordData_balance st)).set (dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_index st) (dep_tokn_amt_in_get_lp_tokns_out.new_AllRecordData_index st)).set (dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_scalar st) (dep_tokn_amt_in_get_lp_tokns_out.new_AllRecordData_scalar st)).set (dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_weight st) (dep_tokn_amt_in_get_lp_tokns_out.new_AllRecordData_weight st)).set (.has (dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_get st)) 1).set (.has AllRecordData) 1
@[simp] def amt1 (st : Step) : Int :=
  dep_tokn_amt_in_get_lp_tokns_out.token_amount_in st
@[simp] def s2 (st : Step) : Storage :=
  xfer (dep_tokn_amt_in_get_lp_tokns_out.token_in st) (dep_tokn_amt_in_get_lp_tokns_out.s1 st) (dep_tokn_amt_in_get_lp_tokns_out.user st) (pool st) (dep_tokn_amt_in_get_lp_tokns_out.amt1 st)
@[simp] def new_TotalShares (st : Step) (u : Unk) : Int :=
  (getOr0 (dep_tokn_amt_in_get_lp_tokns_out.s2 st) TotalShares) + (u.i 1)
@[simp] def s3 (st : Step) (u : Unk) : Storage :=
  ((dep_tokn_amt_in_get_lp_tokns_out.s2 st).set TotalShares (dep_tokn_amt_in_get_lp_tokns_out.new_TotalShares st u)).set (.has TotalShares) 1
@[simp] def new_Balance (st : Step) (u : Unk) : Int :=
  (getOr0 (dep_tokn_amt_in_get_lp_tokns_out.s3 st u) (Balance (dep_tokn_amt_in_get_lp_tokns_out.user st))) + (u.i 2)
@[simp] def s4 (st : Step) (u : Unk) : Storage :=
  ((dep_tokn_amt_in_get_lp_tokns_out.s3 st u).set (Balance (dep_tokn_amt_in_get_lp_tokns_out.user st)) (dep_tokn_amt_in_get_lp_tokns_out.new_Balance st u)).set (.has (Balance (dep_tokn_amt_in_get_lp_tokns_out.user st))) 1
end dep_tokn_amt_in_get_lp_tokns_out

/-- `dep_tokn_amt_in_get_lp_tokns_out(token_in: Address, token_amount_in: i128, min_pool_amount_out: i128, user: Address)`: it succeeds exactly when `dep_tokn_amt_in_get_lp_tokns_out.Spec` holds.
    Its effects, in execution order:
    * `dep_tokn_amt_in_get_lp_tokns_out.s1`: write `dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_balance st` := `dep_tokn_amt_in_get_lp_tokns_out.new_AllRecordData_balance st`, `dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_index st` := `dep_tokn_amt_in_get_lp_tokns_out.new_AllRecordData_index st`, `dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_scalar st` := `dep_tokn_amt_in_get_lp_tokns_out.new_AllRecordData_scalar st`, `dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_weight st` := `dep_tokn_amt_in_get_lp_tokns_out.new_AllRecordData_weight st`
    * `dep_tokn_amt_in_get_lp_tokns_out.s2`: transfer `dep_tokn_amt_in_get_lp_tokns_out.amt1 st` of token `dep_tokn_amt_in_get_lp_tokns_out.token_in st` from `dep_tokn_amt_in_get_lp_tokns_out.user st` to `pool st`
    * `dep_tokn_amt_in_get_lp_tokns_out.s3`: write `TotalShares` := `dep_tokn_amt_in_get_lp_tokns_out.new_TotalShares st u`
    * `dep_tokn_amt_in_get_lp_tokns_out.s4`: write `Balance (dep_tokn_amt_in_get_lp_tokns_out.user st)` := `dep_tokn_amt_in_get_lp_tokns_out.new_Balance st u`
-/
structure dep_tokn_amt_in_get_lp_tokns_out.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "dep_tokn_amt_in_get_lp_tokns_out"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer1 : xferOk (dep_tokn_amt_in_get_lp_tokns_out.token_in st) (dep_tokn_amt_in_get_lp_tokns_out.s1 st) (dep_tokn_amt_in_get_lp_tokns_out.user st) (pool st) (dep_tokn_amt_in_get_lp_tokns_out.amt1 st)
  /-- `dep_tokn_amt_in_get_lp_tokns_out.user st` authorized the call (`require_auth`) -/
  auth_user : (dep_tokn_amt_in_get_lp_tokns_out.user st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : ¬(if (dep_tokn_amt_in_get_lp_tokns_out.amt1 st) = 0 then (dep_tokn_amt_in_get_lp_tokns_out.amt1 st) = 0 else (dep_tokn_amt_in_get_lp_tokns_out.amt1 st) < 1)
  /-- the call panics unless this holds -/
  gate2 : (if (u.g 1) = 69 then (dep_tokn_amt_in_get_lp_tokns_out.min_pool_amount_out st) else (u.g 2)) ≥ 0
  /-- the call panics unless this holds -/
  gate3 : (st.pre (.has (dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_get st))) = 1
  /-- the call panics unless this holds -/
  gate4 : (u.g 3) ≥ (dep_tokn_amt_in_get_lp_tokns_out.amt1 st)
  post : st.post = (dep_tokn_amt_in_get_lp_tokns_out.s4 st u)
  writes : st.writes = [(dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_balance st), (dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_index st), (dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_scalar st), (dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_weight st), .has (dep_tokn_amt_in_get_lp_tokns_out.key_AllRecordData_get st), .has AllRecordData, .bal (dep_tokn_amt_in_get_lp_tokns_out.token_in st) (dep_tokn_amt_in_get_lp_tokns_out.user st), .bal (dep_tokn_amt_in_get_lp_tokns_out.token_in st) (pool st), TotalShares, .has TotalShares, (Balance (dep_tokn_amt_in_get_lp_tokns_out.user st)), .has (Balance (dep_tokn_amt_in_get_lp_tokns_out.user st))]
  ret : st.ret = (u.i 3)

def dep_tokn_amt_in_get_lp_tokns_out : Step → Prop := fun st => ∃ u : Unk, dep_tokn_amt_in_get_lp_tokns_out.Spec st u

namespace dep_lp_tokn_amt_out_get_tokn_in
@[simp] def max_amount_in (st : Step) : Int := st.call.arg "max_amount_in"
@[simp] def pool_amount_out (st : Step) : Int := st.call.arg "pool_amount_out"
@[simp] def token_in (st : Step) : Addr := st.call.argA "token_in"
@[simp] def user (st : Step) : Addr := st.call.argA "user"
@[simp] def key_AllRecordData_balance (st : Step) : Key :=
  AllRecordData.balance (dep_lp_tokn_amt_out_get_tokn_in.token_in st)
@[simp] def key_AllRecordData_index (st : Step) : Key :=
  AllRecordData.index (dep_lp_tokn_amt_out_get_tokn_in.token_in st)
@[simp] def key_AllRecordData_scalar (st : Step) : Key :=
  AllRecordData.scalar (dep_lp_tokn_amt_out_get_tokn_in.token_in st)
@[simp] def key_AllRecordData_weight (st : Step) : Key :=
  AllRecordData.weight (dep_lp_tokn_amt_out_get_tokn_in.token_in st)
@[simp] def key_AllRecordData_get (st : Step) : Key :=
  AllRecordData.get (dep_lp_tokn_amt_out_get_tokn_in.token_in st)
@[simp] def new_AllRecordData_balance (st : Step) (u : Unk) : Int :=
  (u.i 1) + (st.pre (dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_balance st))
@[simp] def new_AllRecordData_index (st : Step) : Int :=
  st.pre (dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_index st)
@[simp] def new_AllRecordData_scalar (st : Step) : Int :=
  st.pre (dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_scalar st)
@[simp] def new_AllRecordData_weight (st : Step) : Int :=
  st.pre (dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_weight st)
@[simp] def s1 (st : Step) (u : Unk) : Storage :=
  ((((((st.pre).set (dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_balance st) (dep_lp_tokn_amt_out_get_tokn_in.new_AllRecordData_balance st u)).set (dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_index st) (dep_lp_tokn_amt_out_get_tokn_in.new_AllRecordData_index st)).set (dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_scalar st) (dep_lp_tokn_amt_out_get_tokn_in.new_AllRecordData_scalar st)).set (dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_weight st) (dep_lp_tokn_amt_out_get_tokn_in.new_AllRecordData_weight st)).set (.has (dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_get st)) 1).set (.has AllRecordData) 1
@[simp] def amt1 (_st : Step) (u : Unk) : Int :=
  u.i 2
@[simp] def s2 (st : Step) (u : Unk) : Storage :=
  xfer (dep_lp_tokn_amt_out_get_tokn_in.token_in st) (dep_lp_tokn_amt_out_get_tokn_in.s1 st u) (dep_lp_tokn_amt_out_get_tokn_in.user st) (pool st) (dep_lp_tokn_amt_out_get_tokn_in.amt1 st u)
@[simp] def new_TotalShares (st : Step) (u : Unk) : Int :=
  (getOr0 (dep_lp_tokn_amt_out_get_tokn_in.s2 st u) TotalShares) + (dep_lp_tokn_amt_out_get_tokn_in.pool_amount_out st)
@[simp] def s3 (st : Step) (u : Unk) : Storage :=
  ((dep_lp_tokn_amt_out_get_tokn_in.s2 st u).set TotalShares (dep_lp_tokn_amt_out_get_tokn_in.new_TotalShares st u)).set (.has TotalShares) 1
@[simp] def new_Balance (st : Step) (u : Unk) : Int :=
  (getOr0 (dep_lp_tokn_amt_out_get_tokn_in.s3 st u) (Balance (dep_lp_tokn_amt_out_get_tokn_in.user st))) + (dep_lp_tokn_amt_out_get_tokn_in.pool_amount_out st)
@[simp] def s4 (st : Step) (u : Unk) : Storage :=
  ((dep_lp_tokn_amt_out_get_tokn_in.s3 st u).set (Balance (dep_lp_tokn_amt_out_get_tokn_in.user st)) (dep_lp_tokn_amt_out_get_tokn_in.new_Balance st u)).set (.has (Balance (dep_lp_tokn_amt_out_get_tokn_in.user st))) 1
end dep_lp_tokn_amt_out_get_tokn_in

/-- `dep_lp_tokn_amt_out_get_tokn_in(token_in: Address, pool_amount_out: i128, max_amount_in: i128, user: Address)`: it succeeds exactly when `dep_lp_tokn_amt_out_get_tokn_in.Spec` holds.
    Its effects, in execution order:
    * `dep_lp_tokn_amt_out_get_tokn_in.s1`: write `dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_balance st` := `dep_lp_tokn_amt_out_get_tokn_in.new_AllRecordData_balance st u`, `dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_index st` := `dep_lp_tokn_amt_out_get_tokn_in.new_AllRecordData_index st`, `dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_scalar st` := `dep_lp_tokn_amt_out_get_tokn_in.new_AllRecordData_scalar st`, `dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_weight st` := `dep_lp_tokn_amt_out_get_tokn_in.new_AllRecordData_weight st`
    * `dep_lp_tokn_amt_out_get_tokn_in.s2`: transfer `dep_lp_tokn_amt_out_get_tokn_in.amt1 st u` of token `dep_lp_tokn_amt_out_get_tokn_in.token_in st` from `dep_lp_tokn_amt_out_get_tokn_in.user st` to `pool st`
    * `dep_lp_tokn_amt_out_get_tokn_in.s3`: write `TotalShares` := `dep_lp_tokn_amt_out_get_tokn_in.new_TotalShares st u`
    * `dep_lp_tokn_amt_out_get_tokn_in.s4`: write `Balance (dep_lp_tokn_amt_out_get_tokn_in.user st)` := `dep_lp_tokn_amt_out_get_tokn_in.new_Balance st u`
-/
structure dep_lp_tokn_amt_out_get_tokn_in.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "dep_lp_tokn_amt_out_get_tokn_in"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer1 : xferOk (dep_lp_tokn_amt_out_get_tokn_in.token_in st) (dep_lp_tokn_amt_out_get_tokn_in.s1 st u) (dep_lp_tokn_amt_out_get_tokn_in.user st) (pool st) (dep_lp_tokn_amt_out_get_tokn_in.amt1 st u)
  /-- `dep_lp_tokn_amt_out_get_tokn_in.user st` authorized the call (`require_auth`) -/
  auth_user : (dep_lp_tokn_amt_out_get_tokn_in.user st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : ¬(if (dep_lp_tokn_amt_out_get_tokn_in.pool_amount_out st) = 0 then (dep_lp_tokn_amt_out_get_tokn_in.pool_amount_out st) = 0 else (dep_lp_tokn_amt_out_get_tokn_in.pool_amount_out st) < 1)
  /-- the call panics unless this holds -/
  gate2 : ¬(if (if (u.g 1) = 69 then (dep_lp_tokn_amt_out_get_tokn_in.max_amount_in st) else (u.g 2)) = 0 then (dep_lp_tokn_amt_out_get_tokn_in.max_amount_in st) = 0 else (if (u.g 3) = 69 then (dep_lp_tokn_amt_out_get_tokn_in.max_amount_in st) else (u.g 4)) < 1)
  /-- the call panics unless this holds -/
  gate3 : (st.pre (.has (dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_get st))) = 1
  post : st.post = (dep_lp_tokn_amt_out_get_tokn_in.s4 st u)
  writes : st.writes = [(dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_balance st), (dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_index st), (dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_scalar st), (dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_weight st), .has (dep_lp_tokn_amt_out_get_tokn_in.key_AllRecordData_get st), .has AllRecordData, .bal (dep_lp_tokn_amt_out_get_tokn_in.token_in st) (dep_lp_tokn_amt_out_get_tokn_in.user st), .bal (dep_lp_tokn_amt_out_get_tokn_in.token_in st) (pool st), TotalShares, .has TotalShares, (Balance (dep_lp_tokn_amt_out_get_tokn_in.user st)), .has (Balance (dep_lp_tokn_amt_out_get_tokn_in.user st))]
  ret : st.ret = (u.i 3)

def dep_lp_tokn_amt_out_get_tokn_in : Step → Prop := fun st => ∃ u : Unk, dep_lp_tokn_amt_out_get_tokn_in.Spec st u

namespace wdr_tokn_amt_in_get_lp_tokns_out
@[simp] def min_amount_out (st : Step) : Int := st.call.arg "min_amount_out"
@[simp] def pool_amount_in (st : Step) : Int := st.call.arg "pool_amount_in"
@[simp] def token_out (st : Step) : Addr := st.call.argA "token_out"
@[simp] def user (st : Step) : Addr := st.call.argA "user"
@[simp] def new_Balance (st : Step) : Int :=
  (getOr0 st.pre (Balance (wdr_tokn_amt_in_get_lp_tokns_out.user st))) - (wdr_tokn_amt_in_get_lp_tokns_out.pool_amount_in st)
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set (Balance (wdr_tokn_amt_in_get_lp_tokns_out.user st)) (wdr_tokn_amt_in_get_lp_tokns_out.new_Balance st)).set (.has (Balance (wdr_tokn_amt_in_get_lp_tokns_out.user st))) 1
@[simp] def new_Balance_2 (st : Step) : Int :=
  (getOr0 (wdr_tokn_amt_in_get_lp_tokns_out.s1 st) (Balance (pool st))) + (wdr_tokn_amt_in_get_lp_tokns_out.pool_amount_in st)
@[simp] def s2 (st : Step) : Storage :=
  ((wdr_tokn_amt_in_get_lp_tokns_out.s1 st).set (Balance (pool st)) (wdr_tokn_amt_in_get_lp_tokns_out.new_Balance_2 st)).set (.has (Balance (pool st))) 1
@[simp] def new_Balance_3 (st : Step) : Int :=
  (getOr0 (wdr_tokn_amt_in_get_lp_tokns_out.s2 st) (Balance (pool st))) - (wdr_tokn_amt_in_get_lp_tokns_out.pool_amount_in st)
@[simp] def s3 (st : Step) : Storage :=
  ((wdr_tokn_amt_in_get_lp_tokns_out.s2 st).set (Balance (pool st)) (wdr_tokn_amt_in_get_lp_tokns_out.new_Balance_3 st)).set (.has (Balance (pool st))) 1
@[simp] def new_TotalShares (st : Step) : Int :=
  (getOr0 (wdr_tokn_amt_in_get_lp_tokns_out.s2 st) TotalShares) - (wdr_tokn_amt_in_get_lp_tokns_out.pool_amount_in st)
@[simp] def s4 (st : Step) : Storage :=
  ((wdr_tokn_amt_in_get_lp_tokns_out.s3 st).set TotalShares (wdr_tokn_amt_in_get_lp_tokns_out.new_TotalShares st)).set (.has TotalShares) 1
@[simp] def amt1 (_st : Step) (u : Unk) : Int :=
  u.i 1
@[simp] def s5 (st : Step) (u : Unk) : Storage :=
  xfer (wdr_tokn_amt_in_get_lp_tokns_out.token_out st) (wdr_tokn_amt_in_get_lp_tokns_out.s4 st) (pool st) (wdr_tokn_amt_in_get_lp_tokns_out.user st) (wdr_tokn_amt_in_get_lp_tokns_out.amt1 st u)
@[simp] def s6 (st : Step) (u : Unk) : Storage :=
  ((wdr_tokn_amt_in_get_lp_tokns_out.s5 st u).setUnder AllRecordData (u.s 2)).set (.has AllRecordData) 1
end wdr_tokn_amt_in_get_lp_tokns_out

/-- `wdr_tokn_amt_in_get_lp_tokns_out(token_out: Address, pool_amount_in: i128, min_amount_out: i128, user: Address)`: it succeeds exactly when `wdr_tokn_amt_in_get_lp_tokns_out.Spec` holds.
    Its effects, in execution order:
    * `wdr_tokn_amt_in_get_lp_tokns_out.s1`: write `Balance (wdr_tokn_amt_in_get_lp_tokns_out.user st)` := `wdr_tokn_amt_in_get_lp_tokns_out.new_Balance st`
    * `wdr_tokn_amt_in_get_lp_tokns_out.s2`: write `Balance (pool st)` := `wdr_tokn_amt_in_get_lp_tokns_out.new_Balance_2 st`
    * `wdr_tokn_amt_in_get_lp_tokns_out.s3`: write `Balance (pool st)` := `wdr_tokn_amt_in_get_lp_tokns_out.new_Balance_3 st`
    * `wdr_tokn_amt_in_get_lp_tokns_out.s4`: write `TotalShares` := `wdr_tokn_amt_in_get_lp_tokns_out.new_TotalShares st`
    * `wdr_tokn_amt_in_get_lp_tokns_out.s5`: transfer `wdr_tokn_amt_in_get_lp_tokns_out.amt1 st u` of token `wdr_tokn_amt_in_get_lp_tokns_out.token_out st` from `pool st` to `wdr_tokn_amt_in_get_lp_tokns_out.user st`
    * `wdr_tokn_amt_in_get_lp_tokns_out.s6`: write `AllRecordData` := `u.s 2`
-/
structure wdr_tokn_amt_in_get_lp_tokns_out.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "wdr_tokn_amt_in_get_lp_tokns_out"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer1 : xferOk (wdr_tokn_amt_in_get_lp_tokns_out.token_out st) (wdr_tokn_amt_in_get_lp_tokns_out.s4 st) (pool st) (wdr_tokn_amt_in_get_lp_tokns_out.user st) (wdr_tokn_amt_in_get_lp_tokns_out.amt1 st u)
  /-- `wdr_tokn_amt_in_get_lp_tokns_out.user st` authorized the call (`require_auth`) -/
  auth_user : (wdr_tokn_amt_in_get_lp_tokns_out.user st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : ¬(if (wdr_tokn_amt_in_get_lp_tokns_out.pool_amount_in st) = 0 then (wdr_tokn_amt_in_get_lp_tokns_out.pool_amount_in st) = 0 else (wdr_tokn_amt_in_get_lp_tokns_out.pool_amount_in st) < 1)
  /-- the call panics unless this holds -/
  gate2 : (if (u.g 1) = 69 then (wdr_tokn_amt_in_get_lp_tokns_out.min_amount_out st) else (u.g 2)) ≥ 0
  /-- the call panics unless this holds -/
  gate3 : (st.pre (.has (AllRecordData.get (wdr_tokn_amt_in_get_lp_tokns_out.token_out st)))) = 1
  post : st.post = (wdr_tokn_amt_in_get_lp_tokns_out.s6 st u)
  writes : st.writes = [(Balance (wdr_tokn_amt_in_get_lp_tokns_out.user st)), .has (Balance (wdr_tokn_amt_in_get_lp_tokns_out.user st)), (Balance (pool st)), .has (Balance (pool st)), TotalShares, .has TotalShares, .bal (wdr_tokn_amt_in_get_lp_tokns_out.token_out st) (pool st), .bal (wdr_tokn_amt_in_get_lp_tokns_out.token_out st) (wdr_tokn_amt_in_get_lp_tokns_out.user st), AllRecordData, .has AllRecordData]
  ret : st.ret = (u.i 3)

def wdr_tokn_amt_in_get_lp_tokns_out : Step → Prop := fun st => ∃ u : Unk, wdr_tokn_amt_in_get_lp_tokns_out.Spec st u

namespace wdr_tokn_amt_out_get_lp_tokns_in
@[simp] def max_pool_amount_in (st : Step) : Int := st.call.arg "max_pool_amount_in"
@[simp] def token_amount_out (st : Step) : Int := st.call.arg "token_amount_out"
@[simp] def token_out (st : Step) : Addr := st.call.argA "token_out"
@[simp] def user (st : Step) : Addr := st.call.argA "user"
@[simp] def new_Balance (st : Step) (u : Unk) : Int :=
  (getOr0 st.pre (Balance (wdr_tokn_amt_out_get_lp_tokns_in.user st))) - (u.i 1)
@[simp] def s1 (st : Step) (u : Unk) : Storage :=
  ((st.pre).set (Balance (wdr_tokn_amt_out_get_lp_tokns_in.user st)) (wdr_tokn_amt_out_get_lp_tokns_in.new_Balance st u)).set (.has (Balance (wdr_tokn_amt_out_get_lp_tokns_in.user st))) 1
@[simp] def new_Balance_2 (st : Step) (u : Unk) : Int :=
  (getOr0 (wdr_tokn_amt_out_get_lp_tokns_in.s1 st u) (Balance (pool st))) + (u.i 2)
@[simp] def s2 (st : Step) (u : Unk) : Storage :=
  ((wdr_tokn_amt_out_get_lp_tokns_in.s1 st u).set (Balance (pool st)) (wdr_tokn_amt_out_get_lp_tokns_in.new_Balance_2 st u)).set (.has (Balance (pool st))) 1
@[simp] def new_Balance_3 (st : Step) (u : Unk) : Int :=
  (getOr0 (wdr_tokn_amt_out_get_lp_tokns_in.s2 st u) (Balance (pool st))) - (u.i 3)
@[simp] def s3 (st : Step) (u : Unk) : Storage :=
  ((wdr_tokn_amt_out_get_lp_tokns_in.s2 st u).set (Balance (pool st)) (wdr_tokn_amt_out_get_lp_tokns_in.new_Balance_3 st u)).set (.has (Balance (pool st))) 1
@[simp] def new_TotalShares (st : Step) (u : Unk) : Int :=
  (getOr0 (wdr_tokn_amt_out_get_lp_tokns_in.s2 st u) TotalShares) - (u.i 4)
@[simp] def s4 (st : Step) (u : Unk) : Storage :=
  ((wdr_tokn_amt_out_get_lp_tokns_in.s3 st u).set TotalShares (wdr_tokn_amt_out_get_lp_tokns_in.new_TotalShares st u)).set (.has TotalShares) 1
@[simp] def amt1 (st : Step) : Int :=
  wdr_tokn_amt_out_get_lp_tokns_in.token_amount_out st
@[simp] def s5 (st : Step) (u : Unk) : Storage :=
  xfer (wdr_tokn_amt_out_get_lp_tokns_in.token_out st) (wdr_tokn_amt_out_get_lp_tokns_in.s4 st u) (pool st) (wdr_tokn_amt_out_get_lp_tokns_in.user st) (wdr_tokn_amt_out_get_lp_tokns_in.amt1 st)
@[simp] def s6 (st : Step) (u : Unk) : Storage :=
  ((wdr_tokn_amt_out_get_lp_tokns_in.s5 st u).setUnder AllRecordData (u.s 5)).set (.has AllRecordData) 1
end wdr_tokn_amt_out_get_lp_tokns_in

/-- `wdr_tokn_amt_out_get_lp_tokns_in(token_out: Address, token_amount_out: i128, max_pool_amount_in: i128, user: Address)`: it succeeds exactly when `wdr_tokn_amt_out_get_lp_tokns_in.Spec` holds.
    Its effects, in execution order:
    * `wdr_tokn_amt_out_get_lp_tokns_in.s1`: write `Balance (wdr_tokn_amt_out_get_lp_tokns_in.user st)` := `wdr_tokn_amt_out_get_lp_tokns_in.new_Balance st u`
    * `wdr_tokn_amt_out_get_lp_tokns_in.s2`: write `Balance (pool st)` := `wdr_tokn_amt_out_get_lp_tokns_in.new_Balance_2 st u`
    * `wdr_tokn_amt_out_get_lp_tokns_in.s3`: write `Balance (pool st)` := `wdr_tokn_amt_out_get_lp_tokns_in.new_Balance_3 st u`
    * `wdr_tokn_amt_out_get_lp_tokns_in.s4`: write `TotalShares` := `wdr_tokn_amt_out_get_lp_tokns_in.new_TotalShares st u`
    * `wdr_tokn_amt_out_get_lp_tokns_in.s5`: transfer `wdr_tokn_amt_out_get_lp_tokns_in.amt1 st` of token `wdr_tokn_amt_out_get_lp_tokns_in.token_out st` from `pool st` to `wdr_tokn_amt_out_get_lp_tokns_in.user st`
    * `wdr_tokn_amt_out_get_lp_tokns_in.s6`: write `AllRecordData` := `u.s 5`
-/
structure wdr_tokn_amt_out_get_lp_tokns_in.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "wdr_tokn_amt_out_get_lp_tokns_in"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer1 : xferOk (wdr_tokn_amt_out_get_lp_tokns_in.token_out st) (wdr_tokn_amt_out_get_lp_tokns_in.s4 st u) (pool st) (wdr_tokn_amt_out_get_lp_tokns_in.user st) (wdr_tokn_amt_out_get_lp_tokns_in.amt1 st)
  /-- `wdr_tokn_amt_out_get_lp_tokns_in.user st` authorized the call (`require_auth`) -/
  auth_user : (wdr_tokn_amt_out_get_lp_tokns_in.user st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : ¬(if (wdr_tokn_amt_out_get_lp_tokns_in.amt1 st) = 0 then (wdr_tokn_amt_out_get_lp_tokns_in.amt1 st) = 0 else (wdr_tokn_amt_out_get_lp_tokns_in.amt1 st) < 1)
  /-- the call panics unless this holds -/
  gate2 : ¬(if (if (u.g 1) = 69 then (wdr_tokn_amt_out_get_lp_tokns_in.max_pool_amount_in st) else (u.g 2)) = 0 then (wdr_tokn_amt_out_get_lp_tokns_in.max_pool_amount_in st) = 0 else (if (u.g 3) = 69 then (wdr_tokn_amt_out_get_lp_tokns_in.max_pool_amount_in st) else (u.g 4)) < 1)
  /-- the call panics unless this holds -/
  gate3 : (st.pre (.has (AllRecordData.get (wdr_tokn_amt_out_get_lp_tokns_in.token_out st)))) = 1
  /-- the call panics unless this holds -/
  gate4 : (u.g 5) ≥ (wdr_tokn_amt_out_get_lp_tokns_in.amt1 st)
  /-- the call panics unless this holds -/
  gate5 : (wdr_tokn_amt_out_get_lp_tokns_in.amt1 st) ≤ (st.pre (AllRecordData.balance (wdr_tokn_amt_out_get_lp_tokns_in.token_out st)))
  post : st.post = (wdr_tokn_amt_out_get_lp_tokns_in.s6 st u)
  writes : st.writes = [(Balance (wdr_tokn_amt_out_get_lp_tokns_in.user st)), .has (Balance (wdr_tokn_amt_out_get_lp_tokns_in.user st)), (Balance (pool st)), .has (Balance (pool st)), TotalShares, .has TotalShares, .bal (wdr_tokn_amt_out_get_lp_tokns_in.token_out st) (pool st), .bal (wdr_tokn_amt_out_get_lp_tokns_in.token_out st) (wdr_tokn_amt_out_get_lp_tokns_in.user st), AllRecordData, .has AllRecordData]
  ret : st.ret = (u.i 6)

def wdr_tokn_amt_out_get_lp_tokns_in : Step → Prop := fun st => ∃ u : Unk, wdr_tokn_amt_out_get_lp_tokns_in.Spec st u

namespace set_controller
@[simp] def manager (st : Step) : Addr := st.call.argA "manager"
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set Controller (set_controller.manager st)).set (.has Controller) 1
end set_controller

/-- `set_controller(manager: Address)`: it succeeds exactly when `set_controller.Spec` holds.
    Its effects, in execution order:
    * `set_controller.s1`: write `Controller` := `set_controller.manager st`
-/
structure set_controller.Spec (st : Step) : Prop where
  fn : st.call.fn = "set_controller"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `(set_controller.s1 st) Controller` authorized the call (`require_auth`) -/
  auth_set_controller_s1_st__Controller : ((set_controller.s1 st) Controller) ∈ st.call.signers
  post : st.post = (set_controller.s1 st)
  writes : st.writes = [Controller, .has Controller]
  ret : st.ret = 2

abbrev set_controller : Step → Prop := fun st => set_controller.Spec st

namespace set_freeze_status
@[simp] def val (st : Step) : Int := st.call.arg "val"
@[simp] def s1 (st : Step) (u : Unk) : Storage :=
  ((st.pre).setUnder (u.k 1) (u.s 2)).set (.has (u.k 1)) 1
end set_freeze_status

/-- `set_freeze_status(val: bool)`: it succeeds exactly when `set_freeze_status.Spec` holds.
    Its effects, in execution order:
    * `set_freeze_status.s1`: write `u.k 1` := `u.s 2`
-/
structure set_freeze_status.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "set_freeze_status"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `st.pre Controller` authorized the call (`require_auth`) -/
  auth_Controller : (st.pre Controller) ∈ st.call.signers
  post : st.post = (set_freeze_status.s1 st u)
  writes : st.writes = [(u.k 1), .has (u.k 1)]
  ret : st.ret = 2

def set_freeze_status : Step → Prop := fun st => ∃ u : Unk, set_freeze_status.Spec st u

/-- `get_total_supply()`: it succeeds exactly when `get_total_supply.Spec` holds.
-/
structure get_total_supply.Spec (st : Step) : Prop where
  fn : st.call.fn = "get_total_supply"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (getOr0 st.pre TotalShares)

abbrev get_total_supply : Step → Prop := fun st => get_total_supply.Spec st

/-- `get_controller()`: it succeeds exactly when `get_controller.Spec` holds.
-/
structure get_controller.Spec (st : Step) : Prop where
  fn : st.call.fn = "get_controller"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (st.pre Controller)

abbrev get_controller : Step → Prop := fun st => get_controller.Spec st

/-- `get_tokens()`: it succeeds exactly when `get_tokens.Spec` holds.
-/
structure get_tokens.Spec (st : Step) : Prop where
  fn : st.call.fn = "get_tokens"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (st.pre AllTokenVec)

abbrev get_tokens : Step → Prop := fun st => get_tokens.Spec st

namespace get_balance
@[simp] def token (st : Step) : Addr := st.call.argA "token"
end get_balance

/-- `get_balance(token: Address)`: it succeeds exactly when `get_balance.Spec` holds.
-/
structure get_balance.Spec (st : Step) : Prop where
  fn : st.call.fn = "get_balance"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the call panics unless this holds -/
  gate1 : (st.pre (.has (AllRecordData.get (get_balance.token st)))) = 1
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (st.pre (AllRecordData.balance (get_balance.token st)))

abbrev get_balance : Step → Prop := fun st => get_balance.Spec st

namespace get_normalized_weight
@[simp] def token (st : Step) : Addr := st.call.argA "token"
end get_normalized_weight

/-- `get_normalized_weight(token: Address)`: it succeeds exactly when `get_normalized_weight.Spec` holds.
-/
structure get_normalized_weight.Spec (st : Step) : Prop where
  fn : st.call.fn = "get_normalized_weight"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the call panics unless this holds -/
  gate1 : (st.pre (.has (AllRecordData.get (get_normalized_weight.token st)))) = 1
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (st.pre (AllRecordData.weight (get_normalized_weight.token st)))

abbrev get_normalized_weight : Step → Prop := fun st => get_normalized_weight.Spec st

namespace get_spot_price
@[simp] def token_in (st : Step) : Addr := st.call.argA "token_in"
@[simp] def token_out (st : Step) : Addr := st.call.argA "token_out"
end get_spot_price

/-- `get_spot_price(token_in: Address, token_out: Address)`: it succeeds exactly when `get_spot_price.Spec` holds.
-/
structure get_spot_price.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "get_spot_price"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the call panics unless this holds -/
  gate1 : (st.pre (.has (AllRecordData.get (get_spot_price.token_in st)))) = 1
  /-- the call panics unless this holds -/
  gate2 : (st.pre (.has (AllRecordData.get (get_spot_price.token_out st)))) = 1
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (u.i 1)

def get_spot_price : Step → Prop := fun st => ∃ u : Unk, get_spot_price.Spec st u

/-- `get_swap_fee()`: it succeeds exactly when `get_swap_fee.Spec` holds.
-/
structure get_swap_fee.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "get_swap_fee"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (u.i 3)

def get_swap_fee : Step → Prop := fun st => ∃ u : Unk, get_swap_fee.Spec st u

namespace get_spot_price_sans_fee
@[simp] def token_in (st : Step) : Addr := st.call.argA "token_in"
@[simp] def token_out (st : Step) : Addr := st.call.argA "token_out"
end get_spot_price_sans_fee

/-- `get_spot_price_sans_fee(token_in: Address, token_out: Address)`: it succeeds exactly when `get_spot_price_sans_fee.Spec` holds.
-/
structure get_spot_price_sans_fee.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "get_spot_price_sans_fee"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the call panics unless this holds -/
  gate1 : (st.pre (.has (AllRecordData.get (get_spot_price_sans_fee.token_in st)))) = 1
  /-- the call panics unless this holds -/
  gate2 : (st.pre (.has (AllRecordData.get (get_spot_price_sans_fee.token_out st)))) = 1
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (u.i 1)

def get_spot_price_sans_fee : Step → Prop := fun st => ∃ u : Unk, get_spot_price_sans_fee.Spec st u

namespace allowance
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def spender (st : Step) : Addr := st.call.argA "spender"
end allowance

/-- `allowance(from: Address, spender: Address)`: it succeeds exactly when `allowance.Spec` holds.
-/
structure allowance.Spec (st : Step) : Prop where
  fn : st.call.fn = "allowance"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (if (st.pre (.has (Allowance (allowance.«from» st) (allowance.spender st)))) = 1 then (if (st.call.env "sequence") > (st.pre (Allowance.expiration_ledger (allowance.«from» st) (allowance.spender st))) then 0 else (st.pre (Allowance.amount (allowance.«from» st) (allowance.spender st)))) else 0)

abbrev allowance : Step → Prop := fun st => allowance.Spec st

namespace approve
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def expiration_ledger (st : Step) : Int := st.call.arg "expiration_ledger"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def spender (st : Step) : Addr := st.call.argA "spender"
@[simp] def key_Allowance_amount (st : Step) : Key :=
  Allowance.amount (approve.«from» st) (approve.spender st)
@[simp] def key_Allowance_expiration_ledger (st : Step) : Key :=
  Allowance.expiration_ledger (approve.«from» st) (approve.spender st)
@[simp] def s1 (st : Step) : Storage :=
  (((st.pre).set (approve.key_Allowance_amount st) (approve.amount st)).set (approve.key_Allowance_expiration_ledger st) (approve.expiration_ledger st)).set (.has (Allowance (approve.«from» st) (approve.spender st))) 1
end approve

/-- `approve(from: Address, spender: Address, amount: i128, expiration_ledger: u32)`: it succeeds exactly when `approve.Spec` holds.
    Its effects, in execution order:
    * `approve.s1`: write `approve.key_Allowance_amount st` := `approve.amount st`, `approve.key_Allowance_expiration_ledger st` := `approve.expiration_ledger st`
-/
structure approve.Spec (st : Step) : Prop where
  fn : st.call.fn = "approve"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `approve.«from» st` authorized the call (`require_auth`) -/
  auth_from : (approve.«from» st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (approve.amount st) > -1
  post : st.post = (approve.s1 st)
  writes : st.writes = [(approve.key_Allowance_amount st), (approve.key_Allowance_expiration_ledger st), .has (Allowance (approve.«from» st) (approve.spender st))]
  ret : st.ret = 2

abbrev approve : Step → Prop := fun st => approve.Spec st

namespace balance
@[simp] def id (st : Step) : Addr := st.call.argA "id"
end balance

/-- `balance(id: Address)`: it succeeds exactly when `balance.Spec` holds.
-/
structure balance.Spec (st : Step) : Prop where
  fn : st.call.fn = "balance"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (getOr0 st.pre (Balance (balance.id st)))

abbrev balance : Step → Prop := fun st => balance.Spec st

namespace transfer
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def to (st : Step) : Addr := st.call.argA "to"
@[simp] def new_Balance (st : Step) : Int :=
  (getOr0 st.pre (Balance (transfer.«from» st))) - (transfer.amount st)
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set (Balance (transfer.«from» st)) (transfer.new_Balance st)).set (.has (Balance (transfer.«from» st))) 1
@[simp] def new_Balance_2 (st : Step) : Int :=
  (getOr0 (transfer.s1 st) (Balance (transfer.to st))) + (transfer.amount st)
@[simp] def s2 (st : Step) : Storage :=
  ((transfer.s1 st).set (Balance (transfer.to st)) (transfer.new_Balance_2 st)).set (.has (Balance (transfer.to st))) 1
end transfer

/-- `transfer(from: Address, to: Address, amount: i128)`: it succeeds exactly when `transfer.Spec` holds.
    Its effects, in execution order:
    * `transfer.s1`: write `Balance (transfer.«from» st)` := `transfer.new_Balance st`
    * `transfer.s2`: write `Balance (transfer.to st)` := `transfer.new_Balance_2 st`
-/
structure transfer.Spec (st : Step) : Prop where
  fn : st.call.fn = "transfer"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `transfer.«from» st` authorized the call (`require_auth`) -/
  auth_from : (transfer.«from» st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (transfer.amount st) > -1
  post : st.post = (transfer.s2 st)
  writes : st.writes = [(Balance (transfer.«from» st)), .has (Balance (transfer.«from» st)), (Balance (transfer.to st)), .has (Balance (transfer.to st))]
  ret : st.ret = 2

abbrev transfer : Step → Prop := fun st => transfer.Spec st

namespace transfer_from
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def spender (st : Step) : Addr := st.call.argA "spender"
@[simp] def to (st : Step) : Addr := st.call.argA "to"
@[simp] def pre_Allowance_amount (st : Step) : Int :=
  st.pre (Allowance.amount (transfer_from.«from» st) (transfer_from.spender st))
@[simp] def pre_Allowance_expiration_ledger (st : Step) : Int :=
  st.pre (Allowance.expiration_ledger (transfer_from.«from» st) (transfer_from.spender st))
@[simp] def pre_has_Allowance (st : Step) : Int :=
  st.pre (.has (Allowance (transfer_from.«from» st) (transfer_from.spender st)))
@[simp] def key_Allowance_amount (st : Step) : Key :=
  Allowance.amount (transfer_from.«from» st) (transfer_from.spender st)
@[simp] def key_Allowance_expiration_ledger (st : Step) : Key :=
  Allowance.expiration_ledger (transfer_from.«from» st) (transfer_from.spender st)
@[simp] def key_Allowance (st : Step) : Key :=
  Allowance (transfer_from.«from» st) (transfer_from.spender st)
@[simp] def new_Allowance_amount (st : Step) : Int :=
  (if (transfer_from.pre_has_Allowance st) = 1 then (if (st.call.env "sequence") > (transfer_from.pre_Allowance_expiration_ledger st) then 0 else (transfer_from.pre_Allowance_amount st)) else 0) - (transfer_from.amount st)
@[simp] def new_Allowance_expiration_ledger (st : Step) : Int :=
  getOr0 st.pre (transfer_from.key_Allowance_expiration_ledger st) (base := (transfer_from.key_Allowance st))
@[simp] def s1 (st : Step) : Storage :=
  if (transfer_from.amount st) ≠ 0 then (((st.pre).set (transfer_from.key_Allowance_amount st) (transfer_from.new_Allowance_amount st)).set (transfer_from.key_Allowance_expiration_ledger st) (transfer_from.new_Allowance_expiration_ledger st)).set (.has (transfer_from.key_Allowance st)) 1 else st.pre
@[simp] def new_Balance (st : Step) : Int :=
  (getOr0 (transfer_from.s1 st) (Balance (transfer_from.«from» st))) - (transfer_from.amount st)
@[simp] def s2 (st : Step) : Storage :=
  ((transfer_from.s1 st).set (Balance (transfer_from.«from» st)) (transfer_from.new_Balance st)).set (.has (Balance (transfer_from.«from» st))) 1
@[simp] def new_Balance_2 (st : Step) : Int :=
  (getOr0 (transfer_from.s2 st) (Balance (transfer_from.to st))) + (transfer_from.amount st)
@[simp] def s3 (st : Step) : Storage :=
  ((transfer_from.s2 st).set (Balance (transfer_from.to st)) (transfer_from.new_Balance_2 st)).set (.has (Balance (transfer_from.to st))) 1
end transfer_from

/-- `transfer_from(spender: Address, from: Address, to: Address, amount: i128)`: it succeeds exactly when `transfer_from.Spec` holds.
    Its effects, in execution order:
    * `transfer_from.s1`: write `transfer_from.key_Allowance_amount st` := `transfer_from.new_Allowance_amount st`, `transfer_from.key_Allowance_expiration_ledger st` := `transfer_from.new_Allowance_expiration_ledger st`, when `(transfer_from.amount st) ≠ 0`
    * `transfer_from.s2`: write `Balance (transfer_from.«from» st)` := `transfer_from.new_Balance st`
    * `transfer_from.s3`: write `Balance (transfer_from.to st)` := `transfer_from.new_Balance_2 st`
-/
structure transfer_from.Spec (st : Step) : Prop where
  fn : st.call.fn = "transfer_from"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `transfer_from.spender st` authorized the call (`require_auth`) -/
  auth_spender : (transfer_from.spender st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (transfer_from.amount st) > -1
  /-- the call panics unless this holds -/
  gate2 : (if (transfer_from.pre_has_Allowance st) = 1 then (if (st.call.env "sequence") > (transfer_from.pre_Allowance_expiration_ledger st) then 0 else (transfer_from.pre_Allowance_amount st)) else 0) ≥ (transfer_from.amount st)
  post : st.post = (transfer_from.s3 st)
  writes : st.writes = [(transfer_from.key_Allowance_amount st), (transfer_from.key_Allowance_expiration_ledger st), .has (transfer_from.key_Allowance st), (Balance (transfer_from.«from» st)), .has (Balance (transfer_from.«from» st)), (Balance (transfer_from.to st)), .has (Balance (transfer_from.to st))]
  ret : st.ret = 2

abbrev transfer_from : Step → Prop := fun st => transfer_from.Spec st

namespace burn
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def new_Balance (st : Step) : Int :=
  (getOr0 st.pre (Balance (burn.«from» st))) - (burn.amount st)
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set (Balance (burn.«from» st)) (burn.new_Balance st)).set (.has (Balance (burn.«from» st))) 1
@[simp] def new_TotalShares (st : Step) : Int :=
  (getOr0 st.pre TotalShares) - (burn.amount st)
@[simp] def s2 (st : Step) : Storage :=
  ((burn.s1 st).set TotalShares (burn.new_TotalShares st)).set (.has TotalShares) 1
end burn

/-- `burn(from: Address, amount: i128)`: it succeeds exactly when `burn.Spec` holds.
    Its effects, in execution order:
    * `burn.s1`: write `Balance (burn.«from» st)` := `burn.new_Balance st`
    * `burn.s2`: write `TotalShares` := `burn.new_TotalShares st`
-/
structure burn.Spec (st : Step) : Prop where
  fn : st.call.fn = "burn"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `burn.«from» st` authorized the call (`require_auth`) -/
  auth_from : (burn.«from» st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (burn.amount st) > -1
  post : st.post = (burn.s2 st)
  writes : st.writes = [(Balance (burn.«from» st)), .has (Balance (burn.«from» st)), TotalShares, .has TotalShares]
  ret : st.ret = 2

abbrev burn : Step → Prop := fun st => burn.Spec st

namespace burn_from
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def spender (st : Step) : Addr := st.call.argA "spender"
@[simp] def pre_Allowance_amount (st : Step) : Int :=
  st.pre (Allowance.amount (burn_from.«from» st) (burn_from.spender st))
@[simp] def pre_Allowance_expiration_ledger (st : Step) : Int :=
  st.pre (Allowance.expiration_ledger (burn_from.«from» st) (burn_from.spender st))
@[simp] def pre_has_Allowance (st : Step) : Int :=
  st.pre (.has (Allowance (burn_from.«from» st) (burn_from.spender st)))
@[simp] def key_Allowance_amount (st : Step) : Key :=
  Allowance.amount (burn_from.«from» st) (burn_from.spender st)
@[simp] def key_Allowance_expiration_ledger (st : Step) : Key :=
  Allowance.expiration_ledger (burn_from.«from» st) (burn_from.spender st)
@[simp] def key_Allowance (st : Step) : Key :=
  Allowance (burn_from.«from» st) (burn_from.spender st)
@[simp] def new_Allowance_amount (st : Step) : Int :=
  (if (burn_from.pre_has_Allowance st) = 1 then (if (st.call.env "sequence") > (burn_from.pre_Allowance_expiration_ledger st) then 0 else (burn_from.pre_Allowance_amount st)) else 0) - (burn_from.amount st)
@[simp] def new_Allowance_expiration_ledger (st : Step) : Int :=
  getOr0 st.pre (burn_from.key_Allowance_expiration_ledger st) (base := (burn_from.key_Allowance st))
@[simp] def s1 (st : Step) : Storage :=
  if (burn_from.amount st) ≠ 0 then (((st.pre).set (burn_from.key_Allowance_amount st) (burn_from.new_Allowance_amount st)).set (burn_from.key_Allowance_expiration_ledger st) (burn_from.new_Allowance_expiration_ledger st)).set (.has (burn_from.key_Allowance st)) 1 else st.pre
@[simp] def new_Balance (st : Step) : Int :=
  (getOr0 (burn_from.s1 st) (Balance (burn_from.«from» st))) - (burn_from.amount st)
@[simp] def s2 (st : Step) : Storage :=
  ((burn_from.s1 st).set (Balance (burn_from.«from» st)) (burn_from.new_Balance st)).set (.has (Balance (burn_from.«from» st))) 1
@[simp] def new_TotalShares (st : Step) : Int :=
  (getOr0 st.pre TotalShares) - (burn_from.amount st)
@[simp] def s3 (st : Step) : Storage :=
  ((burn_from.s2 st).set TotalShares (burn_from.new_TotalShares st)).set (.has TotalShares) 1
end burn_from

/-- `burn_from(spender: Address, from: Address, amount: i128)`: it succeeds exactly when `burn_from.Spec` holds.
    Its effects, in execution order:
    * `burn_from.s1`: write `burn_from.key_Allowance_amount st` := `burn_from.new_Allowance_amount st`, `burn_from.key_Allowance_expiration_ledger st` := `burn_from.new_Allowance_expiration_ledger st`, when `(burn_from.amount st) ≠ 0`
    * `burn_from.s2`: write `Balance (burn_from.«from» st)` := `burn_from.new_Balance st`
    * `burn_from.s3`: write `TotalShares` := `burn_from.new_TotalShares st`
-/
structure burn_from.Spec (st : Step) : Prop where
  fn : st.call.fn = "burn_from"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `burn_from.spender st` authorized the call (`require_auth`) -/
  auth_spender : (burn_from.spender st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (burn_from.amount st) > -1
  /-- the call panics unless this holds -/
  gate2 : (if (burn_from.pre_has_Allowance st) = 1 then (if (st.call.env "sequence") > (burn_from.pre_Allowance_expiration_ledger st) then 0 else (burn_from.pre_Allowance_amount st)) else 0) ≥ (burn_from.amount st)
  post : st.post = (burn_from.s3 st)
  writes : st.writes = [(burn_from.key_Allowance_amount st), (burn_from.key_Allowance_expiration_ledger st), .has (burn_from.key_Allowance st), (Balance (burn_from.«from» st)), .has (Balance (burn_from.«from» st)), TotalShares, .has TotalShares]
  ret : st.ret = 2

abbrev burn_from : Step → Prop := fun st => burn_from.Spec st

/-- `decimals()`: it succeeds exactly when `decimals.Spec` holds.
-/
structure decimals.Spec (st : Step) : Prop where
  fn : st.call.fn = "decimals"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the call panics unless this holds -/
  gate1 : (st.pre (.has METADATA)) = 1
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = 0

abbrev decimals : Step → Prop := fun st => decimals.Spec st

/-- `name()`: it succeeds exactly when `name.Spec` holds.
-/
structure name.Spec (st : Step) : Prop where
  fn : st.call.fn = "name"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the call panics unless this holds -/
  gate1 : (st.pre (.has METADATA)) = 1
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = 0

abbrev name : Step → Prop := fun st => name.Spec st

/-- `symbol()`: it succeeds exactly when `symbol.Spec` holds.
-/
structure symbol.Spec (st : Step) : Prop where
  fn : st.call.fn = "symbol"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the call panics unless this holds -/
  gate1 : (st.pre (.has METADATA)) = 1
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = 0

abbrev symbol : Step → Prop := fun st => symbol.Spec st

/-- the contract's entry points (each a `Step → Prop`; the constructor runs
    only at deployment, so it is not one of them). -/
def entries : List (Step → Prop) := [init, gulp, join_pool, exit_pool, swap_exact_amount_in, swap_exact_amount_out, dep_tokn_amt_in_get_lp_tokns_out, dep_lp_tokn_amt_out_get_tokn_in, wdr_tokn_amt_in_get_lp_tokns_out, wdr_tokn_amt_out_get_lp_tokns_in, set_controller, set_freeze_status, get_total_supply, get_controller, get_tokens, get_balance, get_normalized_weight, get_spot_price, get_swap_fee, get_spot_price_sans_fee, allowance, approve, balance, transfer, transfer_from, burn, burn_from, decimals, name, symbol]

/-- Keys in temporary storage: they can expire between calls. -/
def temporary : Key → Bool
  | .var "SwapFee" => true
  | .tup "Allowance" _ => true
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
