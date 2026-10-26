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

/-- `claim(claimant: Address)`
    effects (reconstructed, in program order):
      transfer "Balance.token": @pool -> claimant : @field:amount(storage.Balance/15)
      write storage.Balance/101 := @del
    guards (recovered panic/gate conditions):
      auth: caller signed as `claimant` (require_auth)
      gate: @has(storage.Balance/11) = 1
      gate: ¬Select(ICmp_EQ(And(Select(@not(ICmp_EQ(And(@field:time_bound(storage.Balance/15), 255), 76)), 2, Select(@and(ICmp_EQ(And(@field:time_bound(storage.Balance/15), 255), 76), @not(ICmp_EQ(And(@field:kind(@field:time_bound(storage.Balance/15)), 255), 75))), 2, Select(@and(@and(ICmp_EQ(And(@field:time_bound(storage.Balance/15), 255), 76), ICmp_EQ(And(@field:kind(@field:time_bound(storage.Balance/15)), 255), 75)), ICmp_ULT(@len(@field:kind(@field:time_bound(storage.Balance/15))), 4294967296)), 2, Select(@and(@and(ICmp_EQ(And(@field:time_bound(storage.Balance/15), 255), 76), ICmp_EQ(And(@field:kind(@field:time_bound(storage.Balance/15)), 255), 75), @not(ICmp_ULT(@len(@field:kind(@field:time_bound(storage.Balance/15))), 4294967296))), @and(ICmp_NE(@field:kind(@field:time_bound(storage.Balance/15))[4], 74), ICmp_NE(@field:kind(@field:time_bound(storage.Balance/15))[4], 14))), 2, Select(@and(@and(ICmp_EQ(And(@field:time_bound(storage.Balance/15), 255), 76), ICmp_EQ(And(@field:kind(@field:time_bound(storage.Balance/15)), 255), 75), @not(ICmp_ULT(@len(@field:kind(@field:time_bound(storage.Balance/15))), 4294967296)), @or(ICmp_EQ(@field:kind(@field:time_bound(storage.Balance/15))[4], 74), ICmp_EQ(@field:kind(@field:time_bound(storage.Balance/15))[4], 14))), ICmp_UGT(buf_symbol_index_in_linear_memory, 8589934591)), 2, Select(@or(@and(ICmp_EQ(And(@field:time_bound(storage.Balance/15), 255), 76), ICmp_EQ(And(@field:kind(@field:time_bound(storage.Balance/15)), 255), 75), @not(ICmp_ULT(@len(@field:kind(@field:time_bound(storage.Balance/15))), 4294967296)), @or(ICmp_EQ(@field:kind(@field:time_bound(storage.Balance/15))[4], 74), ICmp_EQ(@field:kind(@field:time_bound(storage.Balance/15))[4], 14)), @not(ICmp_UGT(buf_symbol_index_in_linear_memory, 8589934591)), ICmp_EQ(And((@len(@field:kind(@field:time_bound(storage.Balance/15))) + 4294967295), 4294967295), 0), ICmp_EQ(@field:timestamp(@field:time_bound(storage.Balance/15)), 64)), @and(ICmp_EQ(And(@field:time_bound(storage.Balance/15), 255), 76), ICmp_EQ(And(@field:kind(@field:time_bound(storage.Balance/15)), 255), 75), @not(ICmp_ULT(@len(@field:kind(@field:time_bound(storage.Balance/15))), 4294967296)), @or(ICmp_EQ(@field:kind(@field:time_bound(storage.Balance/15))[4], 74), ICmp_EQ(@field:kind(@field:time_bound(storage.Balance/15))[4], 14)), @not(ICmp_UGT(buf_symbol_index_in_linear_memory, 8589934591)), ICmp_EQ(And((@len(@field:kind(@field:time_bound(storage.Balance/15))) + 4294967295), 4294967295), 0), ICmp_EQ(@field:timestamp(@field:time_bound(storage.Balance/15)), 6))), ICmp_UGT(buf_symbol_index_in_linear_memory, 4294967295), 2)))))), 1), 0), ICmp_ULT(@field:timestamp(@field:time_bound(storage.Balance/15)), @env:timestamp), ICmp_UGT(@field:timestamp(@field:time_bound(storage.Balance/15)), @env:timestamp))
