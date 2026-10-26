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

/-- the fee-adjusted constant-product invariant value `new_inv_a*new_inv_b`,
    the quantity the contract's `constant product` panic compares. -/
opaque invProduct : Storage → Int

/-- `__constructor(token_a: Address, token_b: Address)`
    effects (reconstructed, in program order):
      write storage.TokenA/21 := token_a
      write storage.TokenB/24 := token_b
      write storage.TotalShares/29 := 11
      write storage.ReserveA/33 := 11
      write storage.ReserveB/37 := 11
-/
def __constructor : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (st.pre).set (.var "TokenA") (st.call.argA "token_a")
  let s2 := (s1).set (.var "TokenB") (st.call.argA "token_b")
  let s3 := (s2).set (.var "TotalShares") (11)
  let s4 := (s3).set (.var "ReserveA") (11)
  let s5 := (s4).set (.var "ReserveB") (11)
  st.call.fn = "__constructor" ∧
  c ≠ pool ∧
  st.post = s5 ∧
  st.writes = [.var "TokenA", .var "TokenB", .var "TotalShares", .var "ReserveA", .var "ReserveB"] ∧
  st.ret = 0

/-- `balance_shares(user: Address)`
    effects (reconstructed, in program order):
-/
def balance_shares : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "balance_shares" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (st.pre (.entry "Shares" (st.call.argA "user")))

/-- `deposit(to: Address, desired_a: i128, min_a: i128, desired_b: i128, min_b: i128)`
    effects (reconstructed, in program order):
      transfer "TokenA": to -> @pool : Select(@and(@not(@and(ICmp_EQ(storage.ReserveA/105, 0), ICmp_EQ(storage.ReserveB/109, 0))), ICmp_SGT(((desired_a * storage.ReserveB/109) / storage.ReserveA/105), desired_b)), ((desired_b * storage.ReserveA/105) / storage.ReserveB/109), desired_a)
      transfer "TokenB": to -> @pool : Select(@and(@not(@and(ICmp_EQ(storage.ReserveA/105, 0), ICmp_EQ(storage.ReserveB/109, 0))), ICmp_SGT(((desired_a * storage.ReserveB/109) / storage.ReserveA/105), desired_b)), desired_b, Select(@and(@not(@and(ICmp_EQ(storage.ReserveA/105, 0), ICmp_EQ(storage.ReserveB/109, 0))), @not(ICmp_SGT(((desired_a * storage.ReserveB/109) / storage.ReserveA/105), desired_b))), ((desired_a * storage.ReserveB/109) / storage.ReserveA/105), desired_b))
      write @map:Shares(to, @at(681)) := (@map:Shares(to, @at(663)) + (big - storage.TotalShares/287))
      write storage.TotalShares/694 := (storage.TotalShares/667 + (big - storage.TotalShares/287))
      write storage.ReserveA/695 := @call:balance(storage.TokenA/280, @vec(@pool), @at(279))
      write storage.ReserveB/696 := @call:balance(storage.TokenB/284, @vec(@pool), @at(283))
    guards (recovered panic/gate conditions):
      auth: caller signed as `to` (require_auth)
      gate: ((desired_a * storage.ReserveB/109) / storage.ReserveA/105) ≥ min_b
      gate: desired_a ≥ ((desired_b * storage.ReserveA/105) / storage.ReserveB/109)
      gate: ((desired_b * storage.ReserveA/105) / storage.ReserveB/109) ≥ min_a
      gate: (@call:balance(storage.TokenA/280, @vec(@pool), @at(279)) * @call:balance(storage.TokenB/284, @vec(@pool), @at(283))) ≥ 0
