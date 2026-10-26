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
@[simp] def METADATA : Key := .var "METADATA"
@[simp] def METADATA.decimal : Key := .fld METADATA "decimal"
@[simp] def METADATA.name : Key := .fld METADATA "name"
@[simp] def METADATA.symbol : Key := .fld METADATA "symbol"
@[simp] def Allowance (k1 : Int) (k2 : Int) : Key := .tup "Allowance" [k1, k2]
@[simp] def Allowance.live_until_ledger (k1 : Int) (k2 : Int) : Key := .fld (Allowance k1 k2) "live_until_ledger"
@[simp] def Allowance.amount (k1 : Int) (k2 : Int) : Key := .fld (Allowance k1 k2) "amount"
@[simp] def Balance (k1 : Addr) : Key := .entry "Balance" k1

namespace __constructor
@[simp] def admin (st : Step) : Addr := st.call.argA "admin"
@[simp] def decimal (st : Step) : Int := st.call.arg "decimal"
@[simp] def name (st : Step) : Int := st.call.arg "name"
@[simp] def symbol (st : Step) : Int := st.call.arg "symbol"
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set Admin (__constructor.admin st)).set (.has Admin) 1
@[simp] def s2 (st : Step) (u : Unk) : Storage :=
  ((((__constructor.s1 st).set METADATA.decimal (u.i 1)).set METADATA.name (__constructor.name st)).set METADATA.symbol (__constructor.symbol st)).set (.has METADATA) 1
end __constructor

/-- `__constructor(admin: Address, decimal: u32, name: String, symbol: String)`: it succeeds exactly when `__constructor.Spec` holds.
    Its effects, in execution order:
    * `__constructor.s1`: write `Admin`
    * `__constructor.s2`: write `METADATA`
-/
structure __constructor.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "__constructor"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- the call panics unless this holds -/
  gate1 : (__constructor.decimal st) < 19
  post : st.post = (__constructor.s2 st u)
  writes : st.writes = [Admin, .has Admin, METADATA.decimal, METADATA.name, METADATA.symbol, .has METADATA]
  ret : st.ret = 2

def __constructor : Step → Prop := fun st => ∃ u : Unk, __constructor.Spec st u

namespace allowance
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def spender (st : Step) : Addr := st.call.argA "spender"
end allowance

/-- `allowance(from: Address, spender: Address)`: it succeeds exactly when `allowance.Spec` holds.
-/
structure allowance.Spec (st : Step) : Prop where
  fn : st.call.fn = "allowance"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (if ¬((st.pre (.has (Allowance (allowance.«from» st) (allowance.spender st)))) = 1) then 0 else (if ¬((st.call.env "sequence") > (st.pre (Allowance.live_until_ledger (allowance.«from» st) (allowance.spender st)))) then (st.pre (Allowance.amount (allowance.«from» st) (allowance.spender st))) else 0))

abbrev allowance : Step → Prop := fun st => allowance.Spec st

namespace approve
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def live_until_ledger (st : Step) : Int := st.call.arg "live_until_ledger"
@[simp] def spender (st : Step) : Addr := st.call.argA "spender"
@[simp] def s1 (st : Step) (u : Unk) : Storage :=
  (((st.pre).set (Allowance.amount (approve.«from» st) (approve.spender st)) (u.i 1)).set (Allowance.live_until_ledger (approve.«from» st) (approve.spender st)) (approve.live_until_ledger st)).set (.has (Allowance (approve.«from» st) (approve.spender st))) 1
end approve

/-- `approve(from: Address, spender: Address, amount: i128, live_until_ledger: u32)`: it succeeds exactly when `approve.Spec` holds.
    Its effects, in execution order:
    * `approve.s1`: write `Allowance (approve.«from» st) (approve.spender st)`
-/
structure approve.Spec (st : Step) (u : Unk) : Prop where
  fn : st.call.fn = "approve"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `approve.«from» st` authorized the call (`require_auth`) -/
  auth_from : (approve.«from» st) ∈ st.call.signers
  post : st.post = (approve.s1 st u)
  writes : st.writes = [(Allowance.amount (approve.«from» st) (approve.spender st)), (Allowance.live_until_ledger (approve.«from» st) (approve.spender st)), .has (Allowance (approve.«from» st) (approve.spender st))]
  ret : st.ret = 2

