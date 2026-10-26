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

/-- the fee-adjusted constant-product invariant value `new_inv_a*new_inv_b`,
    the quantity the contract's `constant product` panic compares. -/
opaque invProduct : Storage → Int

/-- `__constructor(token_a: Address, token_b: Address)`
    effects (reconstructed, in program order):
      write storage.TokenA/19 := token_a
      write storage.TokenB/22 := token_b
      write storage.TotalShares/27 := 11
      write storage.ReserveA/31 := 11
      write storage.ReserveB/35 := 11
    guards (recovered panic/gate conditions):
      gate: token_a < token_b
-/
def __constructor : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := ((st.pre).set (.var "TokenA") (st.call.argA "token_a")).set (.has (.var "TokenA")) (1)
  let s2 := ((s1).set (.var "TokenB") (st.call.argA "token_b")).set (.has (.var "TokenB")) (1)
  let s3 := ((s2).set (.var "TotalShares") (11)).set (.has (.var "TotalShares")) (1)
  let s4 := ((s3).set (.var "ReserveA") (11)).set (.has (.var "ReserveA")) (1)
  let s5 := ((s4).set (.var "ReserveB") (11)).set (.has (.var "ReserveB")) (1)
  st.call.fn = "__constructor" ∧
  c ≠ pool ∧
  st.call.argA "token_a" < st.call.argA "token_b" ∧   -- gate
  st.post = s5 ∧
  st.writes = [.var "TokenA", .has (.var "TokenA"), .var "TokenB", .has (.var "TokenB"), .var "TotalShares", .has (.var "TotalShares"), .var "ReserveA", .has (.var "ReserveA"), .var "ReserveB", .has (.var "ReserveB")] ∧
  st.ret = 0

/-- `balance_shares(user: Address)`
    effects (reconstructed, in program order):
-/
def balance_shares : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "balance_shares" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre (.entry "Shares" (st.call.argA "user")))

