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

/-- `claim(claimant: Address)`
    transfers: (none recovered)
    guards (recovered panic/gate conditions):
      auth: caller signed as `claimant` (require_auth)
-/
def claim : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "claim" ∧
  c ≠ pool ∧
  c = st.call.argA "claimant" ∧   -- require_auth
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = 0

/-- `deposit(from: Address, token: Address, amount: i128, claimants: Vec<Address>, time_bound: TimeBound)`
    effects (reconstructed, in program order):
      write @slot:instance(@vec(phi(Select(@and(@not(ICmp_EQ(7, 0)), @not(ICmp_EQ(And((phi(cyc, 7) + 4294967295), 4294967295), 0))), buf_symbol_new_from_linear_memory, Select(ICmp_EQ(7, 0), 14, Or(And(phi(1, And((@load(phi(And((cyc + 1), 4294967295), 1048608)) + 4294967250), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048608)) + 4294967243), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048608)) + 4294967237), 4294967295)), 255), Shl(cyc, 6)))), Select(@and(@not(ICmp_EQ(4, 0)), @not(ICmp_EQ(And((phi(cyc, 4) + 4294967295), 4294967295), 0))), buf_symbol_new_from_linear_memory, Select(ICmp_EQ(4, 0), 14, Or(And(phi(1, And((@load(phi(And((cyc + 1), 4294967295), 1048604)) + 4294967250), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048604)) + 4294967243), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048604)) + 4294967237), 4294967295)), 255), Shl(cyc, 6)))))), @at(81)) := map_map_new_from_linear_memory
      write @slot:instance(@vec(phi(Select(@and(@not(ICmp_EQ(7, 0)), @not(ICmp_EQ(And((phi(cyc, 7) + 4294967295), 4294967295), 0))), buf_symbol_new_from_linear_memory, Select(ICmp_EQ(7, 0), 14, Or(And(phi(1, And((@load(phi(And((cyc + 1), 4294967295), 1048608)) + 4294967250), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048608)) + 4294967243), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048608)) + 4294967237), 4294967295)), 255), Shl(cyc, 6)))), Select(@and(@not(ICmp_EQ(4, 0)), @not(ICmp_EQ(And((phi(cyc, 4) + 4294967295), 4294967295), 0))), buf_symbol_new_from_linear_memory, Select(ICmp_EQ(4, 0), 14, Or(And(phi(1, And((@load(phi(And((cyc + 1), 4294967295), 1048604)) + 4294967250), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048604)) + 4294967243), 4294967295), And((@load(phi(And((cyc + 1), 4294967295), 1048604)) + 4294967237), 4294967295)), 255), Shl(cyc, 6)))))), @at(85)) := 2
      transfer (toString (st.call.argA "token")): from -> @pool : amount
    guards (recovered panic/gate conditions):
      auth: caller signed as `from` (require_auth)
-/
opaque deposit_e_g2 : Step → Int
opaque deposit_e_k1 : Step → Key
opaque deposit_e_k3 : Step → Key
def deposit : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (st.pre).set ((deposit_e_k1 st)) ((deposit_e_g2 st))
  let s2 := (s1).set ((deposit_e_k3 st)) (2)
  let s3 := xfer (toString (st.call.argA "token")) s2 (st.call.argA "from") (pool) (st.call.arg "amount")
  st.call.fn = "deposit" ∧
  c ≠ pool ∧
  c = st.call.argA "from" ∧   -- require_auth
  st.post = s3 ∧
  st.writes = [(deposit_e_k1 st), (deposit_e_k3 st), .entry (toString (st.call.argA "token")) (st.call.argA "from"), .entry (toString (st.call.argA "token")) (pool)] ∧
  st.ret = 0

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [claim, deposit]

end Contract
