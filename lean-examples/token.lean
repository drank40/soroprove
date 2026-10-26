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

/-- `__constructor(admin: Address, decimal: u32, name: String, symbol: String)`
    effects, in execution order (states `__constructor.s1`, `__constructor.s2`, …):
      write storage.Admin/2 := admin
      write storage.METADATA/3 := @struct:decimal,name,symbol(And(decimal, 133143986180), name, symbol)
    conditions to succeed:
      gate: decimal < 19
-/
def __constructor : Step → Prop := fun st => ∃ u : Unk,
  st.call.fn = "__constructor" ∧
  st.call.caller ≠ pool st ∧
  (__constructor.decimal st) < 19 ∧   -- gate
  st.post = (__constructor.s2 st u) ∧
  st.writes = [Admin, .has Admin, METADATA.decimal, METADATA.name, METADATA.symbol, .has METADATA] ∧
  st.ret = 2

namespace allowance
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def spender (st : Step) : Addr := st.call.argA "spender"
end allowance

/-- `allowance(from: Address, spender: Address)`
-/
def allowance : Step → Prop := fun st =>
  st.call.fn = "allowance" ∧
  st.call.caller ≠ pool st ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (if ¬((st.pre (.has (Allowance (allowance.«from» st) (allowance.spender st)))) = 1) then 0 else (if ¬((st.call.env "sequence") > (st.pre (Allowance.live_until_ledger (allowance.«from» st) (allowance.spender st)))) then (st.pre (Allowance.amount (allowance.«from» st) (allowance.spender st))) else 0))

namespace approve
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def live_until_ledger (st : Step) : Int := st.call.arg "live_until_ledger"
@[simp] def spender (st : Step) : Addr := st.call.argA "spender"
@[simp] def s1 (st : Step) (u : Unk) : Storage :=
  (((st.pre).set (Allowance.amount (approve.«from» st) (approve.spender st)) (u.i 1)).set (Allowance.live_until_ledger (approve.«from» st) (approve.spender st)) (approve.live_until_ledger st)).set (.has (Allowance (approve.«from» st) (approve.spender st))) 1
end approve

/-- `approve(from: Address, spender: Address, amount: i128, live_until_ledger: u32)`
    effects, in execution order (states `approve.s1`, `approve.s2`, …):
      write @map:Allowance(@struct:from,spender(from, spender), @at(2)) := @struct:amount,live_until_ledger(Load, live_until_ledger)
    conditions to succeed:
      require_auth from
-/
def approve : Step → Prop := fun st => ∃ u : Unk,
  st.call.fn = "approve" ∧
  st.call.caller ≠ pool st ∧
  (approve.«from» st) ∈ st.call.signers ∧   -- require_auth from
  st.post = (approve.s1 st u) ∧
  st.writes = [(Allowance.amount (approve.«from» st) (approve.spender st)), (Allowance.live_until_ledger (approve.«from» st) (approve.spender st)), .has (Allowance (approve.«from» st) (approve.spender st))] ∧
  st.ret = 2

namespace balance
@[simp] def id (st : Step) : Addr := st.call.argA "id"
end balance

/-- `balance(id: Address)`
-/
def balance : Step → Prop := fun st =>
  st.call.fn = "balance" ∧
  st.call.caller ≠ pool st ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (getOr0 st.pre (Balance (balance.id st)))

namespace burn
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set (Balance (burn.«from» st)) ((getOr0 st.pre (Balance (burn.«from» st))) - (burn.amount st))).set (.has (Balance (burn.«from» st))) 1
end burn

/-- `burn(from: Address, amount: i128)`
    effects, in execution order (states `burn.s1`, `burn.s2`, …):
      write @map:Balance(from, @at(18)) := (Select(ICmp_EQ(@has(@map:Balance(from, @at(20))), 1), @map:Balance(from, @at(21)), 0) - amount)
    conditions to succeed:
      require_auth from
      gate: amount > -1
      gate: Select(ICmp_EQ(@has(@map:Balance(from, @at(20))), 1), @map:Balance(from, @at(21)), 0) ≥ amount