/-- `deposit(to: Address, desired_a: i128, min_a: i128, desired_b: i128, min_b: i128)`
    effects (reconstructed, in program order):
      transfer "TokenA": to -> @pool : Select(@and(@not(@and(ICmp_EQ(storage.ReserveA/80, 0), ICmp_EQ(storage.ReserveB/84, 0))), ICmp_SGT(((desired_a * storage.ReserveB/84) / storage.ReserveA/80), desired_b)), ((desired_b * storage.ReserveA/80) / storage.ReserveB/84), desired_a)
      transfer "TokenB": to -> @pool : Select(@and(@not(@and(ICmp_EQ(storage.ReserveA/80, 0), ICmp_EQ(storage.ReserveB/84, 0))), ICmp_SGT(((desired_a * storage.ReserveB/84) / storage.ReserveA/80), desired_b)), desired_b, Select(@and(@not(@and(ICmp_EQ(storage.ReserveA/80, 0), ICmp_EQ(storage.ReserveB/84, 0))), @not(ICmp_SGT(((desired_a * storage.ReserveB/84) / storage.ReserveA/80), desired_b))), ((desired_a * storage.ReserveB/84) / storage.ReserveA/80), desired_b))
      write @map:Shares(to, @at(671)) := (@map:Shares(to, @at(653)) + (Select(@and(@not(Select(ICmp_SGT(storage.ReserveB/84, 0), ICmp_EQ(Select(ICmp_EQ(storage.ReserveA/80, 0), ICmp_EQ(storage.ReserveA/80, 0), LShr(storage.ReserveA/80, 63)), 0), 0)), @not(ICmp_EQ((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 0))), Select(@and(@and(@not(Select(ICmp_SGT(storage.ReserveB/84, 0), ICmp_EQ(Select(ICmp_EQ(storage.ReserveA/80, 0), ICmp_EQ(storage.ReserveA/80, 0), LShr(storage.ReserveA/80, 63)), 0), 0)), @not(ICmp_EQ((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 0))), ICmp_UGT((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 4611686018427387903)), big, Or(Shl(big, And((0 - LShr(llvm_ctlz_i64((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), -1), 1)), 4294967295)), LShr(big, LShr(llvm_ctlz_i64((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), -1), 1)))), Select(Select(ICmp_SGT(storage.ReserveB/84, 0), ICmp_EQ(Select(ICmp_EQ(storage.ReserveA/80, 0), ICmp_EQ(storage.ReserveA/80, 0), LShr(storage.ReserveA/80, 63)), 0), 0), Select(ICmp_SLT(((@call:balance(storage.TokenB/259, @vec(@pool), @at(258)) * storage.TotalShares/262) / storage.ReserveB/84), ((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * storage.TotalShares/262) / storage.ReserveA/80)), ((@call:balance(storage.TokenB/259, @vec(@pool), @at(258)) * storage.TotalShares/262) / storage.ReserveB/84), ((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * storage.TotalShares/262) / storage.ReserveA/80)), Select(@and(@not(Select(ICmp_SGT(storage.ReserveB/84, 0), ICmp_EQ(Select(ICmp_EQ(storage.ReserveA/80, 0), ICmp_EQ(storage.ReserveA/80, 0), LShr(storage.ReserveA/80, 63)), 0), 0)), ICmp_EQ((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 0), @not(ICmp_UGT((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 3))), ICmp_NE((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 0), Select(@and(@and(@not(Select(ICmp_SGT(storage.ReserveB/84, 0), ICmp_EQ(Select(ICmp_EQ(storage.ReserveA/80, 0), ICmp_EQ(storage.ReserveA/80, 0), LShr(storage.ReserveA/80, 63)), 0), 0)), ICmp_EQ((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 0), ICmp_UGT((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 3)), @not(ICmp_UGT(phi(Shl(1, LShr((64 - llvm_ctlz_i64((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), -1)), 1)), LShr((((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))) / cyc) + cyc), 1)), LShr((((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))) / cyc) + cyc), 1)))), phi(Shl(1, LShr((64 - llvm_ctlz_i64((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), -1)), 1)), LShr((((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))) / cyc) + cyc), 1)), LShr((((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))) / cyc) + cyc), 1))))) - storage.TotalShares/262))
      write storage.TotalShares/684 := (storage.TotalShares/657 + (Select(@and(@not(Select(ICmp_SGT(storage.ReserveB/84, 0), ICmp_EQ(Select(ICmp_EQ(storage.ReserveA/80, 0), ICmp_EQ(storage.ReserveA/80, 0), LShr(storage.ReserveA/80, 63)), 0), 0)), @not(ICmp_EQ((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 0))), Select(@and(@and(@not(Select(ICmp_SGT(storage.ReserveB/84, 0), ICmp_EQ(Select(ICmp_EQ(storage.ReserveA/80, 0), ICmp_EQ(storage.ReserveA/80, 0), LShr(storage.ReserveA/80, 63)), 0), 0)), @not(ICmp_EQ((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 0))), ICmp_UGT((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 4611686018427387903)), big, Or(Shl(big, And((0 - LShr(llvm_ctlz_i64((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), -1), 1)), 4294967295)), LShr(big, LShr(llvm_ctlz_i64((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), -1), 1)))), Select(Select(ICmp_SGT(storage.ReserveB/84, 0), ICmp_EQ(Select(ICmp_EQ(storage.ReserveA/80, 0), ICmp_EQ(storage.ReserveA/80, 0), LShr(storage.ReserveA/80, 63)), 0), 0), Select(ICmp_SLT(((@call:balance(storage.TokenB/259, @vec(@pool), @at(258)) * storage.TotalShares/262) / storage.ReserveB/84), ((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * storage.TotalShares/262) / storage.ReserveA/80)), ((@call:balance(storage.TokenB/259, @vec(@pool), @at(258)) * storage.TotalShares/262) / storage.ReserveB/84), ((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * storage.TotalShares/262) / storage.ReserveA/80)), Select(@and(@not(Select(ICmp_SGT(storage.ReserveB/84, 0), ICmp_EQ(Select(ICmp_EQ(storage.ReserveA/80, 0), ICmp_EQ(storage.ReserveA/80, 0), LShr(storage.ReserveA/80, 63)), 0), 0)), ICmp_EQ((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 0), @not(ICmp_UGT((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 3))), ICmp_NE((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 0), Select(@and(@and(@not(Select(ICmp_SGT(storage.ReserveB/84, 0), ICmp_EQ(Select(ICmp_EQ(storage.ReserveA/80, 0), ICmp_EQ(storage.ReserveA/80, 0), LShr(storage.ReserveA/80, 63)), 0), 0)), ICmp_EQ((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 0), ICmp_UGT((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), 3)), @not(ICmp_UGT(phi(Shl(1, LShr((64 - llvm_ctlz_i64((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), -1)), 1)), LShr((((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))) / cyc) + cyc), 1)), LShr((((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))) / cyc) + cyc), 1)))), phi(Shl(1, LShr((64 - llvm_ctlz_i64((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))), -1)), 1)), LShr((((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))) / cyc) + cyc), 1)), LShr((((@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))) / cyc) + cyc), 1))))) - storage.TotalShares/262))
      write storage.ReserveA/685 := @call:balance(storage.TokenA/255, @vec(@pool), @at(254))
      write storage.ReserveB/686 := @call:balance(storage.TokenB/259, @vec(@pool), @at(258))
    guards (recovered panic/gate conditions):
      auth: caller signed as `to` (require_auth)
      gate: ((desired_a * storage.ReserveB/84) / storage.ReserveA/80) ≥ min_b
      gate: desired_a ≥ ((desired_b * storage.ReserveA/80) / storage.ReserveB/84)
      gate: ((desired_b * storage.ReserveA/80) / storage.ReserveB/84) ≥ min_a
      gate: (@call:balance(storage.TokenA/255, @vec(@pool), @at(254)) * @call:balance(storage.TokenB/259, @vec(@pool), @at(258))) ≥ 0