def approve : Step → Prop := fun st => ∃ u : Unk, approve.Spec st u

namespace balance
@[simp] def id (st : Step) : Addr := st.call.argA "id"
end balance

/-- `balance(id: Address)`: it succeeds exactly when `balance.Spec` holds.
-/
structure balance.Spec (st : Step) : Prop where
  fn : st.call.fn = "balance"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (getOr0 st.pre (Balance (balance.id st)))

abbrev balance : Step → Prop := fun st => balance.Spec st

namespace burn
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set (Balance (burn.«from» st)) ((getOr0 st.pre (Balance (burn.«from» st))) - (burn.amount st))).set (.has (Balance (burn.«from» st))) 1
end burn

/-- `burn(from: Address, amount: i128)`: it succeeds exactly when `burn.Spec` holds.
    Its effects, in execution order:
    * `burn.s1`: write `Balance (burn.«from» st)`
-/
structure burn.Spec (st : Step) : Prop where
  fn : st.call.fn = "burn"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `burn.«from» st` authorized the call (`require_auth`) -/
  auth_from : (burn.«from» st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (burn.amount st) > -1
  /-- the call panics unless this holds -/
  gate2 : (getOr0 st.pre (Balance (burn.«from» st))) ≥ (burn.amount st)
  post : st.post = (burn.s1 st)
  writes : st.writes = [(Balance (burn.«from» st)), .has (Balance (burn.«from» st))]
  ret : st.ret = 2

abbrev burn : Step → Prop := fun st => burn.Spec st

namespace burn_from
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def spender (st : Step) : Addr := st.call.argA "spender"
@[simp] def s1 (st : Step) : Storage :=
  if ¬((burn_from.amount st) = 0) then (((st.pre).set (Allowance.amount (burn_from.«from» st) (burn_from.spender st)) ((if ¬((st.pre (.has (Allowance (burn_from.«from» st) (burn_from.spender st)))) = 1) then 0 else (if ¬((st.call.env "sequence") > (st.pre (Allowance.live_until_ledger (burn_from.«from» st) (burn_from.spender st)))) then (st.pre (Allowance.amount (burn_from.«from» st) (burn_from.spender st))) else 0)) - (burn_from.amount st))).set (Allowance.live_until_ledger (burn_from.«from» st) (burn_from.spender st)) (getOr0 st.pre (Allowance.live_until_ledger (burn_from.«from» st) (burn_from.spender st)) (base := (Allowance (burn_from.«from» st) (burn_from.spender st))))).set (.has (Allowance (burn_from.«from» st) (burn_from.spender st))) 1 else st.pre
@[simp] def s2 (st : Step) : Storage :=
  ((burn_from.s1 st).set (Balance (burn_from.«from» st)) ((getOr0 (burn_from.s1 st) (Balance (burn_from.«from» st))) - (burn_from.amount st))).set (.has (Balance (burn_from.«from» st))) 1
end burn_from

/-- `burn_from(spender: Address, from: Address, amount: i128)`: it succeeds exactly when `burn_from.Spec` holds.
    Its effects, in execution order:
    * `burn_from.s1`: write `Allowance (burn_from.«from» st) (burn_from.spender st)`, when `¬((burn_from.amount st) = 0)`
    * `burn_from.s2`: write `Balance (burn_from.«from» st)`
-/
structure burn_from.Spec (st : Step) : Prop where
  fn : st.call.fn = "burn_from"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `burn_from.spender st` authorized the call (`require_auth`) -/
  auth_spender : (burn_from.spender st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (burn_from.amount st) > -1
  /-- the call panics unless this holds -/
  gate2 : (if ¬((st.pre (.has (Allowance (burn_from.«from» st) (burn_from.spender st)))) = 1) then 0 else (if ((st.pre (.has (Allowance (burn_from.«from» st) (burn_from.spender st)))) = 1) ∧ (¬((st.call.env "sequence") > (st.pre (Allowance.live_until_ledger (burn_from.«from» st) (burn_from.spender st))))) then (st.pre (Allowance.amount (burn_from.«from» st) (burn_from.spender st))) else 0)) ≥ (burn_from.amount st)
  /-- the call panics unless this holds -/
  gate3 : (getOr0 (burn_from.s1 st) (Balance (burn_from.«from» st))) ≥ (burn_from.amount st)
  post : st.post = (burn_from.s2 st)
  writes : st.writes = [(Allowance.amount (burn_from.«from» st) (burn_from.spender st)), (Allowance.live_until_ledger (burn_from.«from» st) (burn_from.spender st)), .has (Allowance (burn_from.«from» st) (burn_from.spender st)), (Balance (burn_from.«from» st)), .has (Balance (burn_from.«from» st))]
  ret : st.ret = 2

abbrev burn_from : Step → Prop := fun st => burn_from.Spec st

/-- `decimals()`: it succeeds exactly when `decimals.Spec` holds.
-/
structure decimals.Spec (st : Step) : Prop where
  fn : st.call.fn = "decimals"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (st.pre METADATA.decimal)

abbrev decimals : Step → Prop := fun st => decimals.Spec st

namespace mint
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def to (st : Step) : Addr := st.call.argA "to"
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set (Balance (mint.to st)) ((getOr0 st.pre (Balance (mint.to st))) + (mint.amount st))).set (.has (Balance (mint.to st))) 1
end mint

/-- `mint(to: Address, amount: i128)`: it succeeds exactly when `mint.Spec` holds.
    Its effects, in execution order:
    * `mint.s1`: write `Balance (mint.to st)`
-/
structure mint.Spec (st : Step) : Prop where
  fn : st.call.fn = "mint"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `st.pre Admin` authorized the call (`require_auth`) -/
  auth_Admin : (st.pre Admin) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (mint.amount st) > -1
  post : st.post = (mint.s1 st)
  writes : st.writes = [(Balance (mint.to st)), .has (Balance (mint.to st))]
  ret : st.ret = 2

abbrev mint : Step → Prop := fun st => mint.Spec st

/-- `name()`: it succeeds exactly when `name.Spec` holds.
-/
structure name.Spec (st : Step) : Prop where
  fn : st.call.fn = "name"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (st.pre METADATA.name)

abbrev name : Step → Prop := fun st => name.Spec st

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

/-- `symbol()`: it succeeds exactly when `symbol.Spec` holds.
-/
structure symbol.Spec (st : Step) : Prop where
  fn : st.call.fn = "symbol"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  post : st.post = st.pre
  writes : st.writes = []
  ret : st.ret = (st.pre METADATA.symbol)

abbrev symbol : Step → Prop := fun st => symbol.Spec st

namespace transfer
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def to_muxed (st : Step) : Addr := st.call.argA "to_muxed"
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set (Balance (transfer.«from» st)) ((getOr0 st.pre (Balance (transfer.«from» st))) - (transfer.amount st))).set (.has (Balance (transfer.«from» st))) 1
@[simp] def s2 (st : Step) : Storage :=
  ((transfer.s1 st).set (Balance (transfer.to_muxed st)) ((getOr0 (transfer.s1 st) (Balance (transfer.to_muxed st))) + (transfer.amount st))).set (.has (Balance (transfer.to_muxed st))) 1
