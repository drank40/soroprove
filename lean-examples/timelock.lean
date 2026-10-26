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

/-- `claim(claimant: Address)`
    effects, in execution order:
      transfer @field:token(storage.Balance/2): @pool -> claimant : @field:amount(storage.Balance/2)
      write storage.Balance/12 := @del
    conditions to succeed:
      require_auth claimant
      gate: @has(storage.Balance/1) = 1
      gate: ¬Select(ICmp_EQ(And(ICmp_UGT(buf_symbol_index_in_linear_memory, 4294967295), 1), 0), ICmp_ULT(Select(@not(ICmp_EQ(And((@len(@field:kind(@field:time_bound(storage.Balance/2))) + 4294967295), 4294967295), 0)), 0, Select(@and(ICmp_EQ(And((@len(@field:kind(@field:time_bound(storage.Balance/2))) + 4294967295), 4294967295), 0), @and(ICmp_NE(And(@field:timestamp(@field:time_bound(storage.Balance/2)), 255), 64), ICmp_NE(And(@field:timestamp(@field:time_bound(storage.Balance/2)), 255), 6))), 0, @field:timestamp(@field:time_bound(storage.Balance/2)))), @env:timestamp), ICmp_UGT(Select(@not(ICmp_EQ(And((@len(@field:kind(@field:time_bound(storage.Balance/2))) + 4294967295), 4294967295), 0)), 0, Select(@and(ICmp_EQ(And((@len(@field:kind(@field:time_bound(storage.Balance/2))) + 4294967295), 4294967295), 0), @and(ICmp_NE(And(@field:timestamp(@field:time_bound(storage.Balance/2)), 255), 64), ICmp_NE(And(@field:timestamp(@field:time_bound(storage.Balance/2)), 255), 6))), 0, @field:timestamp(@field:time_bound(storage.Balance/2)))), @env:timestamp))
-/
def claim : Step → Prop := fun st => ∃ u : Unk,
  let c := st.call.caller
  let pool := st.call.self
  let s1 := xfer ((st.pre (.fld (.var "Balance") "token"))) st.pre (pool) (st.call.argA "claimant") ((st.pre (.fld (.var "Balance") "amount")))
  let s2 := (s1).set (.has (.var "Balance")) (0)
  st.call.fn = "claim" ∧
  c ≠ pool ∧
  st.call.argA "claimant" ∈ st.call.signers ∧   -- require_auth claimant
  (st.pre (.has (.var "Balance"))) = 1 ∧   -- gate
  ¬(if (u.g 1) = 0 then (if ¬((u.g 2) = 0) then 0 else (if ((u.g 3) = 0) ∧ (((u.g 4) ≠ 64) ∧ ((u.g 5) ≠ 6)) then 0 else (st.pre (.fld (.fld (.var "Balance") "time_bound") "timestamp")))) < (st.call.env "timestamp") else (if ¬((u.g 6) = 0) then 0 else (if ((u.g 7) = 0) ∧ (((u.g 8) ≠ 64) ∧ ((u.g 9) ≠ 6)) then 0 else (st.pre (.fld (.fld (.var "Balance") "time_bound") "timestamp")))) > (st.call.env "timestamp")) ∧   -- gate
  st.post = s2 ∧
  st.writes = [.bal ((st.pre (.fld (.var "Balance") "token"))) (pool), .bal ((st.pre (.fld (.var "Balance") "token"))) (st.call.argA "claimant"), .has (.var "Balance")] ∧
  st.ret = 2

/-- `deposit(from: Address, token: Address, amount: i128, claimants: Vec<Address>, time_bound: TimeBound)`
    effects, in execution order:
      transfer token: from -> @pool : amount
      write storage.Balance/18 := @struct:amount,claimants,time_bound,token(amount, claimants, @struct:kind,timestamp(@vec(Select(@not(ICmp_EQ(And(ICmp_UGT(buf_symbol_index_in_linear_memory, 4294967295), 1), 0)), phi(buf_symbol_new_from_linear_memory, 14, Or(And(phi(1, And((@load(phi(And((cyc + 1), 4294967295), 1048621)) + 4294967250), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048621)) + 4294967243), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048621)) + 4294967237), 4294967295)), 255), Shl(phi(cyc, 0), 6))), phi(buf_symbol_new_from_linear_memory, 14, Or(And(phi(1, And((@load(phi(And((cyc + 1), 4294967295), 1048615)) + 4294967250), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048615)) + 4294967243), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048615)) + 4294967237), 4294967295)), 255), Shl(phi(cyc, 0), 6))))), Select(@not(ICmp_EQ(And((@len(@field:kind(time_bound)) + 4294967295), 4294967295), 0)), 1, @field:timestamp(time_bound))), token)
      write storage.Init/19 := 2
    conditions to succeed:
      require_auth from
      gate: @len(claimants) < 11
      gate: @has(storage.Init/13) ≠ 1
-/
def deposit : Step → Prop := fun st => ∃ u : Unk,
  let c := st.call.caller
  let pool := st.call.self
  let s1 := xfer (st.call.argA "token") st.pre (st.call.argA "from") (pool) (st.call.arg "amount")
  let s2 := ((((((s1).set (.fld (.var "Balance") "amount") (st.call.arg "amount")).set (.fld (.var "Balance") "claimants") (st.call.arg "claimants")).set (.fld (.fld (.var "Balance") "time_bound") "kind") ((u.i 1))).set (.fld (.fld (.var "Balance") "time_bound") "timestamp") ((if ¬((u.i 2) = 0) then 1 else st.call.arg "time_bound.timestamp"))).set (.fld (.var "Balance") "token") (st.call.argA "token")).set (.has (.var "Balance")) (1)
  let s3 := ((s2).set (.var "Init") (2)).set (.has (.var "Init")) (1)
  st.call.fn = "deposit" ∧
  c ≠ pool ∧
  st.call.argA "from" ∈ st.call.signers ∧   -- require_auth from
  st.call.arg "claimants.len" < 11 ∧   -- gate
  (st.pre (.has (.var "Init"))) ≠ 1 ∧   -- gate
  st.post = s3 ∧
  st.writes = [.bal (st.call.argA "token") (st.call.argA "from"), .bal (st.call.argA "token") (pool), .fld (.var "Balance") "amount", .fld (.var "Balance") "claimants", .fld (.fld (.var "Balance") "time_bound") "kind", .fld (.fld (.var "Balance") "time_bound") "timestamp", .fld (.var "Balance") "token", .has (.var "Balance"), .var "Init", .has (.var "Init")] ∧
  st.ret = 2

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [claim, deposit]

end Contract
