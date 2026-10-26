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

/-- `__constructor(admin: Address)`
    effects, in execution order:
      write storage.Admin/2 := admin
-/
def __constructor : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  let s1 := ((st.pre).set (.var "Admin") (st.call.argA "admin")).set (.has (.var "Admin")) (1)
  st.call.fn = "__constructor" ∧
  c ≠ pool ∧
  st.post = s1 ∧
  st.writes = [.var "Admin", .has (.var "Admin")] ∧
  st.ret = 2

/-- `admin()`
-/
def admin : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  st.call.fn = "admin" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre (.var "Admin"))

/-- `mint(contract: Address, minter: Address, to: Address, amount: i128)`
    effects, in execution order:
      write @tup:MinterStats(@ks(contract, minter, @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(12))), (@env:sequence / @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(12))))), @at(20)) := @struct:consumed_limit((Select(@not(ICmp_EQ(@has(@tup:MinterStats(@ks(contract, minter, @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(12))), (@env:sequence / @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(12))))), @at(16))), 1)), 0, @field:consumed_limit(@tup:MinterStats(@ks(contract, minter, @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(12))), (@env:sequence / @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(12))))), @at(17)))) + amount))   [when ¬(st.call.arg "amount" < 0) ∧ ¬((st.pre (.var "Admin")) = st.call.argA "minter") ∧ ¬(¬((st.pre (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]))) = 1)) ∧ ¬(((getOr0 st.pre (.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit") (base := .tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))])) + st.call.arg "amount") > (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit")))]
      call into another contract: token ledgers open   [when ((¬(st.call.arg "amount" < 0)) ∧ ((st.pre (.var "Admin")) = st.call.argA "minter")) ∨ ((¬(st.call.arg "amount" < 0)) ∧ (¬((st.pre (.var "Admin")) = st.call.argA "minter")) ∧ (¬(¬((st.pre (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]))) = 1))) ∧ (¬(((getOr0 st.pre (.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit") (base := .tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))])) + st.call.arg "amount") > (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit")))))]
    conditions to succeed:
      require_auth minter
      returns Ok
-/
def mint : Step → Prop := fun st => ∃ u : Unk,
  let c := st.call.caller
  let pool := st.call.self
  let s1 := if ¬(st.call.arg "amount" < 0) ∧ ¬((st.pre (.var "Admin")) = st.call.argA "minter") ∧ ¬(¬((st.pre (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]))) = 1)) ∧ ¬(((getOr0 st.pre (.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit") (base := .tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))])) + st.call.arg "amount") > (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit"))) then ((st.pre).set (.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit") (((getOr0 st.pre (.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit") (base := .tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))])) + st.call.arg "amount"))).set (.has (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))])) (1) else st.pre
  let s2 := if ((¬(st.call.arg "amount" < 0)) ∧ ((st.pre (.var "Admin")) = st.call.argA "minter")) ∨ ((¬(st.call.arg "amount" < 0)) ∧ (¬((st.pre (.var "Admin")) = st.call.argA "minter")) ∧ (¬(¬((st.pre (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]))) = 1))) ∧ (¬(((getOr0 st.pre (.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit") (base := .tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))])) + st.call.arg "amount") > (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit"))))) then havoc s1 (u.s 1) else s1
  st.call.fn = "mint" ∧
  c ≠ pool ∧
  st.call.argA "minter" ∈ st.call.signers ∧   -- require_auth minter
  (((¬(st.call.arg "amount" < 0)) ∧ ((st.pre (.var "Admin")) = st.call.argA "minter")) ∨ ((¬(st.call.arg "amount" < 0)) ∧ (¬((st.pre (.var "Admin")) = st.call.argA "minter")) ∧ (¬(¬((st.pre (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]))) = 1))) ∧ (¬(((getOr0 st.pre (.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit") (base := .tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))])) + st.call.arg "amount") > (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit")))))) ∧   -- returns Ok
  st.post = s2 ∧
  st.writes = [.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit", .has (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))])] ∧
  st.ret = (if ((¬(st.call.arg "amount" < 0)) ∧ ((st.pre (.var "Admin")) = st.call.argA "minter")) ∨ ((¬(st.call.arg "amount" < 0)) ∧ (¬((st.pre (.var "Admin")) = st.call.argA "minter")) ∧ (¬(¬((st.pre (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]))) = 1))) ∧ (¬(((getOr0 st.pre (.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit") (base := .tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))])) + st.call.arg "amount") > (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit"))))) then 2 else (if st.call.arg "amount" < 0 then 12884901891 else (if ¬((st.pre (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]))) = 1) then 4294967299 else 8589934595)))

/-- `minter(contract: Address, minter: Address)`
-/
def minter : Step → Prop := fun st => ∃ u : Unk,
  let c := st.call.caller
  let pool := st.call.self
  st.call.fn = "minter" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (if ¬(¬((st.pre (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]))) = 1)) then (u.i 1) else 4294967299)

/-- `set_admin(new_admin: Address)`
    effects, in execution order:
      write storage.Admin/35 := new_admin
    conditions to succeed:
      require_auth storage.Admin/2
-/
def set_admin : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  let s1 := ((st.pre).set (.var "Admin") (st.call.argA "new_admin")).set (.has (.var "Admin")) (1)
  st.call.fn = "set_admin" ∧
  c ≠ pool ∧
  (st.pre (.var "Admin")) ∈ st.call.signers ∧   -- require_auth storage.Admin/2
  st.post = s1 ∧
  st.writes = [.var "Admin", .has (.var "Admin")] ∧
  st.ret = 2

/-- `set_minter(contract: Address, minter: Address, config: MinterConfig)`
    effects, in execution order:
      write @tup:Minter(@ks(contract, minter), @at(38)) := @struct:epoch_length,limit(@field:epoch_length(config), @field:limit(config))
    conditions to succeed:
      require_auth storage.Admin/2
-/
def set_minter : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  let s1 := (((st.pre).set (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length") (st.call.arg "config.epoch_length")).set (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit") (st.call.arg "config.limit")).set (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"])) (1)
  st.call.fn = "set_minter" ∧
  c ≠ pool ∧
  (st.pre (.var "Admin")) ∈ st.call.signers ∧   -- require_auth storage.Admin/2
  st.post = s1 ∧
  st.writes = [.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length", .fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit", .has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"])] ∧
  st.ret = 2

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [__constructor, admin, mint, minter, set_admin, set_minter]

end Contract