-/
def burn : Step → Prop := fun st =>
  st.call.fn = "burn" ∧
  st.call.caller ≠ pool st ∧
  (burn.«from» st) ∈ st.call.signers ∧   -- require_auth from
  (burn.amount st) > -1 ∧   -- gate
  (getOr0 st.pre (Balance (burn.«from» st))) ≥ (burn.amount st) ∧   -- gate
  st.post = (burn.s1 st) ∧
  st.writes = [(Balance (burn.«from» st)), .has (Balance (burn.«from» st))] ∧
  st.ret = 2

namespace burn_from
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def spender (st : Step) : Addr := st.call.argA "spender"
@[simp] def s1 (st : Step) : Storage :=
  if ¬((burn_from.amount st) = 0) then (((st.pre).set (Allowance.amount (burn_from.«from» st) (burn_from.spender st)) ((if ¬((st.pre (.has (Allowance (burn_from.«from» st) (burn_from.spender st)))) = 1) then 0 else (if ¬((st.call.env "sequence") > (st.pre (Allowance.live_until_ledger (burn_from.«from» st) (burn_from.spender st)))) then (st.pre (Allowance.amount (burn_from.«from» st) (burn_from.spender st))) else 0)) - (burn_from.amount st))).set (Allowance.live_until_ledger (burn_from.«from» st) (burn_from.spender st)) (getOr0 st.pre (Allowance.live_until_ledger (burn_from.«from» st) (burn_from.spender st)) (base := (Allowance (burn_from.«from» st) (burn_from.spender st))))).set (.has (Allowance (burn_from.«from» st) (burn_from.spender st))) 1 else st.pre
@[simp] def s2 (st : Step) : Storage :=
  ((burn_from.s1 st).set (Balance (burn_from.«from» st)) ((getOr0 (burn_from.s1 st) (Balance (burn_from.«from» st))) - (burn_from.amount st))).set (.has (Balance (burn_from.«from» st))) 1
end burn_from

/-- `burn_from(spender: Address, from: Address, amount: i128)`
    effects, in execution order (states `burn_from.s1`, `burn_from.s2`, …):
      write @map:Allowance(@struct:from,spender(from, spender), @at(23)) := @struct:amount,live_until_ledger((Select(@not(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(25))), 1)), 0, Select(@not(ICmp_UGT(@env:sequence, @field:live_until_ledger(@map:Allowance(@struct:from,spender(from, spender), @at(26))))), @field:amount(@map:Allowance(@struct:from,spender(from, spender), @at(26))), 0)) - amount), Select(@not(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(25))), 1)), 0, @field:live_until_ledger(@map:Allowance(@struct:from,spender(from, spender), @at(26)))))   [when ¬((burn_from.amount st) = 0)]
      write @map:Balance(from, @at(27)) := (Select(ICmp_EQ(@has(@map:Balance(from, @at(29))), 1), @map:Balance(from, @at(30)), 0) - amount)
    conditions to succeed:
      require_auth spender
      gate: amount > -1
      gate: Select(@not(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(25))), 1)), 0, Select(@and(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(25))), 1), @not(ICmp_UGT(@env:sequence, @field:live_until_ledger(@map:Allowance(@struct:from,spender(from, spender), @at(26)))))), @field:amount(@map:Allowance(@struct:from,spender(from, spender), @at(26))), 0)) ≥ amount
      gate: Select(ICmp_EQ(@has(@map:Balance(from, @at(29))), 1), @map:Balance(from, @at(30)), 0) ≥ amount
-/
def burn_from : Step → Prop := fun st =>
  st.call.fn = "burn_from" ∧
  st.call.caller ≠ pool st ∧
  (burn_from.spender st) ∈ st.call.signers ∧   -- require_auth spender
  (burn_from.amount st) > -1 ∧   -- gate
  (if ¬((st.pre (.has (Allowance (burn_from.«from» st) (burn_from.spender st)))) = 1) then 0 else (if ((st.pre (.has (Allowance (burn_from.«from» st) (burn_from.spender st)))) = 1) ∧ (¬((st.call.env "sequence") > (st.pre (Allowance.live_until_ledger (burn_from.«from» st) (burn_from.spender st))))) then (st.pre (Allowance.amount (burn_from.«from» st) (burn_from.spender st))) else 0)) ≥ (burn_from.amount st) ∧   -- gate
  (getOr0 (burn_from.s1 st) (Balance (burn_from.«from» st))) ≥ (burn_from.amount st) ∧   -- gate
  st.post = (burn_from.s2 st) ∧
  st.writes = [(Allowance.amount (burn_from.«from» st) (burn_from.spender st)), (Allowance.live_until_ledger (burn_from.«from» st) (burn_from.spender st)), .has (Allowance (burn_from.«from» st) (burn_from.spender st)), (Balance (burn_from.«from» st)), .has (Balance (burn_from.«from» st))] ∧
  st.ret = 2

