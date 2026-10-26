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

/-- `swap(a: Address, b: Address, token_a: Address, token_b: Address, amount_a: i128, min_b_for_a: i128, amount_b: i128, min_a_for_b: i128)`
    effects (reconstructed, in program order):
      transfer (toString (st.call.argA "token_a")): a -> @pool : amount_a
      transfer (toString (st.call.argA "token_a")): @pool -> b : min_a_for_b
      transfer (toString (st.call.argA "token_a")): @pool -> a : (amount_a - min_a_for_b)
      transfer (toString (st.call.argA "token_b")): b -> @pool : amount_b
      transfer (toString (st.call.argA "token_b")): @pool -> a : min_b_for_a
      transfer (toString (st.call.argA "token_b")): @pool -> b : (amount_b - min_b_for_a)
    guards (recovered panic/gate conditions):
      auth: caller signed as `a` (require_auth)
      auth: `b` also authorized the call (require_auth)
      gate: min_b_for_a ≤ amount_b
      gate: amount_a ≥ min_a_for_b
-/
def swap : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := xfer (toString (st.call.argA "token_a")) st.pre (st.call.argA "a") (pool) (st.call.arg "amount_a")
  let s2 := xfer (toString (st.call.argA "token_a")) s1 (pool) (st.call.argA "b") (st.call.arg "min_a_for_b")
  let s3 := xfer (toString (st.call.argA "token_a")) s2 (pool) (st.call.argA "a") ((st.call.arg "amount_a" - st.call.arg "min_a_for_b"))
  let s4 := xfer (toString (st.call.argA "token_b")) s3 (st.call.argA "b") (pool) (st.call.arg "amount_b")
  let s5 := xfer (toString (st.call.argA "token_b")) s4 (pool) (st.call.argA "a") (st.call.arg "min_b_for_a")
  let s6 := xfer (toString (st.call.argA "token_b")) s5 (pool) (st.call.argA "b") ((st.call.arg "amount_b" - st.call.arg "min_b_for_a"))
  st.call.fn = "swap" ∧
  c ≠ pool ∧
  c = st.call.argA "a" ∧   -- require_auth
  st.call.signed (st.call.argA "b") ∧   -- require_auth
  st.call.arg "min_b_for_a" ≤ st.call.arg "amount_b" ∧   -- gate
  st.call.arg "amount_a" ≥ st.call.arg "min_a_for_b" ∧   -- gate
  st.post = s6 ∧
  st.writes = [.entry (toString (st.call.argA "token_a")) (st.call.argA "a"), .entry (toString (st.call.argA "token_a")) (pool), .entry (toString (st.call.argA "token_a")) (st.call.argA "b"), .entry (toString (st.call.argA "token_b")) (st.call.argA "b"), .entry (toString (st.call.argA "token_b")) (pool), .entry (toString (st.call.argA "token_b")) (st.call.argA "a")] ∧
  st.ret = 0

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [swap]

end Contract
