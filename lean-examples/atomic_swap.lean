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

/-- `swap(a: Address, b: Address, token_a: Address, token_b: Address, amount_a: i128, min_b_for_a: i128, amount_b: i128, min_a_for_b: i128)`
    effects, in execution order:
      transfer token_a: a -> @pool : amount_a
      transfer token_a: @pool -> b : min_a_for_b
      transfer token_a: @pool -> a : (amount_a - min_a_for_b)
      transfer token_b: b -> @pool : amount_b
      transfer token_b: @pool -> a : min_b_for_a
      transfer token_b: @pool -> b : (amount_b - min_b_for_a)
    conditions to succeed:
      require_auth a
      require_auth b
      gate: min_b_for_a ≤ amount_b
      gate: amount_a ≥ min_a_for_b
-/
def swap : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  let s1 := xfer (st.call.argA "token_a") st.pre (st.call.argA "a") (pool) (st.call.arg "amount_a")
  let s2 := xfer (st.call.argA "token_a") s1 (pool) (st.call.argA "b") (st.call.arg "min_a_for_b")
  let s3 := xfer (st.call.argA "token_a") s2 (pool) (st.call.argA "a") ((st.call.arg "amount_a" - st.call.arg "min_a_for_b"))
  let s4 := xfer (st.call.argA "token_b") s3 (st.call.argA "b") (pool) (st.call.arg "amount_b")
  let s5 := xfer (st.call.argA "token_b") s4 (pool) (st.call.argA "a") (st.call.arg "min_b_for_a")
  let s6 := xfer (st.call.argA "token_b") s5 (pool) (st.call.argA "b") ((st.call.arg "amount_b" - st.call.arg "min_b_for_a"))
  st.call.fn = "swap" ∧
  c ≠ pool ∧
  st.call.argA "a" ∈ st.call.signers ∧   -- require_auth a
  st.call.argA "b" ∈ st.call.signers ∧   -- require_auth b
  st.call.arg "min_b_for_a" ≤ st.call.arg "amount_b" ∧   -- gate
  st.call.arg "amount_a" ≥ st.call.arg "min_a_for_b" ∧   -- gate
  st.post = s6 ∧
  st.writes = [.bal (st.call.argA "token_a") (st.call.argA "a"), .bal (st.call.argA "token_a") (pool), .bal (st.call.argA "token_a") (st.call.argA "b"), .bal (st.call.argA "token_b") (st.call.argA "b"), .bal (st.call.argA "token_b") (pool), .bal (st.call.argA "token_b") (st.call.argA "a")] ∧
  st.ret = 2

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [swap]

end Contract
