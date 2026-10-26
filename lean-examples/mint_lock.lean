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

/-- `__constructor(admin: Address)`
    effects (reconstructed, in program order):
      write storage.Admin/9 := admin
-/
def __constructor : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := ((st.pre).set (.var "Admin") (st.call.argA "admin")).set (.has (.var "Admin")) (1)
  st.call.fn = "__constructor" ∧
  c ≠ pool ∧
  st.post = s1 ∧
  st.writes = [.var "Admin", .has (.var "Admin")] ∧
  st.ret = 0

/-- `admin()`
    effects (reconstructed, in program order):
-/
def admin : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "admin" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre (.var "Admin"))

/-- `mint(contract: Address, minter: Address, to: Address, amount: i128)`
    effects (reconstructed, in program order):
      write @tup:MinterStats(@ks(contract, minter, @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(77))), (@env:sequence / @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(77))))), @at(133)) [when ¬(st.call.arg "amount" < 0) ∧ ¬((st.pre (.var "Admin")) = st.call.argA "minter") ∧ ¬(¬((st.pre (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]))) = 1)) ∧ ¬(((st.pre (.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit")) + st.call.arg "amount") > (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit")))] := @struct:consumed_limit((@field:consumed_limit(@tup:MinterStats(@ks(contract, minter, @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(77))), (@env:sequence / @field:epoch_length(@tup:Minter(@ks(contract, minter), @at(77))))), @at(100))) + amount))
    guards (recovered panic/gate conditions):
      auth: caller signed as `minter` (require_auth)
-/
def mint : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := if ¬(st.call.arg "amount" < 0) ∧ ¬((st.pre (.var "Admin")) = st.call.argA "minter") ∧ ¬(¬((st.pre (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]))) = 1)) ∧ ¬(((st.pre (.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit")) + st.call.arg "amount") > (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit"))) then ((st.pre).set (.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit") (((st.pre (.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit")) + st.call.arg "amount"))).set (.has (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))])) (1) else st.pre
  st.call.fn = "mint" ∧
  c ≠ pool ∧
  c = st.call.argA "minter" ∧   -- require_auth
  (((¬(st.call.arg "amount" < 0)) ∧ ((st.pre (.var "Admin")) = st.call.argA "minter")) ∨ ((¬(st.call.arg "amount" < 0)) ∧ (¬((st.pre (.var "Admin")) = st.call.argA "minter")) ∧ (¬(¬((st.pre (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]))) = 1))) ∧ (¬(((st.pre (.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit")) + st.call.arg "amount") > (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit")))))) ∧   -- returns Ok (an Err return fails the call)
  st.post = s1 ∧
  st.writes = [.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit", .has (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))])] ∧
  st.ret = (if ((¬(st.call.arg "amount" < 0)) ∧ ((st.pre (.var "Admin")) = st.call.argA "minter")) ∨ ((¬(st.call.arg "amount" < 0)) ∧ (¬((st.pre (.var "Admin")) = st.call.argA "minter")) ∧ (¬(¬((st.pre (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]))) = 1))) ∧ (¬(((st.pre (.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter", (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")), (Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length")))]) "consumed_limit")) + st.call.arg "amount") > (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit"))))) then 2 else (if st.call.arg "amount" < 0 then 12884901891 else (if ((¬(st.call.arg "amount" < 0)) ∧ (¬((st.pre (.var "Admin")) = st.call.argA "minter"))) ∧ (¬((st.pre (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]))) = 1)) then 4294967299 else 8589934595)))

/-- `minter(contract: Address, minter: Address)`
    effects (reconstructed, in program order):
-/
opaque minter_e_g1 : Step → Int
def minter : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "minter" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (if ¬(¬((st.pre (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]))) = 1)) then (minter_e_g1 st) else 4294967299)

/-- `set_admin(new_admin: Address)`
    effects (reconstructed, in program order):
      write storage.Admin/12 := new_admin
-/
def set_admin : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := ((st.pre).set (.var "Admin") (st.call.argA "new_admin")).set (.has (.var "Admin")) (1)
  st.call.fn = "set_admin" ∧
  c ≠ pool ∧
  st.call.signed (st.pre (.var "Admin")) ∧   -- require_auth
  st.post = s1 ∧
  st.writes = [.var "Admin", .has (.var "Admin")] ∧
  st.ret = 0

/-- `set_minter(contract: Address, minter: Address, config: MinterConfig)`
    effects (reconstructed, in program order):
      write @tup:Minter(@ks(contract, minter), @at(44)) := @struct:epoch_length,limit(@field:epoch_length(config), @field:limit(config))
-/
def set_minter : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (((st.pre).set (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length") (st.call.arg "config.epoch_length")).set (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit") (st.call.arg "config.limit")).set (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"])) (1)
  st.call.fn = "set_minter" ∧
  c ≠ pool ∧
  st.call.signed (st.pre (.var "Admin")) ∧   -- require_auth
  st.post = s1 ∧
  st.writes = [.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length", .fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit", .has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"])] ∧
  st.ret = 0

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [__constructor, admin, mint, minter, set_admin, set_minter]

end Contract