-/
opaque deposit_e_g1 : Step → Int
opaque deposit_e_g2 : Step → Int
def deposit : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := xfer "TokenA" st.pre (st.call.argA "to") (pool) ((if (¬(((st.pre (.var "ReserveA")) = 0) ∧ ((st.pre (.var "ReserveB")) = 0))) ∧ ((Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) > st.call.arg "desired_b") then (Int.tdiv (st.call.arg "desired_b" * (st.pre (.var "ReserveA"))) (st.pre (.var "ReserveB"))) else st.call.arg "desired_a"))
  let s2 := xfer "TokenB" s1 (st.call.argA "to") (pool) ((if (¬(((st.pre (.var "ReserveA")) = 0) ∧ ((st.pre (.var "ReserveB")) = 0))) ∧ ((Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) > st.call.arg "desired_b") then st.call.arg "desired_b" else (if (¬(((st.pre (.var "ReserveA")) = 0) ∧ ((st.pre (.var "ReserveB")) = 0))) ∧ (¬((Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) > st.call.arg "desired_b")) then (Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) else st.call.arg "desired_b")))
  let s3 := (s2).set (.entry "Shares" (st.call.argA "to")) (((s2 (.entry "Shares" (st.call.argA "to"))) + ((deposit_e_g1 st) - (s2 (.var "TotalShares")))))
  let s4 := (s3).set (.var "TotalShares") (((s2 (.var "TotalShares")) + ((deposit_e_g2 st) - (s2 (.var "TotalShares")))))
  let s5 := (s4).set (.var "ReserveA") ((bal "TokenA" s2 pool))
  let s6 := (s5).set (.var "ReserveB") ((bal "TokenB" s2 pool))
  st.call.fn = "deposit" ∧
  c ≠ pool ∧
  c = st.call.argA "to" ∧   -- require_auth
  (Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) ≥ st.call.arg "min_b" ∧   -- gate
  st.call.arg "desired_a" ≥ (Int.tdiv (st.call.arg "desired_b" * (st.pre (.var "ReserveA"))) (st.pre (.var "ReserveB"))) ∧   -- gate
  (Int.tdiv (st.call.arg "desired_b" * (st.pre (.var "ReserveA"))) (st.pre (.var "ReserveB"))) ≥ st.call.arg "min_a" ∧   -- gate
  ((bal "TokenA" s2 pool) * (bal "TokenB" s2 pool)) ≥ 0 ∧   -- gate
  st.post = s6 ∧
  st.writes = [.entry "TokenA" (st.call.argA "to"), .entry "TokenA" (pool), .entry "TokenB" (st.call.argA "to"), .entry "TokenB" (pool), .entry "Shares" (st.call.argA "to"), .var "TotalShares", .var "ReserveA", .var "ReserveB"] ∧
  st.ret = 0

/-- `get_rsrvs()`
    transfers: (none recovered)
-/
opaque get_rsrvs_ret : Step → Int
def get_rsrvs : Step → Prop := fun st =>
  let c := st.call.caller
  st.call.fn = "get_rsrvs" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = get_rsrvs_ret st

/-- `swap(to: Address, buy_a: bool, out: i128, in_max: i128)`
    effects (reconstructed, in program order):
      transfer (if ¬(st.call.arg "buy_a" = 0) then "TokenB" else "TokenA"): to -> @pool : ((((Select(@isfalse(buy_a), storage.ReserveA/66, storage.ReserveB/70) * out) * 1000) / ((Select(@isfalse(buy_a), storage.ReserveB/70, storage.ReserveA/66) - out) * 997)) + 1)
      transfer (if st.call.arg "buy_a" = 0 then "TokenB" else "TokenA"): @pool -> to : out
      write storage.ReserveA/338 := (@call:balance(storage.TokenA/203, @vec(@pool), @at(202)) - Select(@not(@isfalse(buy_a)), out, 0))
      write storage.ReserveB/339 := (@call:balance(storage.TokenB/207, @vec(@pool), @at(206)) - Select(@not(@isfalse(buy_a)), 0, out))
    guards (recovered panic/gate conditions):
      auth: caller signed as `to` (require_auth)
      gate: Select(@isfalse(buy_a), storage.ReserveB/70, storage.ReserveA/66) ≥ out
      gate: ((((Select(@isfalse(buy_a), storage.ReserveA/66, storage.ReserveB/70) * out) * 1000) / ((Select(@isfalse(buy_a), storage.ReserveB/70, storage.ReserveA/66) - out) * 997)) + 1) ≤ in_max
      gate: (((1000 * storage.ReserveA/66) + Select(@not(ICmp_SLE(((@call:balance(storage.TokenA/203, @vec(@pool), @at(202)) - storage.ReserveA/66) - Select(@not(@isfalse(buy_a)), out, 0)), 0)), (997 * ((@call:balance(storage.TokenA/203, @vec(@pool), @at(202)) - storage.ReserveA/66) - Select(@not(@isfalse(buy_a)), out, 0))), (1000 * ((@call:balance(storage.TokenA/203, @vec(@pool), @at(202)) - storage.ReserveA/66) - Select(@not(@isfalse(buy_a)), out, 0))))) * ((1000 * storage.ReserveB/70) + Select(@not(ICmp_SLE(((@call:balance(storage.TokenB/207, @vec(@pool), @at(206)) - storage.ReserveB/70) - Select(@not(@isfalse(buy_a)), 0, out)), 0)), (997 * ((@call:balance(storage.TokenB/207, @vec(@pool), @at(206)) - storage.ReserveB/70) - Select(@not(@isfalse(buy_a)), 0, out))), (1000 * ((@call:balance(storage.TokenB/207, @vec(@pool), @at(206)) - storage.ReserveB/70) - Select(@not(@isfalse(buy_a)), 0, out)))))) ≥ ((storage.ReserveA/66 * 1000) * (storage.ReserveB/70 * 1000))