-/
opaque deposit_e_g1 : Step → Int
opaque deposit_e_g2 : Step → Int
def deposit : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := xfer "TokenA" st.pre (st.call.argA "to") (pool) ((if (¬(((st.pre (.var "ReserveA")) = 0) ∧ ((st.pre (.var "ReserveB")) = 0))) ∧ ((Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) > st.call.arg "desired_b") then (Int.tdiv (st.call.arg "desired_b" * (st.pre (.var "ReserveA"))) (st.pre (.var "ReserveB"))) else st.call.arg "desired_a"))
  let s2 := xfer "TokenB" s1 (st.call.argA "to") (pool) ((if (¬(((st.pre (.var "ReserveA")) = 0) ∧ ((st.pre (.var "ReserveB")) = 0))) ∧ ((Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) > st.call.arg "desired_b") then st.call.arg "desired_b" else (if (¬(((st.pre (.var "ReserveA")) = 0) ∧ ((st.pre (.var "ReserveB")) = 0))) ∧ (¬((Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) > st.call.arg "desired_b")) then (Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) else st.call.arg "desired_b")))
  let s3 := ((s2).set (.entry "Shares" (st.call.argA "to")) (((s2 (.entry "Shares" (st.call.argA "to"))) + ((deposit_e_g1 st) - (s2 (.var "TotalShares")))))).set (.has (.entry "Shares" (st.call.argA "to"))) (1)
  let s4 := ((s3).set (.var "TotalShares") (((s2 (.var "TotalShares")) + ((deposit_e_g2 st) - (s2 (.var "TotalShares")))))).set (.has (.var "TotalShares")) (1)
  let s5 := ((s4).set (.var "ReserveA") ((bal "TokenA" s2 pool))).set (.has (.var "ReserveA")) (1)
  let s6 := ((s5).set (.var "ReserveB") ((bal "TokenB" s2 pool))).set (.has (.var "ReserveB")) (1)
  st.call.fn = "deposit" ∧
  c ≠ pool ∧
  c = st.call.argA "to" ∧   -- require_auth
  (Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) ≥ st.call.arg "min_b" ∧   -- gate
  st.call.arg "desired_a" ≥ (Int.tdiv (st.call.arg "desired_b" * (st.pre (.var "ReserveA"))) (st.pre (.var "ReserveB"))) ∧   -- gate
  (Int.tdiv (st.call.arg "desired_b" * (st.pre (.var "ReserveA"))) (st.pre (.var "ReserveB"))) ≥ st.call.arg "min_a" ∧   -- gate
  ((bal "TokenA" s2 pool) * (bal "TokenB" s2 pool)) ≥ 0 ∧   -- gate
  st.post = s6 ∧
  st.writes = [.entry "TokenA" (st.call.argA "to"), .entry "TokenA" (pool), .entry "TokenB" (st.call.argA "to"), .entry "TokenB" (pool), .entry "Shares" (st.call.argA "to"), .has (.entry "Shares" (st.call.argA "to")), .var "TotalShares", .has (.var "TotalShares"), .var "ReserveA", .has (.var "ReserveA"), .var "ReserveB", .has (.var "ReserveB")] ∧
  st.ret = 0