/-- `decimals()`
-/
def decimals : Step → Prop := fun st =>
  st.call.fn = "decimals" ∧
  st.call.caller ≠ pool st ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre METADATA.decimal)

namespace mint
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def to (st : Step) : Addr := st.call.argA "to"
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set (Balance (mint.to st)) ((getOr0 st.pre (Balance (mint.to st))) + (mint.amount st))).set (.has (Balance (mint.to st))) 1
end mint

/-- `mint(to: Address, amount: i128)`
    effects, in execution order (states `mint.s1`, `mint.s2`, …):
      write @map:Balance(to, @at(39)) := (Select(ICmp_EQ(@has(@map:Balance(to, @at(40))), 1), @map:Balance(to, @at(41)), 0) + amount)
    conditions to succeed:
      require_auth storage.Admin/16
      gate: amount > -1
-/
def mint : Step → Prop := fun st =>
  st.call.fn = "mint" ∧
  st.call.caller ≠ pool st ∧
  (st.pre Admin) ∈ st.call.signers ∧   -- require_auth storage.Admin/16
  (mint.amount st) > -1 ∧   -- gate
  st.post = (mint.s1 st) ∧
  st.writes = [(Balance (mint.to st)), .has (Balance (mint.to st))] ∧
  st.ret = 2

/-- `name()`
-/
def name : Step → Prop := fun st =>
  st.call.fn = "name" ∧
  st.call.caller ≠ pool st ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre METADATA.name)

namespace set_admin
@[simp] def new_admin (st : Step) : Addr := st.call.argA "new_admin"
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set Admin (set_admin.new_admin st)).set (.has Admin) 1
end set_admin

/-- `set_admin(new_admin: Address)`
    effects, in execution order (states `set_admin.s1`, `set_admin.s2`, …):
      write storage.Admin/45 := new_admin
    conditions to succeed:
      require_auth storage.Admin/16
-/
def set_admin : Step → Prop := fun st =>
  st.call.fn = "set_admin" ∧
  st.call.caller ≠ pool st ∧
  (st.pre Admin) ∈ st.call.signers ∧   -- require_auth storage.Admin/16
  st.post = (set_admin.s1 st) ∧
  st.writes = [Admin, .has Admin] ∧
  st.ret = 2

/-- `symbol()`
-/
def symbol : Step → Prop := fun st =>
  st.call.fn = "symbol" ∧
  st.call.caller ≠ pool st ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre METADATA.symbol)

namespace transfer
@[simp] def amount (st : Step) : Int := st.call.arg "amount"
@[simp] def «from» (st : Step) : Addr := st.call.argA "from"
@[simp] def to_muxed (st : Step) : Addr := st.call.argA "to_muxed"
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set (Balance (transfer.«from» st)) ((getOr0 st.pre (Balance (transfer.«from» st))) - (transfer.amount st))).set (.has (Balance (transfer.«from» st))) 1
@[simp] def s2 (st : Step) : Storage :=
  ((transfer.s1 st).set (Balance (transfer.to_muxed st)) ((getOr0 (transfer.s1 st) (Balance (transfer.to_muxed st))) + (transfer.amount st))).set (.has (Balance (transfer.to_muxed st))) 1
end transfer

/-- `transfer(from: Address, to_muxed: MuxedAddress, amount: i128)`
    effects, in execution order (states `transfer.s1`, `transfer.s2`, …):
      write @map:Balance(from, @at(45)) := (Select(ICmp_EQ(@has(@map:Balance(from, @at(47))), 1), @map:Balance(from, @at(48)), 0) - amount)
      write @map:Balance(@addrof(to_muxed), @at(49)) := (Select(ICmp_EQ(@has(@map:Balance(@addrof(to_muxed), @at(52))), 1), @map:Balance(@addrof(to_muxed), @at(53)), 0) + amount)
    conditions to succeed:
      require_auth from
      gate: amount > -1
      gate: Select(ICmp_EQ(@has(@map:Balance(from, @at(47))), 1), @map:Balance(from, @at(48)), 0) ≥ amount
