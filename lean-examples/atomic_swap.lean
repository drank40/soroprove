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

namespace swap
@[simp] def a (st : Step) : Addr := st.call.argA "a"
@[simp] def amount_a (st : Step) : Int := st.call.arg "amount_a"
@[simp] def amount_b (st : Step) : Int := st.call.arg "amount_b"
@[simp] def b (st : Step) : Addr := st.call.argA "b"
@[simp] def min_a_for_b (st : Step) : Int := st.call.arg "min_a_for_b"
@[simp] def min_b_for_a (st : Step) : Int := st.call.arg "min_b_for_a"
@[simp] def token_a (st : Step) : Addr := st.call.argA "token_a"
@[simp] def token_b (st : Step) : Addr := st.call.argA "token_b"
@[simp] def amt1 (st : Step) : Int :=
  (swap.amount_a st)
@[simp] def s1 (st : Step) : Storage :=
  xfer (swap.token_a st) st.pre (swap.a st) (pool st) (swap.amt1 st)
@[simp] def amt2 (st : Step) : Int :=
  (swap.min_a_for_b st)
@[simp] def s2 (st : Step) : Storage :=
  xfer (swap.token_a st) (swap.s1 st) (pool st) (swap.b st) (swap.amt2 st)
@[simp] def amt3 (st : Step) : Int :=
  ((swap.amount_a st) - (swap.min_a_for_b st))
@[simp] def s3 (st : Step) : Storage :=
  xfer (swap.token_a st) (swap.s2 st) (pool st) (swap.a st) (swap.amt3 st)
@[simp] def amt4 (st : Step) : Int :=
  (swap.amount_b st)
@[simp] def s4 (st : Step) : Storage :=
  xfer (swap.token_b st) (swap.s3 st) (swap.b st) (pool st) (swap.amt4 st)
@[simp] def amt5 (st : Step) : Int :=
  (swap.min_b_for_a st)
@[simp] def s5 (st : Step) : Storage :=
  xfer (swap.token_b st) (swap.s4 st) (pool st) (swap.a st) (swap.amt5 st)
@[simp] def amt6 (st : Step) : Int :=
  ((swap.amount_b st) - (swap.min_b_for_a st))
@[simp] def s6 (st : Step) : Storage :=
  xfer (swap.token_b st) (swap.s5 st) (pool st) (swap.b st) (swap.amt6 st)
end swap

/-- `swap(a: Address, b: Address, token_a: Address, token_b: Address, amount_a: i128, min_b_for_a: i128, amount_b: i128, min_a_for_b: i128)`
    effects, in execution order (states `swap.s1`, `swap.s2`, …; amounts `swap.amt1`, …):
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
  st.call.fn = "swap" ∧
  st.call.caller ≠ pool st ∧
  (swap.a st) ∈ st.call.signers ∧   -- require_auth a
  (swap.b st) ∈ st.call.signers ∧   -- require_auth b
  (swap.min_b_for_a st) ≤ (swap.amount_b st) ∧   -- gate
  (swap.amount_a st) ≥ (swap.min_a_for_b st) ∧   -- gate
  st.post = (swap.s6 st) ∧
  st.writes = [.bal (swap.token_a st) (swap.a st), .bal (swap.token_a st) (pool st), .bal (swap.token_a st) (swap.b st), .bal (swap.token_b st) (swap.b st), .bal (swap.token_b st) (pool st), .bal (swap.token_b st) (swap.a st)] ∧
  st.ret = 2

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [swap]

end Contract
