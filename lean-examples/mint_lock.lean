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

/-! ## Storage layout -/

@[simp] def Admin : Key := .var "Admin"
@[simp] def Minter (k1 : Int) (k2 : Int) : Key := .tup "Minter" [k1, k2]
@[simp] def Minter.epoch_length (k1 : Int) (k2 : Int) : Key := .fld (Minter k1 k2) "epoch_length"
@[simp] def MinterStats (k1 : Int) (k2 : Int) (k3 : Int) (k4 : Int) : Key := .tup "MinterStats" [k1, k2, k3, k4]
@[simp] def MinterStats.consumed_limit (k1 : Int) (k2 : Int) (k3 : Int) (k4 : Int) : Key := .fld (MinterStats k1 k2 k3 k4) "consumed_limit"
@[simp] def Minter.limit (k1 : Int) (k2 : Int) : Key := .fld (Minter k1 k2) "limit"

namespace __constructor
@[simp] def admin (st : Step) : Addr := st.call.argA "admin"
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set Admin (__constructor.admin st)).set (.has Admin) 1
end __constructor

/-- `__constructor(admin: Address)`: it succeeds exactly when `__constructor.Spec` holds.
    Its effects, in execution order:
    * `__constructor.s1`: write `Admin`
-/
structure __constructor.Spec (st : Step) : Prop where
  fn : st.call.fn = "__constructor"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = (__constructor.s1 st)
  writes : st.writes = [Admin, .has Admin]
  ret : st.ret = 2

abbrev __constructor : Step → Prop := fun st => __constructor.Spec st

/-- `admin()`: it succeeds exactly when `admin.Spec` holds.
-/
structure admin.Spec (st : Step) : Prop where
  fn : st.call.fn = "admin"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (st.pre Admin)

abbrev admin : Step → Prop := fun st => admin.Spec st

namespace mint
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def contract (st : Step) : Addr := st.call.argA "contract"
@[simp] def minter (st : Step) : Addr := st.call.argA "minter"
@[simp] def to (st : Step) : Addr := st.call.argA "to"
@[simp] def s1 (st : Step) : Storage :=
  if ¬((mint.amount st) < 0) ∧ ¬((st.pre Admin) = (mint.minter st)) ∧ ¬(¬((st.pre (.has (Minter (mint.contract st) (mint.minter st)))) = 1)) ∧ ¬(((getOr0 st.pre (MinterStats.consumed_limit (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))) (base := (MinterStats (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))))) + (mint.amount st)) > (st.pre (Minter.limit (mint.contract st) (mint.minter st)))) then ((st.pre).set (MinterStats.consumed_limit (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))) ((getOr0 st.pre (MinterStats.consumed_limit (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))) (base := (MinterStats (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))))) + (mint.amount st))).set (.has (MinterStats (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st)))))) 1 else st.pre
@[simp] def s2 (st : Step) (u : Unk) : Storage :=
  if ((¬((mint.amount st) < 0)) ∧ ((st.pre Admin) = (mint.minter st))) ∨ ((¬((mint.amount st) < 0)) ∧ (¬((st.pre Admin) = (mint.minter st))) ∧ (¬(¬((st.pre (.has (Minter (mint.contract st) (mint.minter st)))) = 1))) ∧ (¬(((getOr0 st.pre (MinterStats.consumed_limit (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))) (base := (MinterStats (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))))) + (mint.amount st)) > (st.pre (Minter.limit (mint.contract st) (mint.minter st)))))) then havoc (mint.s1 st) (u.s 1) else (mint.s1 st)
end mint

/-- `mint(contract: Address, minter: Address, to: Address, amount: i128)`: it succeeds exactly when `mint.Spec` holds.
    Its effects, in execution order:
    * `mint.s1`: write `MinterStats (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))`, when `¬((mint.amount st) < 0) ∧ ¬((st.pre Admin) = (mint.minter st)) ∧ ¬(¬((st.pre (.has (Minter (mint.contract st) (mint.minter st)))) = 1)) ∧ ¬(((getOr0 st.pre (MinterStats.consumed_limit (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))) (base := (MinterStats (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))))) + (mint.amount st)) > (st.pre (Minter.limit (mint.contract st) (mint.minter st))))`
    * `mint.s2`: a call into another contract: token ledgers open, when `((¬((mint.amount st) < 0)) ∧ ((st.pre Admin) = (mint.minter st))) ∨ ((¬((mint.amount st) < 0)) ∧ (¬((st.pre Admin) = (mint.minter st))) ∧ (¬(¬((st.pre (.has (Minter (mint.contract st) (mint.minter st)))) = 1))) ∧ (¬(((getOr0 st.pre (MinterStats.consumed_limit (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))) (base := (MinterStats (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))))) + (mint.amount st)) > (st.pre (Minter.limit (mint.contract st) (mint.minter st))))))`
