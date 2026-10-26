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
-- STILL `opaque`: values from loops (e.g. an integer sqrt), composite keys,
-- tuple returns, and whatever the reconstruction could not resolve.
-- ASSUMES token ledgers are keyed by the storage slot holding the token
-- address (`"TokenA"`), i.e. distinct slots hold distinct tokens.
-- Reads/writes inside one helper call are ordered at the call's position.

namespace Contract

abbrev Addr := Int

inductive Key where
  | var   (name : String)
  | entry (map : String) (k : Addr)
  deriving DecidableEq, Inhabited

abbrev Storage := Key → Int
def Storage.set (s : Storage) (k : Key) (v : Int) : Storage := fun k' => if k' = k then v else s k'

structure Call where
  fn     : String
  caller : Addr
  arg    : String → Int   -- numeric args by name
  argA   : String → Addr  -- address args by name
  signed : Addr → Prop    -- addresses that authorized the call (require_auth)

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
  (s.set (.entry m src) (bal m s src - amt)).set (.entry m dst) (bal m s dst + amt)

/-- `__constructor(admin: Address, decimal: u32, name: String, symbol: String)`
    effects (reconstructed, in program order):
      write storage.Admin/34 := admin
      write storage.METADATA/54 := map_map_new_from_linear_memory
    guards (recovered panic/gate conditions):
      gate: decimal ≤ 81604378623
-/
opaque __constructor_e_g1 : Step → Int
def __constructor : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (st.pre).set (.var "Admin") (st.call.argA "admin")
  let s2 := (s1).set (.var "METADATA") ((__constructor_e_g1 st))
  st.call.fn = "__constructor" ∧
  c ≠ pool ∧
  st.call.arg "decimal" ≤ 81604378623 ∧   -- gate
  st.post = s2 ∧
  st.writes = [.var "Admin", .var "METADATA"] ∧
  st.ret = 0

/-- `allowance(from: Address, spender: Address)`
    transfers: (none recovered)
-/
opaque allowance_ret : Step → Int
def allowance : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "allowance" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = allowance_ret st

/-- `approve(from: Address, spender: Address, amount: i128, live_until_ledger: u32)`
    effects (reconstructed, in program order):
      write @map:Allowance(from, @at(55)) := map_map_new_from_linear_memory
    guards (recovered panic/gate conditions):
      auth: caller signed as `from` (require_auth)
-/
opaque approve_e_g1 : Step → Int
def approve : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (st.pre).set (.entry "Allowance" (st.call.argA "from")) ((approve_e_g1 st))
  st.call.fn = "approve" ∧
  c ≠ pool ∧
  c = st.call.argA "from" ∧   -- require_auth
  st.post = s1 ∧
  st.writes = [.entry "Allowance" (st.call.argA "from")] ∧
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
      write @map:Balance(from, @at(63)) := (@map:Balance(from, @at(39)) - amount)
    guards (recovered panic/gate conditions):
      auth: caller signed as `from` (require_auth)
      gate: amount > -1
      gate: @map:Balance(from, @at(39)) ≥ amount
-/
def burn : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (st.pre).set (.entry "Balance" (st.call.argA "from")) (((st.pre (.entry "Balance" (st.call.argA "from"))) - st.call.arg "amount"))
  st.call.fn = "burn" ∧
  c ≠ pool ∧
  c = st.call.argA "from" ∧   -- require_auth
  st.call.arg "amount" > -1 ∧   -- gate
  (st.pre (.entry "Balance" (st.call.argA "from"))) ≥ st.call.arg "amount" ∧   -- gate
  st.post = s1 ∧
  st.writes = [.entry "Balance" (st.call.argA "from")] ∧
  st.ret = 0

/-- `burn_from(spender: Address, from: Address, amount: i128)`
    effects (reconstructed, in program order):
      write @map:Allowance(from, @at(66)) [when False] := map_map_new_from_linear_memory
      write @map:Balance(from, @at(96)) := (@map:Balance(from, @at(72)) - amount)
    guards (recovered panic/gate conditions):
      auth: caller signed as `spender` (require_auth)
      gate: amount > -1
      gate: 0 ≥ amount
      gate: @map:Balance(from, @at(72)) ≥ amount
-/
opaque burn_from_e_g1 : Step → Int
def burn_from : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := if False then (st.pre).set (.entry "Allowance" (st.call.argA "from")) ((burn_from_e_g1 st)) else st.pre
  let s2 := (s1).set (.entry "Balance" (st.call.argA "from")) (((s1 (.entry "Balance" (st.call.argA "from"))) - st.call.arg "amount"))
  st.call.fn = "burn_from" ∧
  c ≠ pool ∧
  c = st.call.argA "spender" ∧   -- require_auth
  st.call.arg "amount" > -1 ∧   -- gate
  0 ≥ st.call.arg "amount" ∧   -- gate
  (s1 (.entry "Balance" (st.call.argA "from"))) ≥ st.call.arg "amount" ∧   -- gate
  st.post = s2 ∧
  st.writes = [.entry "Allowance" (st.call.argA "from"), .entry "Balance" (st.call.argA "from")] ∧
  st.ret = 0