/-- `get_rsrvs()`
    transfers: (none recovered)
-/
opaque get_rsrvs_ret : Step → Int
def get_rsrvs : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "get_rsrvs" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = get_rsrvs_ret st

/-- `swap(to: Address, buy_a: bool, out: i128, in_max: i128)`
    effects (reconstructed, in program order):
      transfer (if ¬(st.call.arg "buy_a" = 0) then "TokenB" else "TokenA"): to -> @pool : ((((Select(@isfalse(buy_a), storage.ReserveA/56, storage.ReserveB/60) * out) * 1000) / ((Select(@isfalse(buy_a), storage.ReserveB/60, storage.ReserveA/56) - out) * 997)) + 1)
      transfer (if st.call.arg "buy_a" = 0 then "TokenB" else "TokenA"): @pool -> to : out
      write storage.ReserveA/328 := (@call:balance(storage.TokenA/194, @vec(@pool), @at(193)) - Select(@not(@isfalse(buy_a)), out, 0))
      write storage.ReserveB/329 := (@call:balance(storage.TokenB/198, @vec(@pool), @at(197)) - Select(@not(@isfalse(buy_a)), 0, out))
    guards (recovered panic/gate conditions):
      auth: caller signed as `to` (require_auth)
      gate: Select(@isfalse(buy_a), storage.ReserveB/60, storage.ReserveA/56) ≥ out
      gate: ((((Select(@isfalse(buy_a), storage.ReserveA/56, storage.ReserveB/60) * out) * 1000) / ((Select(@isfalse(buy_a), storage.ReserveB/60, storage.ReserveA/56) - out) * 997)) + 1) ≤ in_max
      gate: (((1000 * storage.ReserveA/56) + Select(@not(ICmp_SLE(((@call:balance(storage.TokenA/194, @vec(@pool), @at(193)) - storage.ReserveA/56) - Select(@not(@isfalse(buy_a)), out, 0)), 0)), (997 * ((@call:balance(storage.TokenA/194, @vec(@pool), @at(193)) - storage.ReserveA/56) - Select(@not(@isfalse(buy_a)), out, 0))), (1000 * ((@call:balance(storage.TokenA/194, @vec(@pool), @at(193)) - storage.ReserveA/56) - Select(@not(@isfalse(buy_a)), out, 0))))) * ((1000 * storage.ReserveB/60) + Select(@not(ICmp_SLE(((@call:balance(storage.TokenB/198, @vec(@pool), @at(197)) - storage.ReserveB/60) - Select(@not(@isfalse(buy_a)), 0, out)), 0)), (997 * ((@call:balance(storage.TokenB/198, @vec(@pool), @at(197)) - storage.ReserveB/60) - Select(@not(@isfalse(buy_a)), 0, out))), (1000 * ((@call:balance(storage.TokenB/198, @vec(@pool), @at(197)) - storage.ReserveB/60) - Select(@not(@isfalse(buy_a)), 0, out)))))) ≥ ((storage.ReserveA/56 * 1000) * (storage.ReserveB/60 * 1000))