-/
def swap : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := xfer (if ¬(st.call.arg "buy_a" = 0) then "TokenB" else "TokenA") st.pre (st.call.argA "to") (pool) (((Int.tdiv (((if st.call.arg "buy_a" = 0 then (st.pre (.var "ReserveA")) else (st.pre (.var "ReserveB"))) * st.call.arg "out") * 1000) (((if st.call.arg "buy_a" = 0 then (st.pre (.var "ReserveB")) else (st.pre (.var "ReserveA"))) - st.call.arg "out") * 997)) + 1))
  let s2 := xfer (if st.call.arg "buy_a" = 0 then "TokenB" else "TokenA") s1 (pool) (st.call.argA "to") (st.call.arg "out")
  let s3 := (s2).set (.var "ReserveA") (((bal "TokenA" s1 pool) - (if ¬(st.call.arg "buy_a" = 0) then st.call.arg "out" else 0)))
  let s4 := (s3).set (.var "ReserveB") (((bal "TokenB" s1 pool) - (if ¬(st.call.arg "buy_a" = 0) then 0 else st.call.arg "out")))
  st.call.fn = "swap" ∧
  c ≠ pool ∧
  c = st.call.argA "to" ∧   -- require_auth
  invProduct st.pre ≤ invProduct st.post ∧   -- constant-product trap
  (if st.call.arg "buy_a" = 0 then (st.pre (.var "ReserveB")) else (st.pre (.var "ReserveA"))) ≥ st.call.arg "out" ∧   -- gate
  ((Int.tdiv (((if st.call.arg "buy_a" = 0 then (st.pre (.var "ReserveA")) else (st.pre (.var "ReserveB"))) * st.call.arg "out") * 1000) (((if st.call.arg "buy_a" = 0 then (st.pre (.var "ReserveB")) else (st.pre (.var "ReserveA"))) - st.call.arg "out") * 997)) + 1) ≤ st.call.arg "in_max" ∧   -- gate
  (((1000 * (st.pre (.var "ReserveA"))) + (if ¬((((bal "TokenA" s1 pool) - (st.pre (.var "ReserveA"))) - (if ¬(st.call.arg "buy_a" = 0) then st.call.arg "out" else 0)) ≤ 0) then (997 * (((bal "TokenA" s1 pool) - (st.pre (.var "ReserveA"))) - (if ¬(st.call.arg "buy_a" = 0) then st.call.arg "out" else 0))) else (1000 * (((bal "TokenA" s1 pool) - (st.pre (.var "ReserveA"))) - (if ¬(st.call.arg "buy_a" = 0) then st.call.arg "out" else 0))))) * ((1000 * (st.pre (.var "ReserveB"))) + (if ¬((((bal "TokenB" s1 pool) - (st.pre (.var "ReserveB"))) - (if ¬(st.call.arg "buy_a" = 0) then 0 else st.call.arg "out")) ≤ 0) then (997 * (((bal "TokenB" s1 pool) - (st.pre (.var "ReserveB"))) - (if ¬(st.call.arg "buy_a" = 0) then 0 else st.call.arg "out"))) else (1000 * (((bal "TokenB" s1 pool) - (st.pre (.var "ReserveB"))) - (if ¬(st.call.arg "buy_a" = 0) then 0 else st.call.arg "out")))))) ≥ (((st.pre (.var "ReserveA")) * 1000) * ((st.pre (.var "ReserveB")) * 1000)) ∧   -- gate
  st.post = s4 ∧
  st.writes = [.entry (if ¬(st.call.arg "buy_a" = 0) then "TokenB" else "TokenA") (st.call.argA "to"), .entry (if ¬(st.call.arg "buy_a" = 0) then "TokenB" else "TokenA") (pool), .entry (if st.call.arg "buy_a" = 0 then "TokenB" else "TokenA") (pool), .entry (if st.call.arg "buy_a" = 0 then "TokenB" else "TokenA") (st.call.argA "to"), .var "ReserveA", .var "ReserveB"] ∧
  st.ret = 0