/-- `decimals()`
    transfers: (none recovered)
-/
opaque decimals_ret : Step → Int
def decimals : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "decimals" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = decimals_ret st

/-- `mint(to: Address, amount: i128)`
    effects (reconstructed, in program order):
      write @map:Balance(to, @at(50)) := (@map:Balance(to, @at(33)) + amount)
    guards (recovered panic/gate conditions):
      gate: amount > -1
-/
def mint : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (st.pre).set (.entry "Balance" (st.call.argA "to")) (((st.pre (.entry "Balance" (st.call.argA "to"))) + st.call.arg "amount"))
  st.call.fn = "mint" ∧
  c ≠ pool ∧
  st.call.arg "amount" > -1 ∧   -- gate
  st.post = s1 ∧
  st.writes = [.entry "Balance" (st.call.argA "to")] ∧
  st.ret = 0

/-- `name()`
    transfers: (none recovered)
-/
opaque name_ret : Step → Int
def name : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "name" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = name_ret st

/-- `set_admin(new_admin: Address)`
    effects (reconstructed, in program order):
      write storage.Admin/24 := new_admin
-/
def set_admin : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (st.pre).set (.var "Admin") (st.call.argA "new_admin")
  st.call.fn = "set_admin" ∧
  c ≠ pool ∧
  st.post = s1 ∧
  st.writes = [.var "Admin"] ∧
  st.ret = 0

/-- `symbol()`
    transfers: (none recovered)
-/
opaque symbol_ret : Step → Int
def symbol : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "symbol" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = symbol_ret st

/-- `transfer(from: Address, to_muxed: MuxedAddress, amount: i128)`
    effects (reconstructed, in program order):
      write @map:Balance(from, @at(67)) := (@map:Balance(from, @at(45)) - amount)
      write @map:Balance(@addrof(to_muxed), @at(95)) := (@map:Balance(@addrof(to_muxed), @at(78)) + amount)
    guards (recovered panic/gate conditions):
      auth: caller signed as `from` (require_auth)
      gate: amount > -1
      gate: @map:Balance(from, @at(45)) ≥ amount
-/
def transfer : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (st.pre).set (.entry "Balance" (st.call.argA "from")) (((st.pre (.entry "Balance" (st.call.argA "from"))) - st.call.arg "amount"))
  let s2 := (s1).set (.entry "Balance" (st.call.argA "to_muxed")) (((s1 (.entry "Balance" (st.call.argA "to_muxed"))) + st.call.arg "amount"))
  st.call.fn = "transfer" ∧
  c ≠ pool ∧
  c = st.call.argA "from" ∧   -- require_auth
  st.call.arg "amount" > -1 ∧   -- gate
  (st.pre (.entry "Balance" (st.call.argA "from"))) ≥ st.call.arg "amount" ∧   -- gate
  st.post = s2 ∧
  st.writes = [.entry "Balance" (st.call.argA "from"), .entry "Balance" (st.call.argA "to_muxed")] ∧
  st.ret = 0

/-- `transfer_from(spender: Address, from: Address, to: Address, amount: i128)`
    effects (reconstructed, in program order):
      write @map:Allowance(from, @at(71)) [when False] := map_map_new_from_linear_memory
      write @map:Balance(from, @at(99)) := (@map:Balance(from, @at(77)) - amount)
      write @map:Balance(to, @at(124)) := (@map:Balance(to, @at(104)) + amount)
    guards (recovered panic/gate conditions):
      auth: caller signed as `spender` (require_auth)
      gate: amount > -1
      gate: 0 ≥ amount
      gate: @map:Balance(from, @at(77)) ≥ amount
-/
opaque transfer_from_e_g1 : Step → Int
def transfer_from : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := if False then (st.pre).set (.entry "Allowance" (st.call.argA "from")) ((transfer_from_e_g1 st)) else st.pre
  let s2 := (s1).set (.entry "Balance" (st.call.argA "from")) (((s1 (.entry "Balance" (st.call.argA "from"))) - st.call.arg "amount"))
  let s3 := (s2).set (.entry "Balance" (st.call.argA "to")) (((s2 (.entry "Balance" (st.call.argA "to"))) + st.call.arg "amount"))
  st.call.fn = "transfer_from" ∧
  c ≠ pool ∧
  c = st.call.argA "spender" ∧   -- require_auth
  st.call.arg "amount" > -1 ∧   -- gate
  0 ≥ st.call.arg "amount" ∧   -- gate
  (s1 (.entry "Balance" (st.call.argA "from"))) ≥ st.call.arg "amount" ∧   -- gate
  st.post = s3 ∧
  st.writes = [.entry "Allowance" (st.call.argA "from"), .entry "Balance" (st.call.argA "from"), .entry "Balance" (st.call.argA "to")] ∧
  st.ret = 0

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [__constructor, allowance, approve, balance, burn, burn_from, decimals, mint, name, set_admin, symbol, transfer, transfer_from]

end Contract