-/
def swap : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := xfer (if ¬(st.call.arg "buy_a" = 0) then "TokenB" else "TokenA") st.pre (st.call.argA "to") (pool) (((Int.tdiv (((if st.call.arg "buy_a" = 0 then (st.pre (.var "ReserveA")) else (st.pre (.var "ReserveB"))) * st.call.arg "out") * 1000) (((if st.call.arg "buy_a" = 0 then (st.pre (.var "ReserveB")) else (st.pre (.var "ReserveA"))) - st.call.arg "out") * 997)) + 1))
  let s2 := xfer (if st.call.arg "buy_a" = 0 then "TokenB" else "TokenA") s1 (pool) (st.call.argA "to") (st.call.arg "out")
  let s3 := ((s2).set (.var "ReserveA") (((bal "TokenA" s1 pool) - (if ¬(st.call.arg "buy_a" = 0) then st.call.arg "out" else 0)))).set (.has (.var "ReserveA")) (1)
  let s4 := ((s3).set (.var "ReserveB") (((bal "TokenB" s1 pool) - (if ¬(st.call.arg "buy_a" = 0) then 0 else st.call.arg "out")))).set (.has (.var "ReserveB")) (1)
  st.call.fn = "swap" ∧
  c ≠ pool ∧
  c = st.call.argA "to" ∧   -- require_auth
  invProduct st.pre ≤ invProduct st.post ∧   -- constant-product trap
  (if st.call.arg "buy_a" = 0 then (st.pre (.var "ReserveB")) else (st.pre (.var "ReserveA"))) ≥ st.call.arg "out" ∧   -- gate
  ((Int.tdiv (((if st.call.arg "buy_a" = 0 then (st.pre (.var "ReserveA")) else (st.pre (.var "ReserveB"))) * st.call.arg "out") * 1000) (((if st.call.arg "buy_a" = 0 then (st.pre (.var "ReserveB")) else (st.pre (.var "ReserveA"))) - st.call.arg "out") * 997)) + 1) ≤ st.call.arg "in_max" ∧   -- gate
  (((1000 * (st.pre (.var "ReserveA"))) + (if ¬((((bal "TokenA" s1 pool) - (st.pre (.var "ReserveA"))) - (if ¬(st.call.arg "buy_a" = 0) then st.call.arg "out" else 0)) ≤ 0) then (997 * (((bal "TokenA" s1 pool) - (st.pre (.var "ReserveA"))) - (if ¬(st.call.arg "buy_a" = 0) then st.call.arg "out" else 0))) else (1000 * (((bal "TokenA" s1 pool) - (st.pre (.var "ReserveA"))) - (if ¬(st.call.arg "buy_a" = 0) then st.call.arg "out" else 0))))) * ((1000 * (st.pre (.var "ReserveB"))) + (if ¬((((bal "TokenB" s1 pool) - (st.pre (.var "ReserveB"))) - (if ¬(st.call.arg "buy_a" = 0) then 0 else st.call.arg "out")) ≤ 0) then (997 * (((bal "TokenB" s1 pool) - (st.pre (.var "ReserveB"))) - (if ¬(st.call.arg "buy_a" = 0) then 0 else st.call.arg "out"))) else (1000 * (((bal "TokenB" s1 pool) - (st.pre (.var "ReserveB"))) - (if ¬(st.call.arg "buy_a" = 0) then 0 else st.call.arg "out")))))) ≥ (((st.pre (.var "ReserveA")) * 1000) * ((st.pre (.var "ReserveB")) * 1000)) ∧   -- gate
  st.post = s4 ∧
  st.writes = [.entry (if ¬(st.call.arg "buy_a" = 0) then "TokenB" else "TokenA") (st.call.argA "to"), .entry (if ¬(st.call.arg "buy_a" = 0) then "TokenB" else "TokenA") (pool), .entry (if st.call.arg "buy_a" = 0 then "TokenB" else "TokenA") (pool), .entry (if st.call.arg "buy_a" = 0 then "TokenB" else "TokenA") (st.call.argA "to"), .var "ReserveA", .has (.var "ReserveA"), .var "ReserveB", .has (.var "ReserveB")] ∧
  st.ret = 0

-- VALUE INVARIANT: a `swap` never decreases the constant product.
theorem swap_keeps_product (st : Step) (h : swap st) :
    invProduct st.pre ≤ invProduct st.post := h.2.2.2.1

