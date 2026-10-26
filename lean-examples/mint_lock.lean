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

/-- `__constructor(admin: Address)`
    effects (reconstructed, in program order):
      write @slot:instance(@key(?, ?, @kb:f17), @at(10)) := admin
-/
opaque __constructor_e_k1 : Step → Key
def __constructor : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (st.pre).set ((__constructor_e_k1 st)) (st.call.argA "admin")
  st.call.fn = "__constructor" ∧
  c ≠ pool ∧
  st.post = s1 ∧
  st.writes = [(__constructor_e_k1 st)] ∧
  st.ret = 0

/-- `admin()`
    transfers: (none recovered)
-/
opaque admin_ret : Step → Int
def admin : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "admin" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = admin_ret st

/-- `mint(contract: Address, minter: Address, to: Address, amount: i128)`
    effects (reconstructed, in program order):
      write @map:MinterStats((LShr(context_get_ledger_sequence, 32) / Load), @at(167)) [when ¬(st.call.arg "amount" < 0) ∧ ¬((mint_e_g1 st) = 0) ∧ ¬((mint_e_g2 st) = 0) ∧ ¬(((if (mint_e_g3 st) = 0 then 0 else (mint_e_g4 st)) + st.call.arg "amount") > (mint_e_g5 st))] := map_map_new_from_linear_memory
    guards (recovered panic/gate conditions):
      auth: caller signed as `minter` (require_auth)
-/
opaque mint_e_g1 : Step → Int
opaque mint_e_g2 : Step → Int
opaque mint_e_g3 : Step → Int
opaque mint_e_g4 : Step → Int
opaque mint_e_g5 : Step → Int
opaque mint_e_g6 : Step → Int
opaque mint_e_g7 : Step → Int
opaque mint_e_g8 : Step → Int
opaque mint_e_g9 : Step → Int
opaque mint_e_g10 : Step → Int
opaque mint_e_g11 : Step → Int
opaque mint_e_g12 : Step → Int
opaque mint_e_g13 : Step → Int
opaque mint_e_g14 : Step → Int
opaque mint_e_g15 : Step → Int
opaque mint_e_g16 : Step → Int
opaque mint_e_g17 : Step → Int
opaque mint_e_g18 : Step → Int
def mint : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := if ¬(st.call.arg "amount" < 0) ∧ ¬((mint_e_g1 st) = 0) ∧ ¬((mint_e_g2 st) = 0) ∧ ¬(((if (mint_e_g3 st) = 0 then 0 else (mint_e_g4 st)) + st.call.arg "amount") > (mint_e_g5 st)) then (st.pre).set (.entry "MinterStats" ((Int.tdiv (mint_e_g6 st) (mint_e_g7 st)))) ((mint_e_g8 st)) else st.pre
  st.call.fn = "mint" ∧
  c ≠ pool ∧
  c = st.call.argA "minter" ∧   -- require_auth
  ((¬(st.call.arg "amount" < 0)) ∧ (¬((mint_e_g9 st) = 0)) ∧ (¬(((if (mint_e_g10 st) = 0 then 0 else (mint_e_g11 st)) + st.call.arg "amount") > (mint_e_g12 st)))) ∧   -- returns Ok (an Err return fails the call)
  st.post = s1 ∧
  st.writes = [.entry "MinterStats" ((Int.tdiv (mint_e_g6 st) (mint_e_g7 st)))] ∧
  st.ret = (if (¬(st.call.arg "amount" < 0)) ∧ (¬((mint_e_g13 st) = 0)) ∧ (¬(((if (mint_e_g14 st) = 0 then 0 else (mint_e_g15 st)) + st.call.arg "amount") > (mint_e_g16 st))) then 2 else (if st.call.arg "amount" < 0 then 12884901891 else (if (¬(st.call.arg "amount" < 0)) ∧ (¬((mint_e_g17 st) = 0)) ∧ ((mint_e_g18 st) = 0) then 4294967299 else 8589934595)))

/-- `minter(contract: Address, minter: Address)`
    transfers: (none recovered)
-/
opaque minter_ret : Step → Int
def minter : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "minter" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = minter_ret st

/-- `set_admin(new_admin: Address)`
    effects (reconstructed, in program order):
      write @slot:instance(@key(?, ?, @kb:f17), @at(13)) := new_admin
-/
opaque set_admin_e_k1 : Step → Key
def set_admin : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (st.pre).set ((set_admin_e_k1 st)) (st.call.argA "new_admin")
  st.call.fn = "set_admin" ∧
  c ≠ pool ∧
  st.post = s1 ∧
  st.writes = [(set_admin_e_k1 st)] ∧
  st.ret = 0

/-- `set_minter(contract: Address, minter: Address, config: MinterConfig)`
    effects (reconstructed, in program order):
      write @map:Minter(contract, @at(46)) := map_map_new_from_linear_memory
-/
opaque set_minter_e_g1 : Step → Int
def set_minter : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (st.pre).set (.entry "Minter" (st.call.argA "contract")) ((set_minter_e_g1 st))
  st.call.fn = "set_minter" ∧
  c ≠ pool ∧
  st.post = s1 ∧
  st.writes = [.entry "Minter" (st.call.argA "contract")] ∧
  st.ret = 0

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [__constructor, admin, mint, minter, set_admin, set_minter]

end Contract