-/
def transfer : Step → Prop := fun st =>
  st.call.fn = "transfer" ∧
  st.call.caller ≠ pool st ∧
  (transfer.«from» st) ∈ st.call.signers ∧   -- require_auth from
  (transfer.amount st) > -1 ∧   -- gate
  (getOr0 st.pre (Balance (transfer.«from» st))) ≥ (transfer.amount st) ∧   -- gate
  st.post = (transfer.s2 st) ∧
  st.writes = [(Balance (transfer.«from» st)), .has (Balance (transfer.«from» st)), (Balance (transfer.to_muxed st)), .has (Balance (transfer.to_muxed st))] ∧
  st.ret = 2

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

/-- `transfer_from(spender: Address, from: Address, to: Address, amount: i128)`
    effects, in execution order (states `transfer_from.s1`, `transfer_from.s2`, …):
      write @map:Allowance(@struct:from,spender(from, spender), @at(56)) := @struct:amount,live_until_ledger((Select(@not(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(58))), 1)), 0, Select(@not(ICmp_UGT(@env:sequence, @field:live_until_ledger(@map:Allowance(@struct:from,spender(from, spender), @at(59))))), @field:amount(@map:Allowance(@struct:from,spender(from, spender), @at(59))), 0)) - amount), Select(@not(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(58))), 1)), 0, @field:live_until_ledger(@map:Allowance(@struct:from,spender(from, spender), @at(59)))))   [when ¬((transfer_from.amount st) = 0)]
      write @map:Balance(from, @at(60)) := (Select(ICmp_EQ(@has(@map:Balance(from, @at(62))), 1), @map:Balance(from, @at(63)), 0) - amount)
      write @map:Balance(to, @at(64)) := (Select(ICmp_EQ(@has(@map:Balance(to, @at(66))), 1), @map:Balance(to, @at(67)), 0) + amount)
    conditions to succeed:
      require_auth spender
      gate: amount > -1
      gate: Select(@not(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(58))), 1)), 0, Select(@and(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(58))), 1), @not(ICmp_UGT(@env:sequence, @field:live_until_ledger(@map:Allowance(@struct:from,spender(from, spender), @at(59)))))), @field:amount(@map:Allowance(@struct:from,spender(from, spender), @at(59))), 0)) ≥ amount
      gate: Select(ICmp_EQ(@has(@map:Balance(from, @at(62))), 1), @map:Balance(from, @at(63)), 0) ≥ amount
-/
def transfer_from : Step → Prop := fun st =>
  st.call.fn = "transfer_from" ∧
  st.call.caller ≠ pool st ∧
  (transfer_from.spender st) ∈ st.call.signers ∧   -- require_auth spender
  (transfer_from.amount st) > -1 ∧   -- gate
  (if ¬((st.pre (.has (Allowance (transfer_from.«from» st) (transfer_from.spender st)))) = 1) then 0 else (if ((st.pre (.has (Allowance (transfer_from.«from» st) (transfer_from.spender st)))) = 1) ∧ (¬((st.call.env "sequence") > (st.pre (Allowance.live_until_ledger (transfer_from.«from» st) (transfer_from.spender st))))) then (st.pre (Allowance.amount (transfer_from.«from» st) (transfer_from.spender st))) else 0)) ≥ (transfer_from.amount st) ∧   -- gate
  (getOr0 (transfer_from.s1 st) (Balance (transfer_from.«from» st))) ≥ (transfer_from.amount st) ∧   -- gate
  st.post = (transfer_from.s3 st) ∧
  st.writes = [(Allowance.amount (transfer_from.«from» st) (transfer_from.spender st)), (Allowance.live_until_ledger (transfer_from.«from» st) (transfer_from.spender st)), .has (Allowance (transfer_from.«from» st) (transfer_from.spender st)), (Balance (transfer_from.«from» st)), .has (Balance (transfer_from.«from» st)), (Balance (transfer_from.to st)), .has (Balance (transfer_from.to st))] ∧
  st.ret = 2

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [__constructor, allowance, approve, balance, burn, burn_from, decimals, mint, name, set_admin, symbol, transfer, transfer_from]

end Contract
