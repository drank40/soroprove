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

/-- `__constructor(admin: Address, decimal: u32, name: String, symbol: String)`
    effects (reconstructed, in program order):
      write storage.Admin/34 := admin
      write storage.METADATA/54 := @struct:decimal,name,symbol(And(decimal, 133143986180), name, symbol)
    guards (recovered panic/gate conditions):
      gate: decimal < 19
-/
opaque __constructor_e_g1 : Step → Int
def __constructor : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := ((st.pre).set (.var "Admin") (st.call.argA "admin")).set (.has (.var "Admin")) (1)
  let s2 := ((((s1).set (.fld (.var "METADATA") "decimal") ((__constructor_e_g1 st))).set (.fld (.var "METADATA") "name") (st.call.arg "name")).set (.fld (.var "METADATA") "symbol") (st.call.arg "symbol")).set (.has (.var "METADATA")) (1)
  st.call.fn = "__constructor" ∧
  c ≠ pool ∧
  st.call.arg "decimal" < 19 ∧   -- gate
  st.post = s2 ∧
  st.writes = [.var "Admin", .has (.var "Admin"), .fld (.var "METADATA") "decimal", .fld (.var "METADATA") "name", .fld (.var "METADATA") "symbol", .has (.var "METADATA")] ∧
  st.ret = 0

/-- `allowance(from: Address, spender: Address)`
    effects (reconstructed, in program order):
-/
def allowance : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "allowance" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount"))

/-- `approve(from: Address, spender: Address, amount: i128, live_until_ledger: u32)`
    effects (reconstructed, in program order):
      write @map:Allowance(@struct:from,spender(from, spender), @at(53)) := @struct:amount,live_until_ledger(Load, live_until_ledger)
    guards (recovered panic/gate conditions):
      auth: caller signed as `from` (require_auth)
-/
opaque approve_e_g1 : Step → Int
def approve : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (((st.pre).set (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount") ((approve_e_g1 st))).set (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger") (st.call.arg "live_until_ledger")).set (.has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"])) (1)
  st.call.fn = "approve" ∧
  c ≠ pool ∧
  c = st.call.argA "from" ∧   -- require_auth
  st.post = s1 ∧
  st.writes = [.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount", .fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger", .has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"])] ∧
  st.ret = 0

/-- `balance(id: Address)`
    effects (reconstructed, in program order):
-/
def balance : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "balance" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre (.entry "Balance" (st.call.argA "id")))

/-- `burn(from: Address, amount: i128)`
    effects (reconstructed, in program order):
      write @map:Balance(from, @at(57)) := (@map:Balance(from, @at(35)) - amount)
    guards (recovered panic/gate conditions):
      auth: caller signed as `from` (require_auth)
      gate: amount > -1
      gate: @map:Balance(from, @at(35)) ≥ amount
-/
def burn : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := ((st.pre).set (.entry "Balance" (st.call.argA "from")) (((st.pre (.entry "Balance" (st.call.argA "from"))) - st.call.arg "amount"))).set (.has (.entry "Balance" (st.call.argA "from"))) (1)
  st.call.fn = "burn" ∧
  c ≠ pool ∧
  c = st.call.argA "from" ∧   -- require_auth
  st.call.arg "amount" > -1 ∧   -- gate
  (st.pre (.entry "Balance" (st.call.argA "from"))) ≥ st.call.arg "amount" ∧   -- gate
  st.post = s1 ∧
  st.writes = [.entry "Balance" (st.call.argA "from"), .has (.entry "Balance" (st.call.argA "from"))] ∧
  st.ret = 0

/-- `burn_from(spender: Address, from: Address, amount: i128)`
    effects (reconstructed, in program order):
      write @map:Allowance(@struct:from,spender(from, spender), @at(62)) [when ¬(st.call.arg "amount" = 0)] := @struct:amount,live_until_ledger((@field:amount(@map:Allowance(@struct:from,spender(from, spender), @at(40))) - amount), @field:live_until_ledger(@map:Allowance(@struct:from,spender(from, spender), @at(40))))
      write @map:Balance(from, @at(90)) := (@map:Balance(from, @at(68)) - amount)
    guards (recovered panic/gate conditions):
      auth: caller signed as `spender` (require_auth)
      gate: amount > -1
      gate: @field:amount(@map:Allowance(@struct:from,spender(from, spender), @at(40))) ≥ amount
      gate: @map:Balance(from, @at(68)) ≥ amount
-/
def burn_from : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := if ¬(st.call.arg "amount" = 0) then (((st.pre).set (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount") (((st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount")) - st.call.arg "amount"))).set (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger") ((st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger")))).set (.has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"])) (1) else st.pre
  let s2 := ((s1).set (.entry "Balance" (st.call.argA "from")) (((s1 (.entry "Balance" (st.call.argA "from"))) - st.call.arg "amount"))).set (.has (.entry "Balance" (st.call.argA "from"))) (1)
  st.call.fn = "burn_from" ∧
  c ≠ pool ∧
  c = st.call.argA "spender" ∧   -- require_auth
  st.call.arg "amount" > -1 ∧   -- gate
  (st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount")) ≥ st.call.arg "amount" ∧   -- gate
  (s1 (.entry "Balance" (st.call.argA "from"))) ≥ st.call.arg "amount" ∧   -- gate
  st.post = s2 ∧
  st.writes = [.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount", .fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger", .has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]), .entry "Balance" (st.call.argA "from"), .has (.entry "Balance" (st.call.argA "from"))] ∧
  st.ret = 0

/-- `decimals()`
    effects (reconstructed, in program order):
-/
def decimals : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "decimals" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre (.fld (.var "METADATA") "decimal"))

