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

/-- `__constructor(admin: Address)`
    effects, in execution order (states `__constructor.s1`, `__constructor.s2`, …):
      write storage.Admin/2 := admin
-/
def __constructor : Step → Prop := fun st =>
  st.call.fn = "__constructor" ∧
  st.call.caller ≠ pool st ∧
  st.post = (__constructor.s1 st) ∧
  st.writes = [Admin, .has Admin] ∧
  st.ret = 2

/-- `admin()`
-/
def admin : Step → Prop := fun st =>
  st.call.fn = "admin" ∧
  st.call.caller ≠ pool st ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre Admin)

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

/-- `mint(contract: Address, minter: Address, to: Address, amount: i128)`
    effects, in execution order (states `mint.s1`, `mint.s2`, …):
      write @tup:MinterStats(@ks(contract, minter, @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(12))), (@env:sequence / @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(12))))), @at(20)) := @struct:consumed_limit((Select(@not(ICmp_EQ(@has(@tup:MinterStats(@ks(contract, minter, @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(12))), (@env:sequence / @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(12))))), @at(16))), 1)), 0, @field:consumed_limit(@tup:MinterStats(@ks(contract, minter, @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(12))), (@env:sequence / @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(12))))), @at(17)))) + amount))   [when ¬((mint.amount st) < 0) ∧ ¬((st.pre (Admin)) = (mint.minter st)) ∧ ¬(¬((st.pre (.has ((Minter ((mint.contract st)) ((mint.minter st)))))) = 1)) ∧ ¬(((getOr0 st.pre ((MinterStats.consumed_limit ((mint.contract st)) ((mint.minter st)) ((st.pre ((Minter.epoch_length ((mint.contract st)) ((mint.minter st)))))) ((Int.tdiv (st.call.env "sequence") (st.pre ((Minter.epoch_length ((mint.contract st)) ((mint.minter st))))))))) (base := (MinterStats ((mint.contract st)) ((mint.minter st)) ((st.pre ((Minter.epoch_length ((mint.contract st)) ((mint.minter st)))))) ((Int.tdiv (st.call.env "sequence") (st.pre ((Minter.epoch_length ((mint.contract st)) ((mint.minter st)))))))))) + (mint.amount st)) > (st.pre ((Minter.limit ((mint.contract st)) ((mint.minter st))))))]
      call into another contract: token ledgers open   [when ((¬((mint.amount st) < 0)) ∧ ((st.pre (Admin)) = (mint.minter st))) ∨ ((¬((mint.amount st) < 0)) ∧ (¬((st.pre (Admin)) = (mint.minter st))) ∧ (¬(¬((st.pre (.has ((Minter ((mint.contract st)) ((mint.minter st)))))) = 1))) ∧ (¬(((getOr0 st.pre ((MinterStats.consumed_limit ((mint.contract st)) ((mint.minter st)) ((st.pre ((Minter.epoch_length ((mint.contract st)) ((mint.minter st)))))) ((Int.tdiv (st.call.env "sequence") (st.pre ((Minter.epoch_length ((mint.contract st)) ((mint.minter st))))))))) (base := (MinterStats ((mint.contract st)) ((mint.minter st)) ((st.pre ((Minter.epoch_length ((mint.contract st)) ((mint.minter st)))))) ((Int.tdiv (st.call.env "sequence") (st.pre ((Minter.epoch_length ((mint.contract st)) ((mint.minter st)))))))))) + (mint.amount st)) > (st.pre ((Minter.limit ((mint.contract st)) ((mint.minter st))))))))]
    conditions to succeed:
      require_auth minter
      returns Ok