/-- `withdraw(to: Address, share_amount: i128, min_a: i128, min_b: i128)`
    effects (reconstructed, in program order):
      write @map:Shares(to, @at(219)) := (@map:Shares(to, @at(197)) - share_amount)
      write storage.TotalShares/231 := (storage.TotalShares/208 - share_amount)
      transfer "TokenA": @pool -> to : ((@call:balance(storage.TokenA/75, @vec(@pool), @at(74)) * share_amount) / storage.TotalShares/88)
      transfer "TokenB": @pool -> to : ((@call:balance(storage.TokenB/85, @vec(@pool), @at(84)) * share_amount) / storage.TotalShares/88)
      write storage.ReserveA/250 := (@call:balance(storage.TokenA/75, @vec(@pool), @at(74)) - ((@call:balance(storage.TokenA/75, @vec(@pool), @at(74)) * share_amount) / storage.TotalShares/88))
      write storage.ReserveB/261 := (@call:balance(storage.TokenB/85, @vec(@pool), @at(84)) - ((@call:balance(storage.TokenB/85, @vec(@pool), @at(84)) * share_amount) / storage.TotalShares/88))
    guards (recovered panic/gate conditions):
      auth: caller signed as `to` (require_auth)
      gate: @map:Shares(to, @at(62)) ≥ share_amount
      gate: ((@call:balance(storage.TokenA/75, @vec(@pool), @at(74)) * share_amount) / storage.TotalShares/88) ≥ min_a
      gate: ((@call:balance(storage.TokenB/85, @vec(@pool), @at(84)) * share_amount) / storage.TotalShares/88) ≥ min_b
      gate: @map:Shares(to, @at(197)) ≥ share_amount
-/
opaque withdraw_ret : Step → Int
def withdraw : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := ((st.pre).set (.entry "Shares" (st.call.argA "to")) (((st.pre (.entry "Shares" (st.call.argA "to"))) - st.call.arg "share_amount"))).set (.has (.entry "Shares" (st.call.argA "to"))) (1)
  let s2 := ((s1).set (.var "TotalShares") (((st.pre (.var "TotalShares")) - st.call.arg "share_amount"))).set (.has (.var "TotalShares")) (1)
  let s3 := xfer "TokenA" s2 (pool) (st.call.argA "to") ((Int.tdiv ((bal "TokenA" st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares"))))
  let s4 := xfer "TokenB" s3 (pool) (st.call.argA "to") ((Int.tdiv ((bal "TokenB" st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares"))))
  let s5 := ((s4).set (.var "ReserveA") (((bal "TokenA" st.pre pool) - (Int.tdiv ((bal "TokenA" st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares")))))).set (.has (.var "ReserveA")) (1)
  let s6 := ((s5).set (.var "ReserveB") (((bal "TokenB" st.pre pool) - (Int.tdiv ((bal "TokenB" st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares")))))).set (.has (.var "ReserveB")) (1)
  st.call.fn = "withdraw" ∧
  c ≠ pool ∧
  c = st.call.argA "to" ∧   -- require_auth
  (st.pre (.entry "Shares" (st.call.argA "to"))) ≥ st.call.arg "share_amount" ∧   -- gate
  (Int.tdiv ((bal "TokenA" st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares"))) ≥ st.call.arg "min_a" ∧   -- gate
  (Int.tdiv ((bal "TokenB" st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares"))) ≥ st.call.arg "min_b" ∧   -- gate
  (st.pre (.entry "Shares" (st.call.argA "to"))) ≥ st.call.arg "share_amount" ∧   -- gate
  st.post = s6 ∧
  st.writes = [.entry "Shares" (st.call.argA "to"), .has (.entry "Shares" (st.call.argA "to")), .var "TotalShares", .has (.var "TotalShares"), .entry "TokenA" (pool), .entry "TokenA" (st.call.argA "to"), .entry "TokenB" (pool), .entry "TokenB" (st.call.argA "to"), .var "ReserveA", .has (.var "ReserveA"), .var "ReserveB", .has (.var "ReserveB")] ∧
  st.ret = withdraw_ret st

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [__constructor, balance_shares, deposit, get_rsrvs, swap, withdraw]

-- VALUE INVARIANT (inductive): across any sequence of `swap` calls the
-- constant product never falls below its start -- no draining by swapping.
inductive Reach : Storage → Storage → Prop where
  | refl (s) : Reach s s
  | step {s} (st : Step) : Reach s st.pre → swap st → Reach s st.post

theorem no_drain (s t : Storage) (r : Reach s t) : invProduct s ≤ invProduct t := by
  induction r with
  | refl => omega
  | step st _ h ih => have hp := swap_keeps_product st h; omega

end Contract
