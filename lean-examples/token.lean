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

/-- `__constructor(admin: Address, decimal: u32, name: String, symbol: String)`
    effects, in execution order:
      write storage.Admin/2 := admin
      write storage.METADATA/3 := @struct:decimal,name,symbol(And(decimal, 133143986180), name, symbol)
    conditions to succeed:
      gate: decimal < 19
-/
def __constructor : Step → Prop := fun st => ∃ u : Unk,
  let c := st.call.caller
  let pool := st.call.self
  let s1 := ((st.pre).set (.var "Admin") (st.call.argA "admin")).set (.has (.var "Admin")) (1)
  let s2 := ((((s1).set (.fld (.var "METADATA") "decimal") ((u.i 1))).set (.fld (.var "METADATA") "name") (st.call.arg "name")).set (.fld (.var "METADATA") "symbol") (st.call.arg "symbol")).set (.has (.var "METADATA")) (1)
  st.call.fn = "__constructor" ∧
  c ≠ pool ∧
  st.call.arg "decimal" < 19 ∧   -- gate
  st.post = s2 ∧
  st.writes = [.var "Admin", .has (.var "Admin"), .fld (.var "METADATA") "decimal", .fld (.var "METADATA") "name", .fld (.var "METADATA") "symbol", .has (.var "METADATA")] ∧
  st.ret = 2

/-- `allowance(from: Address, spender: Address)`
-/
def allowance : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  st.call.fn = "allowance" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (if ¬((st.pre (.has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]))) = 1) then 0 else (if ¬((st.call.env "sequence") > (st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger"))) then (st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount")) else 0))

/-- `approve(from: Address, spender: Address, amount: i128, live_until_ledger: u32)`
    effects, in execution order:
      write @map:Allowance(@struct:from,spender(from, spender), @at(2)) := @struct:amount,live_until_ledger(Load, live_until_ledger)
    conditions to succeed:
      require_auth from
-/
def approve : Step → Prop := fun st => ∃ u : Unk,
  let c := st.call.caller
  let pool := st.call.self
  let s1 := (((st.pre).set (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount") ((u.i 1))).set (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger") (st.call.arg "live_until_ledger")).set (.has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"])) (1)
  st.call.fn = "approve" ∧
  c ≠ pool ∧
  st.call.argA "from" ∈ st.call.signers ∧   -- require_auth from
  st.post = s1 ∧
  st.writes = [.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount", .fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger", .has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"])] ∧
  st.ret = 2

/-- `balance(id: Address)`
-/
def balance : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  st.call.fn = "balance" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (getOr0 st.pre (.entry "Balance" (st.call.argA "id")))

/-- `burn(from: Address, amount: i128)`
    effects, in execution order:
      write @map:Balance(from, @at(18)) := (Select(ICmp_EQ(@has(@map:Balance(from, @at(20))), 1), @map:Balance(from, @at(21)), 0) - amount)
    conditions to succeed:
      require_auth from
      gate: amount > -1
      gate: Select(ICmp_EQ(@has(@map:Balance(from, @at(20))), 1), @map:Balance(from, @at(21)), 0) ≥ amount
-/
def burn : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  let s1 := ((st.pre).set (.entry "Balance" (st.call.argA "from")) (((getOr0 st.pre (.entry "Balance" (st.call.argA "from"))) - st.call.arg "amount"))).set (.has (.entry "Balance" (st.call.argA "from"))) (1)
  st.call.fn = "burn" ∧
  c ≠ pool ∧
  st.call.argA "from" ∈ st.call.signers ∧   -- require_auth from
  st.call.arg "amount" > -1 ∧   -- gate
  (getOr0 st.pre (.entry "Balance" (st.call.argA "from"))) ≥ st.call.arg "amount" ∧   -- gate
  st.post = s1 ∧
  st.writes = [.entry "Balance" (st.call.argA "from"), .has (.entry "Balance" (st.call.argA "from"))] ∧
  st.ret = 2

/-- `burn_from(spender: Address, from: Address, amount: i128)`
    effects, in execution order:
      write @map:Allowance(@struct:from,spender(from, spender), @at(23)) := @struct:amount,live_until_ledger((Select(@not(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(25))), 1)), 0, Select(@not(ICmp_UGT(@env:sequence, @field:live_until_ledger(@map:Allowance(@struct:from,spender(from, spender), @at(26))))), @field:amount(@map:Allowance(@struct:from,spender(from, spender), @at(26))), 0)) - amount), Select(@not(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(25))), 1)), 0, @field:live_until_ledger(@map:Allowance(@struct:from,spender(from, spender), @at(26)))))   [when ¬(st.call.arg "amount" = 0)]
      write @map:Balance(from, @at(27)) := (Select(ICmp_EQ(@has(@map:Balance(from, @at(29))), 1), @map:Balance(from, @at(30)), 0) - amount)
    conditions to succeed:
      require_auth spender
      gate: amount > -1
      gate: Select(@not(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(25))), 1)), 0, Select(@and(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(25))), 1), @not(ICmp_UGT(@env:sequence, @field:live_until_ledger(@map:Allowance(@struct:from,spender(from, spender), @at(26)))))), @field:amount(@map:Allowance(@struct:from,spender(from, spender), @at(26))), 0)) ≥ amount
      gate: Select(ICmp_EQ(@has(@map:Balance(from, @at(29))), 1), @map:Balance(from, @at(30)), 0) ≥ amount
