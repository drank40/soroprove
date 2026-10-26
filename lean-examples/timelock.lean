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

@[simp] def Balance : Key := .var "Balance"
@[simp] def Balance.token : Key := .fld Balance "token"
@[simp] def Balance.amount : Key := .fld Balance "amount"
@[simp] def Balance.time_bound : Key := .fld Balance "time_bound"
@[simp] def Balance.time_bound.timestamp : Key := .fld Balance.time_bound "timestamp"
@[simp] def Balance.claimants : Key := .fld Balance "claimants"
@[simp] def Balance.time_bound.kind : Key := .fld Balance.time_bound "kind"
@[simp] def Init : Key := .var "Init"

namespace claim
@[simp] def claimant (st : Step) : Addr := st.call.argA "claimant"
@[simp] def amt1 (st : Step) : Int :=
  (st.pre Balance.amount)
@[simp] def s1 (st : Step) : Storage :=
  xfer (st.pre Balance.token) st.pre (pool st) (claim.claimant st) (claim.amt1 st)
@[simp] def s2 (st : Step) : Storage :=
  (claim.s1 st).set (.has Balance) 0
end claim

/-- `claim(claimant: Address)`
    effects, in execution order (states `claim.s1`, `claim.s2`, …; amounts `claim.amt1`, …):
      transfer @field:token(storage.Balance/2): @pool -> claimant : @field:amount(storage.Balance/2)
      write storage.Balance/12 := @del
    conditions to succeed:
      require_auth claimant
      gate: @has(storage.Balance/1) = 1
      gate: ¬Select(ICmp_EQ(And(ICmp_UGT(buf_symbol_index_in_linear_memory, 4294967295), 1), 0), ICmp_ULT(Select(@not(ICmp_EQ(And((@len(@field:kind(@field:time_bound(storage.Balance/2))) + 4294967295), 4294967295), 0)), 0, Select(@and(ICmp_EQ(And((@len(@field:kind(@field:time_bound(storage.Balance/2))) + 4294967295), 4294967295), 0), @and(ICmp_NE(And(@field:timestamp(@field:time_bound(storage.Balance/2)), 255), 64), ICmp_NE(And(@field:timestamp(@field:time_bound(storage.Balance/2)), 255), 6))), 0, @field:timestamp(@field:time_bound(storage.Balance/2)))), @env:timestamp), ICmp_UGT(Select(@not(ICmp_EQ(And((@len(@field:kind(@field:time_bound(storage.Balance/2))) + 4294967295), 4294967295), 0)), 0, Select(@and(ICmp_EQ(And((@len(@field:kind(@field:time_bound(storage.Balance/2))) + 4294967295), 4294967295), 0), @and(ICmp_NE(And(@field:timestamp(@field:time_bound(storage.Balance/2)), 255), 64), ICmp_NE(And(@field:timestamp(@field:time_bound(storage.Balance/2)), 255), 6))), 0, @field:timestamp(@field:time_bound(storage.Balance/2)))), @env:timestamp))
-/
def claim : Step → Prop := fun st => ∃ u : Unk,
  st.call.fn = "claim" ∧
  st.call.caller ≠ pool st ∧
  (claim.claimant st) ∈ st.call.signers ∧   -- require_auth claimant
  (st.pre (.has Balance)) = 1 ∧   -- gate
  ¬(if (u.g 1) = 0 then (if ¬((u.g 2) = 0) then 0 else (if ((u.g 3) = 0) ∧ (((u.g 4) ≠ 64) ∧ ((u.g 5) ≠ 6)) then 0 else (st.pre Balance.time_bound.timestamp))) < (st.call.env "timestamp") else (if ¬((u.g 6) = 0) then 0 else (if ((u.g 7) = 0) ∧ (((u.g 8) ≠ 64) ∧ ((u.g 9) ≠ 6)) then 0 else (st.pre Balance.time_bound.timestamp))) > (st.call.env "timestamp")) ∧   -- gate
  st.post = (claim.s2 st) ∧
  st.writes = [.bal (st.pre Balance.token) (pool st), .bal (st.pre Balance.token) (claim.claimant st), .has Balance] ∧
  st.ret = 2

namespace deposit
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def claimants (st : Step) : Int := st.call.arg "claimants"
@[simp] def claimants.len (st : Step) : Int := st.call.arg "claimants.len"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def time_bound.timestamp (st : Step) : Int := st.call.arg "time_bound.timestamp"
@[simp] def token (st : Step) : Addr := st.call.argA "token"
@[simp] def amt1 (st : Step) : Int :=
  (deposit.amount st)
@[simp] def s1 (st : Step) : Storage :=
  xfer (deposit.token st) st.pre (deposit.«from» st) (pool st) (deposit.amt1 st)
@[simp] def s2 (st : Step) (u : Unk) : Storage :=
  ((((((deposit.s1 st).set Balance.amount (deposit.amount st)).set Balance.claimants (deposit.claimants st)).set Balance.time_bound.kind (u.i 1)).set Balance.time_bound.timestamp (if ¬((u.i 2) = 0) then 1 else (deposit.time_bound.timestamp st))).set Balance.token (deposit.token st)).set (.has Balance) 1
@[simp] def s3 (st : Step) (u : Unk) : Storage :=
  ((deposit.s2 st u).set Init 2).set (.has Init) 1
end deposit

/-- `deposit(from: Address, token: Address, amount: i128, claimants: Vec<Address>, time_bound: TimeBound)`
    effects, in execution order (states `deposit.s1`, `deposit.s2`, …; amounts `deposit.amt1`, …):
      transfer token: from -> @pool : amount
      write storage.Balance/18 := @struct:amount,claimants,time_bound,token(amount, claimants, @struct:kind,timestamp(@vec(Select(@not(ICmp_EQ(And(ICmp_UGT(buf_symbol_index_in_linear_memory, 4294967295), 1), 0)), phi(buf_symbol_new_from_linear_memory, 14, Or(And(phi(1, And((@load(phi(And((cyc + 1), 4294967295), 1048621)) + 4294967250), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048621)) + 4294967243), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048621)) + 4294967237), 4294967295)), 255), Shl(phi(cyc, 0), 6))), phi(buf_symbol_new_from_linear_memory, 14, Or(And(phi(1, And((@load(phi(And((cyc + 1), 4294967295), 1048615)) + 4294967250), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048615)) + 4294967243), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048615)) + 4294967237), 4294967295)), 255), Shl(phi(cyc, 0), 6))))), Select(@not(ICmp_EQ(And((@len(@field:kind(time_bound)) + 4294967295), 4294967295), 0)), 1, @field:timestamp(time_bound))), token)
      write storage.Init/19 := 2
    conditions to succeed:
      require_auth from
      gate: @len(claimants) < 11
      gate: @has(storage.Init/13) ≠ 1
-/
def deposit : Step → Prop := fun st => ∃ u : Unk,
  st.call.fn = "deposit" ∧
  st.call.caller ≠ pool st ∧
  (deposit.«from» st) ∈ st.call.signers ∧   -- require_auth from
  (deposit.claimants.len st) < 11 ∧   -- gate
  (st.pre (.has Init)) ≠ 1 ∧   -- gate
  st.post = (deposit.s3 st u) ∧
  st.writes = [.bal (deposit.token st) (deposit.«from» st), .bal (deposit.token st) (pool st), Balance.amount, Balance.claimants, Balance.time_bound.kind, Balance.time_bound.timestamp, Balance.token, .has Balance, Init, .has Init] ∧
  st.ret = 2

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [claim, deposit]

end Contract