-/
def mint : Step → Prop := fun st => ∃ u : Unk,
  st.call.fn = "mint" ∧
  st.call.caller ≠ pool st ∧
  (mint.minter st) ∈ st.call.signers ∧   -- require_auth minter
  (((¬((mint.amount st) < 0)) ∧ ((st.pre Admin) = (mint.minter st))) ∨ ((¬((mint.amount st) < 0)) ∧ (¬((st.pre Admin) = (mint.minter st))) ∧ (¬(¬((st.pre (.has (Minter (mint.contract st) (mint.minter st)))) = 1))) ∧ (¬(((getOr0 st.pre (MinterStats.consumed_limit (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))) (base := (MinterStats (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))))) + (mint.amount st)) > (st.pre (Minter.limit (mint.contract st) (mint.minter st))))))) ∧   -- returns Ok
  st.post = (mint.s2 st u) ∧
  st.writes = [(MinterStats.consumed_limit (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))), .has (MinterStats (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st)))))] ∧
  st.ret = (if ((¬((mint.amount st) < 0)) ∧ ((st.pre Admin) = (mint.minter st))) ∨ ((¬((mint.amount st) < 0)) ∧ (¬((st.pre Admin) = (mint.minter st))) ∧ (¬(¬((st.pre (.has (Minter (mint.contract st) (mint.minter st)))) = 1))) ∧ (¬(((getOr0 st.pre (MinterStats.consumed_limit (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))) (base := (MinterStats (mint.contract st) (mint.minter st) (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))) (Int.tdiv (st.call.env "sequence") (st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))))))) + (mint.amount st)) > (st.pre (Minter.limit (mint.contract st) (mint.minter st)))))) then 2 else (if (mint.amount st) < 0 then 12884901891 else (if ¬((st.pre (.has (Minter (mint.contract st) (mint.minter st)))) = 1) then 4294967299 else 8589934595)))

namespace minter
@[simp] def contract (st : Step) : Addr := st.call.argA "contract"
@[simp] def minter (st : Step) : Addr := st.call.argA "minter"
end minter

/-- `minter(contract: Address, minter: Address)`
-/
def minter : Step → Prop := fun st => ∃ u : Unk,
  st.call.fn = "minter" ∧
  st.call.caller ≠ pool st ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (if ¬(¬((st.pre (.has (Minter (minter.contract st) (minter.minter st)))) = 1)) then (u.i 1) else 4294967299)

namespace set_admin
@[simp] def new_admin (st : Step) : Addr := st.call.argA "new_admin"
@[simp] def s1 (st : Step) : Storage :=
  ((st.pre).set Admin (set_admin.new_admin st)).set (.has Admin) 1
end set_admin

/-- `set_admin(new_admin: Address)`
    effects, in execution order (states `set_admin.s1`, `set_admin.s2`, …):
      write storage.Admin/35 := new_admin
    conditions to succeed:
      require_auth storage.Admin/2
-/
def set_admin : Step → Prop := fun st =>
  st.call.fn = "set_admin" ∧
  st.call.caller ≠ pool st ∧
  (st.pre Admin) ∈ st.call.signers ∧   -- require_auth storage.Admin/2
  st.post = (set_admin.s1 st) ∧
  st.writes = [Admin, .has Admin] ∧
  st.ret = 2

namespace set_minter
@[simp] def config.epoch_length (st : Step) : Int := st.call.arg "config.epoch_length"
@[simp] def config.limit (st : Step) : Int := st.call.arg "config.limit"
@[simp] def contract (st : Step) : Addr := st.call.argA "contract"
@[simp] def minter (st : Step) : Addr := st.call.argA "minter"
@[simp] def s1 (st : Step) : Storage :=
  (((st.pre).set (Minter.epoch_length (set_minter.contract st) (set_minter.minter st)) (set_minter.config.epoch_length st)).set (Minter.limit (set_minter.contract st) (set_minter.minter st)) (set_minter.config.limit st)).set (.has (Minter (set_minter.contract st) (set_minter.minter st))) 1
end set_minter

/-- `set_minter(contract: Address, minter: Address, config: MinterConfig)`
    effects, in execution order (states `set_minter.s1`, `set_minter.s2`, …):
      write @tup:Minter(@ks(contract, minter), @at(38)) := @struct:epoch_length,limit(@field:epoch_length(config), @field:limit(config))
    conditions to succeed:
      require_auth storage.Admin/2
-/
def set_minter : Step → Prop := fun st =>
  st.call.fn = "set_minter" ∧
  st.call.caller ≠ pool st ∧
  (st.pre Admin) ∈ st.call.signers ∧   -- require_auth storage.Admin/2
  st.post = (set_minter.s1 st) ∧
  st.writes = [(Minter.epoch_length (set_minter.contract st) (set_minter.minter st)), (Minter.limit (set_minter.contract st) (set_minter.minter st)), .has (Minter (set_minter.contract st) (set_minter.minter st))] ∧
  st.ret = 2

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [__constructor, admin, mint, minter, set_admin, set_minter]

end Contract