/-- `mint(to: Address, amount: i128)`
    effects (reconstructed, in program order):
      write @map:Balance(to, @at(44)) := (@map:Balance(to, @at(29)) + amount)
    guards (recovered panic/gate conditions):
      gate: amount > -1
-/
def mint : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := ((st.pre).set (.entry "Balance" (st.call.argA "to")) (((st.pre (.entry "Balance" (st.call.argA "to"))) + st.call.arg "amount"))).set (.has (.entry "Balance" (st.call.argA "to"))) (1)
  st.call.fn = "mint" ∧
  c ≠ pool ∧
  st.call.signed (st.pre (.var "Admin")) ∧   -- require_auth
  st.call.arg "amount" > -1 ∧   -- gate
  st.post = s1 ∧
  st.writes = [.entry "Balance" (st.call.argA "to"), .has (.entry "Balance" (st.call.argA "to"))] ∧
  st.ret = 0

/-- `name()`
    effects (reconstructed, in program order):
-/
def name : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "name" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre (.fld (.var "METADATA") "name"))

/-- `set_admin(new_admin: Address)`
    effects (reconstructed, in program order):
      write storage.Admin/22 := new_admin
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

/-- `symbol()`
    effects (reconstructed, in program order):
-/
def symbol : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "symbol" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre (.fld (.var "METADATA") "symbol"))

/-- `transfer(from: Address, to_muxed: MuxedAddress, amount: i128)`
    effects (reconstructed, in program order):
      write @map:Balance(from, @at(61)) := (@map:Balance(from, @at(41)) - amount)
      write @map:Balance(@addrof(to_muxed), @at(87)) := (@map:Balance(@addrof(to_muxed), @at(72)) + amount)
    guards (recovered panic/gate conditions):
      auth: caller signed as `from` (require_auth)
      gate: amount > -1
      gate: @map:Balance(from, @at(41)) ≥ amount
-/
def transfer : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := ((st.pre).set (.entry "Balance" (st.call.argA "from")) (((st.pre (.entry "Balance" (st.call.argA "from"))) - st.call.arg "amount"))).set (.has (.entry "Balance" (st.call.argA "from"))) (1)
  let s2 := ((s1).set (.entry "Balance" (st.call.argA "to_muxed")) (((s1 (.entry "Balance" (st.call.argA "to_muxed"))) + st.call.arg "amount"))).set (.has (.entry "Balance" (st.call.argA "to_muxed"))) (1)
  st.call.fn = "transfer" ∧
  c ≠ pool ∧
  c = st.call.argA "from" ∧   -- require_auth
  st.call.arg "amount" > -1 ∧   -- gate
  (st.pre (.entry "Balance" (st.call.argA "from"))) ≥ st.call.arg "amount" ∧   -- gate
  st.post = s2 ∧
  st.writes = [.entry "Balance" (st.call.argA "from"), .has (.entry "Balance" (st.call.argA "from")), .entry "Balance" (st.call.argA "to_muxed"), .has (.entry "Balance" (st.call.argA "to_muxed"))] ∧
  st.ret = 0

/-- `transfer_from(spender: Address, from: Address, to: Address, amount: i128)`
    effects (reconstructed, in program order):
      write @map:Allowance(@struct:from,spender(from, spender), @at(67)) [when ¬(st.call.arg "amount" = 0)] := @struct:amount,live_until_ledger((@field:amount(@map:Allowance(@struct:from,spender(from, spender), @at(45))) - amount), @field:live_until_ledger(@map:Allowance(@struct:from,spender(from, spender), @at(45))))
      write @map:Balance(from, @at(93)) := (@map:Balance(from, @at(73)) - amount)
      write @map:Balance(to, @at(116)) := (@map:Balance(to, @at(98)) + amount)
    guards (recovered panic/gate conditions):
      auth: caller signed as `spender` (require_auth)
      gate: amount > -1
      gate: @field:amount(@map:Allowance(@struct:from,spender(from, spender), @at(45))) ≥ amount
      gate: @map:Balance(from, @at(73)) ≥ amount
-/
def transfer_from : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := if ¬(st.call.arg "amount" = 0) then (((st.pre).set (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount") (((st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount")) - st.call.arg "amount"))).set (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger") ((st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger")))).set (.has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"])) (1) else st.pre
  let s2 := ((s1).set (.entry "Balance" (st.call.argA "from")) (((s1 (.entry "Balance" (st.call.argA "from"))) - st.call.arg "amount"))).set (.has (.entry "Balance" (st.call.argA "from"))) (1)
  let s3 := ((s2).set (.entry "Balance" (st.call.argA "to")) (((s2 (.entry "Balance" (st.call.argA "to"))) + st.call.arg "amount"))).set (.has (.entry "Balance" (st.call.argA "to"))) (1)
  st.call.fn = "transfer_from" ∧
  c ≠ pool ∧
  c = st.call.argA "spender" ∧   -- require_auth
  st.call.arg "amount" > -1 ∧   -- gate
  (st.pre (.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount")) ≥ st.call.arg "amount" ∧   -- gate
  (s1 (.entry "Balance" (st.call.argA "from"))) ≥ st.call.arg "amount" ∧   -- gate
  st.post = s3 ∧
  st.writes = [.fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "amount", .fld (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]) "live_until_ledger", .has (.tup "Allowance" [st.call.argA "from", st.call.argA "spender"]), .entry "Balance" (st.call.argA "from"), .has (.entry "Balance" (st.call.argA "from")), .entry "Balance" (st.call.argA "to"), .has (.entry "Balance" (st.call.argA "to"))] ∧
  st.ret = 0

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [__constructor, allowance, approve, balance, burn, burn_from, decimals, mint, name, set_admin, symbol, transfer, transfer_from]

end Contract