-/
opaque claim_g1 : Step → Int
def claim : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := xfer "Balance.token" st.pre (pool) (st.call.argA "claimant") ((st.pre (.fld (.var "Balance") "amount")))
  let s2 := ((s1).set (.var "Balance") (0)).set (.has (.var "Balance")) (0)
  st.call.fn = "claim" ∧
  c ≠ pool ∧
  c = st.call.argA "claimant" ∧   -- require_auth
  (st.pre (.has (.var "Balance"))) = 1 ∧   -- gate
  ¬(if (claim_g1 st) = 0 then (st.pre (.fld (.fld (.var "Balance") "time_bound") "timestamp")) < (st.call.env "timestamp") else (st.pre (.fld (.fld (.var "Balance") "time_bound") "timestamp")) > (st.call.env "timestamp")) ∧   -- gate
  st.post = s2 ∧
  st.writes = [.entry "Balance.token" (pool), .entry "Balance.token" (st.call.argA "claimant"), .var "Balance", .has (.var "Balance")] ∧
  st.ret = 0

/-- `deposit(from: Address, token: Address, amount: i128, claimants: Vec<Address>, time_bound: TimeBound)`
    effects (reconstructed, in program order):
      transfer (toString (st.call.argA "token")): from -> @pool : amount
      write storage.Balance/143 := @struct:amount,claimants,time_bound,token(amount, claimants, @struct:kind,timestamp(@vec(phi(phi(buf_symbol_new_from_linear_memory, 14, Or(And(phi(1, And((@load(phi(And((cyc + 1), 4294967295), 1048621)) + 4294967250), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048621)) + 4294967243), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048621)) + 4294967237), 4294967295)), 255), Shl(cyc, 6))), phi(buf_symbol_new_from_linear_memory, 14, Or(And(phi(1, And((@load(phi(And((cyc + 1), 4294967295), 1048615)) + 4294967250), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048615)) + 4294967243), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048615)) + 4294967237), 4294967295)), 255), Shl(cyc, 6))))), @field:timestamp(time_bound)), token)
      write storage.Init/147 := 2
    guards (recovered panic/gate conditions):
      auth: caller signed as `from` (require_auth)
      gate: @len(claimants) < 11
      gate: @has(storage.Init/51) ≠ 1
-/
opaque deposit_e_g1 : Step → Int
def deposit : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := xfer (toString (st.call.argA "token")) st.pre (st.call.argA "from") (pool) (st.call.arg "amount")
  let s2 := ((((((s1).set (.fld (.var "Balance") "amount") (st.call.arg "amount")).set (.fld (.var "Balance") "claimants") (st.call.arg "claimants")).set (.fld (.fld (.var "Balance") "time_bound") "kind") ((deposit_e_g1 st))).set (.fld (.fld (.var "Balance") "time_bound") "timestamp") (st.call.arg "time_bound.timestamp")).set (.fld (.var "Balance") "token") (st.call.argA "token")).set (.has (.var "Balance")) (1)
  let s3 := ((s2).set (.var "Init") (2)).set (.has (.var "Init")) (1)
  st.call.fn = "deposit" ∧
  c ≠ pool ∧
  c = st.call.argA "from" ∧   -- require_auth
  st.call.arg "claimants.len" < 11 ∧   -- gate
  (st.pre (.has (.var "Init"))) ≠ 1 ∧   -- gate
  st.post = s3 ∧
  st.writes = [.entry (toString (st.call.argA "token")) (st.call.argA "from"), .entry (toString (st.call.argA "token")) (pool), .fld (.var "Balance") "amount", .fld (.var "Balance") "claimants", .fld (.fld (.var "Balance") "time_bound") "kind", .fld (.fld (.var "Balance") "time_bound") "timestamp", .fld (.var "Balance") "token", .has (.var "Balance"), .var "Init", .has (.var "Init")] ∧
  st.ret = 0

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [claim, deposit]

end Contract
