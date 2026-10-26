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

/-- `swap(a: Address, b: Address, token_a: Address, token_b: Address, amount_a: i128, min_b_for_a: i128, amount_b: i128, min_a_for_b: i128)`: it succeeds exactly when `swap.Spec` holds.
    Its effects, in execution order:
    * `swap.s1`: transfer `swap.amt1 st` of token `swap.token_a st` from `swap.a st` to `pool st`
    * `swap.s2`: transfer `swap.amt2 st` of token `swap.token_a st` from `pool st` to `swap.b st`
    * `swap.s3`: transfer `swap.amt3 st` of token `swap.token_a st` from `pool st` to `swap.a st`
    * `swap.s4`: transfer `swap.amt4 st` of token `swap.token_b st` from `swap.b st` to `pool st`
    * `swap.s5`: transfer `swap.amt5 st` of token `swap.token_b st` from `pool st` to `swap.a st`
    * `swap.s6`: transfer `swap.amt6 st` of token `swap.token_b st` from `pool st` to `swap.b st`
-/
structure swap.Spec (st : Step) : Prop where
  fn : st.call.fn = "swap"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer1 : xferOk (swap.token_a st) st.pre (swap.a st) (pool st) (swap.amt1 st)
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer2 : xferOk (swap.token_a st) (swap.s1 st) (pool st) (swap.b st) (swap.amt2 st)
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer3 : xferOk (swap.token_a st) (swap.s2 st) (pool st) (swap.a st) (swap.amt3 st)
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer4 : xferOk (swap.token_b st) (swap.s3 st) (swap.b st) (pool st) (swap.amt4 st)
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer5 : xferOk (swap.token_b st) (swap.s4 st) (pool st) (swap.a st) (swap.amt5 st)
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer6 : xferOk (swap.token_b st) (swap.s5 st) (pool st) (swap.b st) (swap.amt6 st)
  /-- `swap.a st` authorized the call (`require_auth`) -/
  auth_a : (swap.a st) ∈ st.call.signers
  /-- `swap.b st` authorized the call (`require_auth`) -/
  auth_b : (swap.b st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (swap.min_b_for_a st) ≤ (swap.amount_b st)
  /-- the call panics unless this holds -/
  gate2 : (swap.amount_a st) ≥ (swap.min_a_for_b st)
  post : st.post = (swap.s6 st)
  writes : st.writes = [.bal (swap.token_a st) (swap.a st), .bal (swap.token_a st) (pool st), .bal (swap.token_a st) (swap.b st), .bal (swap.token_b st) (swap.b st), .bal (swap.token_b st) (pool st), .bal (swap.token_b st) (swap.a st)]
  ret : st.ret = 2

abbrev swap : Step → Prop := fun st => swap.Spec st

/-- the contract's entry points (each a `Step → Prop`; the constructor runs
    only at deployment, so it is not one of them). -/
def entries : List (Step → Prop) := [swap]

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