-- VALUE INVARIANT: a `swap` never decreases the constant product.
theorem swap_keeps_product (st : Step) (h : swap st) :
    invProduct st.pre ≤ invProduct st.post := h.2.2.2.1

/-- `withdraw(to: Address, share_amount: i128, min_a: i128, min_b: i128)`
    effects (reconstructed, in program order):
      write @map:Shares(to, @at(227)) := (@map:Shares(to, @at(207)) - share_amount)
      write storage.TotalShares/239 := (storage.TotalShares/216 - share_amount)
      transfer "TokenA": @pool -> to : ((@call:balance(storage.TokenA/85, @vec(@pool), @at(84)) * share_amount) / storage.TotalShares/98)
      transfer "TokenB": @pool -> to : ((@call:balance(storage.TokenB/95, @vec(@pool), @at(94)) * share_amount) / storage.TotalShares/98)
      write storage.ReserveA/258 := (@call:balance(storage.TokenA/85, @vec(@pool), @at(84)) - ((@call:balance(storage.TokenA/85, @vec(@pool), @at(84)) * share_amount) / storage.TotalShares/98))
      write storage.ReserveB/269 := (@call:balance(storage.TokenB/95, @vec(@pool), @at(94)) - ((@call:balance(storage.TokenB/95, @vec(@pool), @at(94)) * share_amount) / storage.TotalShares/98))
    guards (recovered panic/gate conditions):
      auth: caller signed as `to` (require_auth)
      gate: @map:Shares(to, @at(72)) ≥ share_amount
      gate: ((@call:balance(storage.TokenA/85, @vec(@pool), @at(84)) * share_amount) / storage.TotalShares/98) ≥ min_a
      gate: ((@call:balance(storage.TokenB/95, @vec(@pool), @at(94)) * share_amount) / storage.TotalShares/98) ≥ min_b
      gate: @map:Shares(to, @at(207)) ≥ share_amount
-/
opaque withdraw_ret : Step → Int
def withdraw : Step → Prop := fun st =>
  let c := st.call.caller
  let s1 := (st.pre).set (.entry "Shares" (st.call.argA "to")) (((st.pre (.entry "Shares" (st.call.argA "to"))) - st.call.arg "share_amount"))
  let s2 := (s1).set (.var "TotalShares") (((st.pre (.var "TotalShares")) - st.call.arg "share_amount"))
  let s3 := xfer "TokenA" s2 (pool) (st.call.argA "to") ((Int.tdiv ((bal "TokenA" st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares"))))
  let s4 := xfer "TokenB" s3 (pool) (st.call.argA "to") ((Int.tdiv ((bal "TokenB" st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares"))))
  let s5 := (s4).set (.var "ReserveA") (((bal "TokenA" st.pre pool) - (Int.tdiv ((bal "TokenA" st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares")))))
  let s6 := (s5).set (.var "ReserveB") (((bal "TokenB" st.pre pool) - (Int.tdiv ((bal "TokenB" st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares")))))
  st.call.fn = "withdraw" ∧
  c ≠ pool ∧
  c = st.call.argA "to" ∧   -- require_auth
  (st.pre (.entry "Shares" (st.call.argA "to"))) ≥ st.call.arg "share_amount" ∧   -- gate
  (Int.tdiv ((bal "TokenA" st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares"))) ≥ st.call.arg "min_a" ∧   -- gate
  (Int.tdiv ((bal "TokenB" st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares"))) ≥ st.call.arg "min_b" ∧   -- gate
  (st.pre (.entry "Shares" (st.call.argA "to"))) ≥ st.call.arg "share_amount" ∧   -- gate
  st.post = s6 ∧
  st.writes = [.entry "Shares" (st.call.argA "to"), .var "TotalShares", .entry "TokenA" (pool), .entry "TokenA" (st.call.argA "to"), .entry "TokenB" (pool), .entry "TokenB" (st.call.argA "to"), .var "ReserveA", .var "ReserveB"] ∧
  st.ret = withdraw_ret st

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [__constructor, balance_shares, deposit, get_rsrvs, swap, withdraw]

-- VALUE INVARIANT (inductive): across any sequence of `swap` calls the
-- constant product never falls below its start -- no draining by swapping.
inductive Reach : Storage → Storage → Prop where
  | refl (s) : Reach s s
  | step {s} (st : Step) : Reach s st.pre → swap st → Reach s st.post

theorem no_drain (s t : Storage) (r : Reach s t) : invProduct s ≤ invProduct t := by
  induction r with
  | refl => omega
  | step st _ h ih => have hp := swap_keeps_product st h; omega

end Contract