end transfer

/-- `transfer(from: Address, to_muxed: MuxedAddress, amount: i128)`: it succeeds exactly when `transfer.Spec` holds.
    Its effects, in execution order:
    * `transfer.s1`: write `Balance (transfer.«from» st)`
    * `transfer.s2`: write `Balance (transfer.to_muxed st)`
-/
structure transfer.Spec (st : Step) : Prop where
  fn : st.call.fn = "transfer"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `transfer.«from» st` authorized the call (`require_auth`) -/
  auth_from : (transfer.«from» st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (transfer.amount st) > -1
  /-- the call panics unless this holds -/
  gate2 : (getOr0 st.pre (Balance (transfer.«from» st))) ≥ (transfer.amount st)
  post : st.post = (transfer.s2 st)
  writes : st.writes = [(Balance (transfer.«from» st)), .has (Balance (transfer.«from» st)), (Balance (transfer.to_muxed st)), .has (Balance (transfer.to_muxed st))]
  ret : st.ret = 2

abbrev transfer : Step → Prop := fun st => transfer.Spec st

namespace transfer_from
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def spender (st : Step) : Addr := st.call.argA "spender"
@[simp] def to (st : Step) : Addr := st.call.argA "to"
@[simp] def s1 (st : Step) : Storage :=
  if ¬((transfer_from.amount st) = 0) then (((st.pre).set (Allowance.amount (transfer_from.«from» st) (transfer_from.spender st)) ((if ¬((st.pre (.has (Allowance (transfer_from.«from» st) (transfer_from.spender st)))) = 1) then 0 else (if ¬((st.call.env "sequence") > (st.pre (Allowance.live_until_ledger (transfer_from.«from» st) (transfer_from.spender st)))) then (st.pre (Allowance.amount (transfer_from.«from» st) (transfer_from.spender st))) else 0)) - (transfer_from.amount st))).set (Allowance.live_until_ledger (transfer_from.«from» st) (transfer_from.spender st)) (getOr0 st.pre (Allowance.live_until_ledger (transfer_from.«from» st) (transfer_from.spender st)) (base := (Allowance (transfer_from.«from» st) (transfer_from.spender st))))).set (.has (Allowance (transfer_from.«from» st) (transfer_from.spender st))) 1 else st.pre
@[simp] def s2 (st : Step) : Storage :=
  ((transfer_from.s1 st).set (Balance (transfer_from.«from» st)) ((getOr0 (transfer_from.s1 st) (Balance (transfer_from.«from» st))) - (transfer_from.amount st))).set (.has (Balance (transfer_from.«from» st))) 1
@[simp] def s3 (st : Step) : Storage :=
  ((transfer_from.s2 st).set (Balance (transfer_from.to st)) ((getOr0 (transfer_from.s2 st) (Balance (transfer_from.to st))) + (transfer_from.amount st))).set (.has (Balance (transfer_from.to st))) 1
end transfer_from

/-- `transfer_from(spender: Address, from: Address, to: Address, amount: i128)`: it succeeds exactly when `transfer_from.Spec` holds.
    Its effects, in execution order:
    * `transfer_from.s1`: write `Allowance (transfer_from.«from» st) (transfer_from.spender st)`, when `¬((transfer_from.amount st) = 0)`
    * `transfer_from.s2`: write `Balance (transfer_from.«from» st)`
    * `transfer_from.s3`: write `Balance (transfer_from.to st)`
-/
structure transfer_from.Spec (st : Step) : Prop where
  fn : st.call.fn = "transfer_from"
  /-- not called by the contract itself (Soroban forbids re-entry) -/
  notReentrant : st.call.caller ≠ pool st
  /-- `transfer_from.spender st` authorized the call (`require_auth`) -/
  auth_spender : (transfer_from.spender st) ∈ st.call.signers
  /-- the call panics unless this holds -/
  gate1 : (transfer_from.amount st) > -1
  /-- the call panics unless this holds -/
  gate2 : (if ¬((st.pre (.has (Allowance (transfer_from.«from» st) (transfer_from.spender st)))) = 1) then 0 else (if ((st.pre (.has (Allowance (transfer_from.«from» st) (transfer_from.spender st)))) = 1) ∧ (¬((st.call.env "sequence") > (st.pre (Allowance.live_until_ledger (transfer_from.«from» st) (transfer_from.spender st))))) then (st.pre (Allowance.amount (transfer_from.«from» st) (transfer_from.spender st))) else 0)) ≥ (transfer_from.amount st)
  /-- the call panics unless this holds -/
  gate3 : (getOr0 (transfer_from.s1 st) (Balance (transfer_from.«from» st))) ≥ (transfer_from.amount st)
  post : st.post = (transfer_from.s3 st)
  writes : st.writes = [(Allowance.amount (transfer_from.«from» st) (transfer_from.spender st)), (Allowance.live_until_ledger (transfer_from.«from» st) (transfer_from.spender st)), .has (Allowance (transfer_from.«from» st) (transfer_from.spender st)), (Balance (transfer_from.«from» st)), .has (Balance (transfer_from.«from» st)), (Balance (transfer_from.to st)), .has (Balance (transfer_from.to st))]
  ret : st.ret = 2

abbrev transfer_from : Step → Prop := fun st => transfer_from.Spec st

/-- the contract's entry points (each a `Step → Prop`; the constructor runs
    only at deployment, so it is not one of them). -/
def entries : List (Step → Prop) := [allowance, approve, balance, burn, burn_from, decimals, mint, name, set_admin, symbol, transfer, transfer_from]

/-- Keys in temporary storage: they can expire between calls. -/
def temporary : Key → Bool
  | .tup "Allowance" _ => true
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
