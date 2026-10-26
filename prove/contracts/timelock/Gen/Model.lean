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
  st.pre Balance.amount
@[simp] def s1 (st : Step) : Storage :=
  xfer (st.pre Balance.token) st.pre (pool st) (claim.claimant st) (claim.amt1 st)
@[simp] def s2 (st : Step) : Storage :=
  (claim.s1 st).set (.has Balance) 0
end claim

/-- `claim(claimant: Address)`: it succeeds exactly when `claim.Spec` holds.
    Its effects, in execution order:
    * `claim.s1`: transfer `claim.amt1 st` of token `st.pre Balance.token` from `pool st` to `claim.claimant st`
    * `claim.s2`: remove `Balance`
-/
structure claim.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "claim"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer1 : xferOk (st.pre Balance.token) st.pre (pool st) (claim.claimant st) (claim.amt1 st)
  /-- `claim.claimant st` authorized the call (`require_auth`) -/
  auth_claimant : (claim.claimant st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (st.pre (.has Balance)) = 1
  /-- the call panics unless this holds -/
  gate2 : ¬(if (u.g 1) = 0 then (if (u.g 2) ≠ 0 then 0 else (if ((u.g 3) = 0) ∧ (((u.g 4) ≠ 64) ∧ ((u.g 5) ≠ 6)) then 0 else (st.pre Balance.time_bound.timestamp))) < (st.call.env "timestamp") else (if (u.g 6) ≠ 0 then 0 else (if ((u.g 7) = 0) ∧ (((u.g 8) ≠ 64) ∧ ((u.g 9) ≠ 6)) then 0 else (st.pre Balance.time_bound.timestamp))) > (st.call.env "timestamp"))
  post : st.post = (claim.s2 st)
  writes : st.writes = [.bal (st.pre Balance.token) (pool st), .bal (st.pre Balance.token) (claim.claimant st), .has Balance]
  ret : st.ret = 2

def claim : Step → Prop := fun st => ∃ u : Unk, claim.Spec st u

namespace deposit
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def claimants (st : Step) : Int := st.call.arg "claimants"
@[simp] def claimants.len (st : Step) : Int := st.call.arg "claimants.len"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def time_bound.timestamp (st : Step) : Int := st.call.arg "time_bound.timestamp"
@[simp] def token (st : Step) : Addr := st.call.argA "token"
@[simp] def amt1 (st : Step) : Int :=
  deposit.amount st
@[simp] def s1 (st : Step) : Storage :=
  xfer (deposit.token st) st.pre (deposit.«from» st) (pool st) (deposit.amt1 st)
@[simp] def new_Balance_time_bound_timestamp (st : Step) (u : Unk) : Int :=
  if (u.i 2) ≠ 0 then 1 else (deposit.time_bound.timestamp st)
@[simp] def s2 (st : Step) (u : Unk) : Storage :=
  ((((((deposit.s1 st).set Balance.amount (deposit.amt1 st)).set Balance.claimants (deposit.claimants st)).set Balance.time_bound.kind (u.i 1)).set Balance.time_bound.timestamp (deposit.new_Balance_time_bound_timestamp st u)).set Balance.token (deposit.token st)).set (.has Balance) 1
@[simp] def s3 (st : Step) (u : Unk) : Storage :=
  ((deposit.s2 st u).set Init 2).set (.has Init) 1
end deposit

/-- `deposit(from: Address, token: Address, amount: i128, claimants: Vec<Address>, time_bound: TimeBound)`: it succeeds exactly when `deposit.Spec` holds.
    Its effects, in execution order:
    * `deposit.s1`: transfer `deposit.amt1 st` of token `deposit.token st` from `deposit.«from» st` to `pool st`
    * `deposit.s2`: write `Balance.amount` := `deposit.amount st`, `Balance.claimants` := `deposit.claimants st`, `Balance.time_bound.kind` := `u.i 1`, `Balance.time_bound.timestamp` := `deposit.new_Balance_time_bound_timestamp st u`, `Balance.token` := `deposit.token st`
    * `deposit.s3`: write `Init` := `2`
-/
structure deposit.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "deposit"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the token accepts the transfer (SEP-41: a non-negative amount the sender holds) -/
  xfer1 : xferOk (deposit.token st) st.pre (deposit.«from» st) (pool st) (deposit.amt1 st)
  /-- `deposit.«from» st` authorized the call (`require_auth`) -/
  auth_from : (deposit.«from» st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (deposit.claimants.len st) < 11
  /-- the call panics unless this holds -/
  gate2 : (st.pre (.has Init)) ≠ 1
  post : st.post = (deposit.s3 st u)
  writes : st.writes = [.bal (deposit.token st) (deposit.«from» st), .bal (deposit.token st) (pool st), Balance.amount, Balance.claimants, Balance.time_bound.kind, Balance.time_bound.timestamp, Balance.token, .has Balance, Init, .has Init]
  ret : st.ret = 2

def deposit : Step → Prop := fun st => ∃ u : Unk, deposit.Spec st u

/-- the contract's entry points (each a `Step → Prop`; the constructor runs
    only at deployment, so it is not one of them). -/
def entries : List (Step → Prop) := [claim, deposit]

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