-/
def burn_from : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  let s1 := if ¬(st.call.arg "amount" = 0) then (((st.pre).set (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount") (((if ¬((st.pre (.has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]))) = 1) then 0 else (if ¬((st.call.env "sequence") > (st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger"))) then (st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount")) else 0)) - st.call.arg "amount"))).set (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger") ((getOr0 st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger") (base := .tup "Allowance" [st.call.argA "from", st.call.argA "spender"])))).set (.has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"])) (1) else st.pre
  let s2 := ((s1).set (.entry "Balance" (st.call.argA "from")) (((getOr0 s1 (.entry "Balance" (st.call.argA "from"))) - st.call.arg "amount"))).set (.has (.entry "Balance" (st.call.argA "from"))) (1)
  st.call.fn = "burn_from" ∧
  c ≠ pool ∧
  st.call.argA "spender" ∈ st.call.signers ∧   -- require_auth spender
  st.call.arg "amount" > -1 ∧   -- gate
  (if ¬((st.pre (.has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]))) = 1) then 0 else (if ((st.pre (.has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]))) = 1) ∧ (¬((st.call.env "sequence") > (st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger")))) then (st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount")) else 0)) ≥ st.call.arg "amount" ∧   -- gate
  (getOr0 s1 (.entry "Balance" (st.call.argA "from"))) ≥ st.call.arg "amount" ∧   -- gate
  st.post = s2 ∧
  st.writes = [.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount", .fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger", .has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]), .entry "Balance" (st.call.argA "from"), .has (.entry "Balance" (st.call.argA "from"))] ∧
  st.ret = 2

/-- `decimals()`
-/
def decimals : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  st.call.fn = "decimals" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre (.fld (.var "METADATA") "decimal"))

/-- `mint(to: Address, amount: i128)`
    effects, in execution order:
      write @map:Balance(to, @at(39)) := (Select(ICmp_EQ(@has(@map:Balance(to, @at(40))), 1), @map:Balance(to, @at(41)), 0) + amount)
    conditions to succeed:
      require_auth storage.Admin/16
      gate: amount > -1
-/
def mint : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  let s1 := ((st.pre).set (.entry "Balance" (st.call.argA "to")) (((getOr0 st.pre (.entry "Balance" (st.call.argA "to"))) + st.call.arg "amount"))).set (.has (.entry "Balance" (st.call.argA "to"))) (1)
  st.call.fn = "mint" ∧
  c ≠ pool ∧
  (st.pre (.var "Admin")) ∈ st.call.signers ∧   -- require_auth storage.Admin/16
  st.call.arg "amount" > -1 ∧   -- gate
  st.post = s1 ∧
  st.writes = [.entry "Balance" (st.call.argA "to"), .has (.entry "Balance" (st.call.argA "to"))] ∧
  st.ret = 2

/-- `name()`
-/
def name : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  st.call.fn = "name" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre (.fld (.var "METADATA") "name"))

/-- `set_admin(new_admin: Address)`
    effects, in execution order:
      write storage.Admin/45 := new_admin
    conditions to succeed:
      require_auth storage.Admin/16
-/
def set_admin : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  let s1 := ((st.pre).set (.var "Admin") (st.call.argA "new_admin")).set (.has (.var "Admin")) (1)
  st.call.fn = "set_admin" ∧
  c ≠ pool ∧
  (st.pre (.var "Admin")) ∈ st.call.signers ∧   -- require_auth storage.Admin/16
  st.post = s1 ∧
  st.writes = [.var "Admin", .has (.var "Admin")] ∧
  st.ret = 2

/-- `symbol()`
-/
def symbol : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  st.call.fn = "symbol" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre (.fld (.var "METADATA") "symbol"))

/-- `transfer(from: Address, to_muxed: MuxedAddress, amount: i128)`
    effects, in execution order:
      write @map:Balance(from, @at(45)) := (Select(ICmp_EQ(@has(@map:Balance(from, @at(47))), 1), @map:Balance(from, @at(48)), 0) - amount)
      write @map:Balance(@addrof(to_muxed), @at(49)) := (Select(ICmp_EQ(@has(@map:Balance(@addrof(to_muxed), @at(52))), 1), @map:Balance(@addrof(to_muxed), @at(53)), 0) + amount)
    conditions to succeed:
      require_auth from
      gate: amount > -1
      gate: Select(ICmp_EQ(@has(@map:Balance(from, @at(47))), 1), @map:Balance(from, @at(48)), 0) ≥ amount