-/
structure mint.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "mint"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `mint.minter st` authorized the call (`require_auth`) -/
  auth_minter : (mint.minter st) ∈ st.call.signers
  /-- the call returns `Ok` (an `Err` fails it) -/
  ok : (((¬((mint.amount st) < 0)) ∧ ((st.pre Admin) = (mint.minter st))) ∨ ((¬((mint.amount st) < 0)) ∧ (¬((st.pre Admin) = (mint.minter st))) ∧ (¬(¬((st.pre (.has (Minter (mint.contract st) (mint.minter st)))) = 1))) ∧ (¬(((getOr0 st.pre (MinterStats.consumed_limit (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))) (base := (MinterStats (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))))) + (mint.amount st)) > (st.pre (Minter.limit (mint.contract st) (mint.minter st)))))))
  post : st.post = (mint.s2 st u)
  writes : st.writes = [(MinterStats.consumed_limit (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))), .has (MinterStats (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st)))))]
  ret : st.ret = (if ((¬((mint.amount st) < 0)) ∧ ((st.pre Admin) = (mint.minter st))) ∨ ((¬((mint.amount st) < 0)) ∧ (¬((st.pre Admin) = (mint.minter st))) ∧ (¬(¬((st.pre (.has (Minter (mint.contract st) (mint.minter st)))) = 1))) ∧ (¬(((getOr0 st.pre (MinterStats.consumed_limit (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))) (base := (MinterStats (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))))) + (mint.amount st)) > (st.pre (Minter.limit (mint.contract st) (mint.minter st)))))) then 2 else (if (mint.amount st) < 0 then 12884901891 else (if ¬((st.pre (.has (Minter (mint.contract st) (mint.minter st)))) = 1) then 4294967299 else 8589934595)))

def mint : Step → Prop := fun st => ∃ u : Unk, mint.Spec st u

namespace minter
@[simp] def contract (st : Step) : Addr := st.call.argA "contract"
@[simp] def minter (st : Step) : Addr := st.call.argA "minter"
end minter

/-- `minter(contract: Address, minter: Address)`: it succeeds exactly when `minter.Spec` holds.
-/
structure minter.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "minter"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (if ¬(¬((st.pre (.has (Minter (minter.contract st) (minter.minter st)))) = 1)) then (u.i 1) else 4294967299)

def minter : Step → Prop := fun st => ∃ u : Unk, minter.Spec st u

namespace set_admin
@[simp] def new_admin (st : Step) : Addr := st.call.argA "new_admin"
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set Admin (set_admin.new_admin st)).set (.has Admin) 1
end set_admin

/-- `set_admin(new_admin: Address)`: it succeeds exactly when `set_admin.Spec` holds.
    Its effects, in execution order:
    * `set_admin.s1`: write `Admin`
-/
structure set_admin.Spec (st : Step) : Prop where
  fn : st.call.fn = "set_admin"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `st.pre Admin` authorized the call (`require_auth`) -/
  auth_Admin : (st.pre Admin) ∈ st.call.signers
  post : st.post = (set_admin.s1 st)
  writes : st.writes = [Admin, .has Admin]
  ret : st.ret = 2

abbrev set_admin : Step → Prop := fun st => set_admin.Spec st

namespace set_minter
@[simp] def config.epoch_length (st : Step) : Int := st.call.arg "config.epoch_length"
@[simp] def config.limit (st : Step) : Int := st.call.arg "config.limit"
@[simp] def contract (st : Step) : Addr := st.call.argA "contract"
@[simp] def minter (st : Step) : Addr := st.call.argA "minter"
@[simp] def s1 (st : Step) : Storage :=
  (((st.pre).set (Minter.epoch_length (set_minter.contract st) (set_minter.minter st)) (set_minter.config.epoch_length st)).set (Minter.limit (set_minter.contract st) (set_minter.minter st)) (set_minter.config.limit st)).set (.has (Minter (set_minter.contract st) (set_minter.minter st))) 1
end set_minter

/-- `set_minter(contract: Address, minter: Address, config: MinterConfig)`: it succeeds exactly when `set_minter.Spec` holds.
    Its effects, in execution order:
    * `set_minter.s1`: write `Minter (set_minter.contract st) (set_minter.minter st)`
-/
structure set_minter.Spec (st : Step) : Prop where
  fn : st.call.fn = "set_minter"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `st.pre Admin` authorized the call (`require_auth`) -/
  auth_Admin : (st.pre Admin) ∈ st.call.signers
  post : st.post = (set_minter.s1 st)
  writes : st.writes = [(Minter.epoch_length (set_minter.contract st) (set_minter.minter st)), (Minter.limit (set_minter.contract st) (set_minter.minter st)), .has (Minter (set_minter.contract st) (set_minter.minter st))]
  ret : st.ret = 2

abbrev set_minter : Step → Prop := fun st => set_minter.Spec st

/-- the contract's entry points (each a `Step → Prop`; the constructor runs
    only at deployment, so it is not one of them). -/
def entries : List (Step → Prop) := [admin, mint, minter, set_admin, set_minter]

/-- Keys in temporary storage: they can expire between calls. -/
def temporary : Key → Bool
  | .tup "MinterStats" _ => true
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