-/
def transfer : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  let s1 := ((st.pre).set (.entry "Balance" (st.call.argA "from")) (((getOr0 st.pre (.entry "Balance" (st.call.argA "from"))) - st.call.arg "amount"))).set (.has (.entry "Balance" (st.call.argA "from"))) (1)
  let s2 := ((s1).set (.entry "Balance" (st.call.argA "to_muxed")) (((getOr0 s1 (.entry "Balance" (st.call.argA "to_muxed"))) + st.call.arg "amount"))).set (.has (.entry "Balance" (st.call.argA "to_muxed"))) (1)
  st.call.fn = "transfer" ∧
  c ≠ pool ∧
  st.call.argA "from" ∈ st.call.signers ∧   -- require_auth from
  st.call.arg "amount" > -1 ∧   -- gate
  (getOr0 st.pre (.entry "Balance" (st.call.argA "from"))) ≥ st.call.arg "amount" ∧   -- gate
  st.post = s2 ∧
  st.writes = [.entry "Balance" (st.call.argA "from"), .has (.entry "Balance" (st.call.argA "from")), .entry "Balance" (st.call.argA "to_muxed"), .has (.entry "Balance" (st.call.argA "to_muxed"))] ∧
  st.ret = 2

/-- `transfer_from(spender: Address, from: Address, to: Address, amount: i128)`
    effects, in execution order:
      write @map:Allowance(@struct:from,spender(from, spender), @at(56)) := @struct:amount,live_until_ledger((Select(@not(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(58))), 1)), 0, Select(@not(ICmp_UGT(@env:sequence, @field:live_until_ledger(@map:Allowance(@struct:from,spender(from, spender), @at(59))))), @field:amount(@map:Allowance(@struct:from,spender(from, spender), @at(59))), 0)) - amount), Select(@not(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(58))), 1)), 0, @field:live_until_ledger(@map:Allowance(@struct:from,spender(from, spender), @at(59)))))   [when ¬(st.call.arg "amount" = 0)]
      write @map:Balance(from, @at(60)) := (Select(ICmp_EQ(@has(@map:Balance(from, @at(62))), 1), @map:Balance(from, @at(63)), 0) - amount)
      write @map:Balance(to, @at(64)) := (Select(ICmp_EQ(@has(@map:Balance(to, @at(66))), 1), @map:Balance(to, @at(67)), 0) + amount)
    conditions to succeed:
      require_auth spender
      gate: amount > -1
      gate: Select(@not(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(58))), 1)), 0, Select(@and(ICmp_EQ(@has(@map:Allowance(@struct:from,spender(from, spender), @at(58))), 1), @not(ICmp_UGT(@env:sequence, @field:live_until_ledger(@map:Allowance(@struct:from,spender(from, spender), @at(59)))))), @field:amount(@map:Allowance(@struct:from,spender(from, spender), @at(59))), 0)) ≥ amount
      gate: Select(ICmp_EQ(@has(@map:Balance(from, @at(62))), 1), @map:Balance(from, @at(63)), 0) ≥ amount
-/
def transfer_from : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  let s1 := if ¬(st.call.arg "amount" = 0) then (((st.pre).set (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount") (((if ¬((st.pre (.has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]))) = 1) then 0 else (if ¬((st.call.env "sequence") > (st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger"))) then (st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount")) else 0)) - st.call.arg "amount"))).set (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger") ((getOr0 st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger") (base := .tup "Allowance" [st.call.argA "from", st.call.argA "spender"])))).set (.has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"])) (1) else st.pre
  let s2 := ((s1).set (.entry "Balance" (st.call.argA "from")) (((getOr0 s1 (.entry "Balance" (st.call.argA "from"))) - st.call.arg "amount"))).set (.has (.entry "Balance" (st.call.argA "from"))) (1)
  let s3 := ((s2).set (.entry "Balance" (st.call.argA "to")) (((getOr0 s2 (.entry "Balance" (st.call.argA "to"))) + st.call.arg "amount"))).set (.has (.entry "Balance" (st.call.argA "to"))) (1)
  st.call.fn = "transfer_from" ∧
  c ≠ pool ∧
  st.call.argA "spender" ∈ st.call.signers ∧   -- require_auth spender
  st.call.arg "amount" > -1 ∧   -- gate
  (if ¬((st.pre (.has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]))) = 1) then 0 else (if ((st.pre (.has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]))) = 1) ∧ (¬((st.call.env "sequence") > (st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger")))) then (st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount")) else 0)) ≥ st.call.arg "amount" ∧   -- gate
  (getOr0 s1 (.entry "Balance" (st.call.argA "from"))) ≥ st.call.arg "amount" ∧   -- gate
  st.post = s3 ∧
  st.writes = [.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount", .fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger", .has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]), .entry "Balance" (st.call.argA "from"), .has (.entry "Balance" (st.call.argA "from")), .entry "Balance" (st.call.argA "to"), .has (.entry "Balance" (st.call.argA "to"))] ∧
  st.ret = 2

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [__constructor, allowance, approve, balance, burn, burn_from, decimals, mint, name, set_admin, symbol, transfer, transfer_from]

end Contract
