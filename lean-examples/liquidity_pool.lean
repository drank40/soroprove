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

/-- `__constructor(token_a: Address, token_b: Address)`
    effects, in execution order:
      write storage.TokenA/1 := token_a
      write storage.TokenB/2 := token_b
      write storage.TotalShares/3 := 11
      write storage.ReserveA/4 := 11
      write storage.ReserveB/5 := 11
    conditions to succeed:
      gate: token_a < token_b
-/
def __constructor : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  let s1 := ((st.pre).set (.var "TokenA") (st.call.argA "token_a")).set (.has (.var "TokenA")) (1)
  let s2 := ((s1).set (.var "TokenB") (st.call.argA "token_b")).set (.has (.var "TokenB")) (1)
  let s3 := ((s2).set (.var "TotalShares") (11)).set (.has (.var "TotalShares")) (1)
  let s4 := ((s3).set (.var "ReserveA") (11)).set (.has (.var "ReserveA")) (1)
  let s5 := ((s4).set (.var "ReserveB") (11)).set (.has (.var "ReserveB")) (1)
  st.call.fn = "__constructor" ∧
  c ≠ pool ∧
  st.call.argA "token_a" < st.call.argA "token_b" ∧   -- gate
  st.post = s5 ∧
  st.writes = [.var "TokenA", .has (.var "TokenA"), .var "TokenB", .has (.var "TokenB"), .var "TotalShares", .has (.var "TotalShares"), .var "ReserveA", .has (.var "ReserveA"), .var "ReserveB", .has (.var "ReserveB")] ∧
  st.ret = 2

/-- `balance_shares(user: Address)`
-/
def balance_shares : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  st.call.fn = "balance_shares" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (getOr0 st.pre (.entry "Shares" (st.call.argA "user")))

/-- `deposit(to: Address, desired_a: i128, min_a: i128, desired_b: i128, min_b: i128)`
    effects, in execution order:
      transfer storage.TokenA/6: to -> @pool : Select(@and(@not(@and(ICmp_EQ(storage.ReserveA/14, 0), ICmp_EQ(storage.ReserveB/16, 0))), ICmp_SGT(((desired_a * storage.ReserveB/16) / storage.ReserveA/14), desired_b)), ((desired_b * storage.ReserveA/14) / storage.ReserveB/16), desired_a)
      transfer storage.TokenB/6: to -> @pool : Select(@and(@not(@and(ICmp_EQ(storage.ReserveA/14, 0), ICmp_EQ(storage.ReserveB/16, 0))), ICmp_SGT(((desired_a * storage.ReserveB/16) / storage.ReserveA/14), desired_b)), desired_b, Select(@not(@and(ICmp_EQ(storage.ReserveA/14, 0), ICmp_EQ(storage.ReserveB/16, 0))), ((desired_a * storage.ReserveB/16) / storage.ReserveA/14), desired_b))
      write @map:Shares(to, @at(20)) := (Select(@not(ICmp_EQ(@has(@map:Shares(to, @at(22))), 1)), 0, @map:Shares(to, @at(23))) + (big - storage.TotalShares/36))
      write storage.TotalShares/39 := (storage.TotalShares/41 + (big - storage.TotalShares/36))
      write storage.ReserveA/42 := @call:balance(storage.TokenA/6, @vec(@pool), @at(26))
      write storage.ReserveB/43 := @call:balance(storage.TokenB/6, @vec(@pool), @at(28))
    conditions to succeed:
      require_auth to
      gate: ((desired_a * storage.ReserveB/16) / storage.ReserveA/14) ≥ min_b   [when ¬(((st.pre (.var "ReserveA")) = 0) ∧ ((st.pre (.var "ReserveB")) = 0)) ∧ ¬((Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) > st.call.arg "desired_b")]
      gate: desired_a ≥ ((desired_b * storage.ReserveA/14) / storage.ReserveB/16)   [when ¬(((st.pre (.var "ReserveA")) = 0) ∧ ((st.pre (.var "ReserveB")) = 0)) ∧ (Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) > st.call.arg "desired_b"]
      gate: ((desired_b * storage.ReserveA/14) / storage.ReserveB/16) ≥ min_a   [when ¬(((st.pre (.var "ReserveA")) = 0) ∧ ((st.pre (.var "ReserveB")) = 0)) ∧ (Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) > st.call.arg "desired_b"]
-/
def deposit : Step → Prop := fun st => ∃ u : Unk,
  let c := st.call.caller
  let pool := st.call.self
  let s1 := xfer ((st.pre (.var "TokenA"))) st.pre (st.call.argA "to") (pool) ((if (¬(((st.pre (.var "ReserveA")) = 0) ∧ ((st.pre (.var "ReserveB")) = 0))) ∧ ((Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) > st.call.arg "desired_b") then (Int.tdiv (st.call.arg "desired_b" * (st.pre (.var "ReserveA"))) (st.pre (.var "ReserveB"))) else st.call.arg "desired_a"))
  let s2 := xfer ((st.pre (.var "TokenB"))) s1 (st.call.argA "to") (pool) ((if (¬(((st.pre (.var "ReserveA")) = 0) ∧ ((st.pre (.var "ReserveB")) = 0))) ∧ ((Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) > st.call.arg "desired_b") then st.call.arg "desired_b" else (if ¬(((st.pre (.var "ReserveA")) = 0) ∧ ((st.pre (.var "ReserveB")) = 0)) then (Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) else st.call.arg "desired_b")))
  let s3 := ((s2).set (.entry "Shares" (st.call.argA "to")) (((getOr0 s2 (.entry "Shares" (st.call.argA "to"))) + ((u.i 1) - (s2 (.var "TotalShares")))))).set (.has (.entry "Shares" (st.call.argA "to"))) (1)
  let s4 := ((s3).set (.var "TotalShares") (((s2 (.var "TotalShares")) + ((u.i 2) - (s2 (.var "TotalShares")))))).set (.has (.var "TotalShares")) (1)
  let s5 := ((s4).set (.var "ReserveA") ((bal (st.pre (.var "TokenA")) s2 pool))).set (.has (.var "ReserveA")) (1)
  let s6 := ((s5).set (.var "ReserveB") ((bal (st.pre (.var "TokenB")) s2 pool))).set (.has (.var "ReserveB")) (1)
  st.call.fn = "deposit" ∧
  c ≠ pool ∧
  st.call.argA "to" ∈ st.call.signers ∧   -- require_auth to
  ((¬(((st.pre (.var "ReserveA")) = 0) ∧ ((st.pre (.var "ReserveB")) = 0)) ∧ ¬((Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) > st.call.arg "desired_b")) → (Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) ≥ st.call.arg "min_b") ∧   -- gate
  ((¬(((st.pre (.var "ReserveA")) = 0) ∧ ((st.pre (.var "ReserveB")) = 0)) ∧ (Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) > st.call.arg "desired_b") → st.call.arg "desired_a" ≥ (Int.tdiv (st.call.arg "desired_b" * (st.pre (.var "ReserveA"))) (st.pre (.var "ReserveB")))) ∧   -- gate
  ((¬(((st.pre (.var "ReserveA")) = 0) ∧ ((st.pre (.var "ReserveB")) = 0)) ∧ (Int.tdiv (st.call.arg "desired_a" * (st.pre (.var "ReserveB"))) (st.pre (.var "ReserveA"))) > st.call.arg "desired_b") → (Int.tdiv (st.call.arg "desired_b" * (st.pre (.var "ReserveA"))) (st.pre (.var "ReserveB"))) ≥ st.call.arg "min_a") ∧   -- gate
  st.post = s6 ∧
  st.writes = [.bal ((st.pre (.var "TokenA"))) (st.call.argA "to"), .bal ((st.pre (.var "TokenA"))) (pool), .bal ((st.pre (.var "TokenB"))) (st.call.argA "to"), .bal ((st.pre (.var "TokenB"))) (pool), .entry "Shares" (st.call.argA "to"), .has (.entry "Shares" (st.call.argA "to")), .var "TotalShares", .has (.var "TotalShares"), .var "ReserveA", .has (.var "ReserveA"), .var "ReserveB", .has (.var "ReserveB")] ∧
  st.ret = 2

/-- `get_rsrvs()`
-/
def get_rsrvs : Step → Prop := fun st => ∃ u : Unk,
  let c := st.call.caller
  let pool := st.call.self
  st.call.fn = "get_rsrvs" ∧
  c ≠ pool ∧
  st.post = st.pre ∧
  st.writes = [] ∧
  st.ret = (u.i 0)

/-- `swap(to: Address, buy_a: bool, out: i128, in_max: i128)`
    effects, in execution order:
      transfer Select(@not(@isfalse(buy_a)), storage.TokenB/6, storage.TokenA/6): to -> @pool : ((((Select(@isfalse(buy_a), storage.ReserveA/59, storage.ReserveB/61) * out) * 1000) / ((Select(@isfalse(buy_a), storage.ReserveB/61, storage.ReserveA/59) - out) * 997)) + 1)
      transfer Select(@isfalse(buy_a), storage.TokenB/6, storage.TokenA/6): @pool -> to : out
      write storage.ReserveA/78 := (@call:balance(storage.TokenA/6, @vec(@pool), @at(72)) - Select(@not(@isfalse(buy_a)), out, 0))
      write storage.ReserveB/79 := (@call:balance(storage.TokenB/6, @vec(@pool), @at(76)) - Select(@not(@isfalse(buy_a)), 0, out))
    conditions to succeed:
      require_auth to
      gate: Select(@isfalse(buy_a), storage.ReserveB/61, storage.ReserveA/59) ≥ out
      gate: ((((Select(@isfalse(buy_a), storage.ReserveA/59, storage.ReserveB/61) * out) * 1000) / ((Select(@isfalse(buy_a), storage.ReserveB/61, storage.ReserveA/59) - out) * 997)) + 1) ≤ in_max
      gate: (((1000 * storage.ReserveA/59) + Select(@not(ICmp_SLE(((@call:balance(storage.TokenA/6, @vec(@pool), @at(72)) - storage.ReserveA/59) - Select(@not(@isfalse(buy_a)), out, 0)), 0)), (997 * ((@call:balance(storage.TokenA/6, @vec(@pool), @at(72)) - storage.ReserveA/59) - Select(@not(@isfalse(buy_a)), out, 0))), (1000 * ((@call:balance(storage.TokenA/6, @vec(@pool), @at(72)) - storage.ReserveA/59) - Select(@not(@isfalse(buy_a)), out, 0))))) * ((1000 * storage.ReserveB/61) + Select(@not(ICmp_SLE(((@call:balance(storage.TokenB/6, @vec(@pool), @at(76)) - storage.ReserveB/61) - Select(@not(@isfalse(buy_a)), 0, out)), 0)), (997 * ((@call:balance(storage.TokenB/6, @vec(@pool), @at(76)) - storage.ReserveB/61) - Select(@not(@isfalse(buy_a)), 0, out))), (1000 * ((@call:balance(storage.TokenB/6, @vec(@pool), @at(76)) - storage.ReserveB/61) - Select(@not(@isfalse(buy_a)), 0, out)))))) ≥ ((storage.ReserveA/59 * 1000) * (storage.ReserveB/61 * 1000))
-/
def swap : Step → Prop := fun st =>
  let c := st.call.caller
  let pool := st.call.self
  let s1 := xfer ((if ¬(st.call.arg "buy_a" = 0) then (st.pre (.var "TokenB")) else (st.pre (.var "TokenA")))) st.pre (st.call.argA "to") (pool) (((Int.tdiv (((if st.call.arg "buy_a" = 0 then (st.pre (.var "ReserveA")) else (st.pre (.var "ReserveB"))) * st.call.arg "out") * 1000) (((if st.call.arg "buy_a" = 0 then (st.pre (.var "ReserveB")) else (st.pre (.var "ReserveA"))) - st.call.arg "out") * 997)) + 1))
  let s2 := xfer ((if st.call.arg "buy_a" = 0 then (st.pre (.var "TokenB")) else (st.pre (.var "TokenA")))) s1 (pool) (st.call.argA "to") (st.call.arg "out")
  let s3 := ((s2).set (.var "ReserveA") (((bal (st.pre (.var "TokenA")) s1 pool) - (if ¬(st.call.arg "buy_a" = 0) then st.call.arg "out" else 0)))).set (.has (.var "ReserveA")) (1)
  let s4 := ((s3).set (.var "ReserveB") (((bal (st.pre (.var "TokenB")) s1 pool) - (if ¬(st.call.arg "buy_a" = 0) then 0 else st.call.arg "out")))).set (.has (.var "ReserveB")) (1)
  st.call.fn = "swap" ∧
  c ≠ pool ∧
  st.call.argA "to" ∈ st.call.signers ∧   -- require_auth to
  (if st.call.arg "buy_a" = 0 then (st.pre (.var "ReserveB")) else (st.pre (.var "ReserveA"))) ≥ st.call.arg "out" ∧   -- gate
  ((Int.tdiv (((if st.call.arg "buy_a" = 0 then (st.pre (.var "ReserveA")) else (st.pre (.var "ReserveB"))) * st.call.arg "out") * 1000) (((if st.call.arg "buy_a" = 0 then (st.pre (.var "ReserveB")) else (st.pre (.var "ReserveA"))) - st.call.arg "out") * 997)) + 1) ≤ st.call.arg "in_max" ∧   -- gate
  (((1000 * (st.pre (.var "ReserveA"))) + (if ¬((((bal (st.pre (.var "TokenA")) s1 pool) - (st.pre (.var "ReserveA"))) - (if ¬(st.call.arg "buy_a" = 0) then st.call.arg "out" else 0)) ≤ 0) then (997 * (((bal (st.pre (.var "TokenA")) s1 pool) - (st.pre (.var "ReserveA"))) - (if ¬(st.call.arg "buy_a" = 0) then st.call.arg "out" else 0))) else (1000 * (((bal (st.pre (.var "TokenA")) s1 pool) - (st.pre (.var "ReserveA"))) - (if ¬(st.call.arg "buy_a" = 0) then st.call.arg "out" else 0))))) * ((1000 * (st.pre (.var "ReserveB"))) + (if ¬((((bal (st.pre (.var "TokenB")) s1 pool) - (st.pre (.var "ReserveB"))) - (if ¬(st.call.arg "buy_a" = 0) then 0 else st.call.arg "out")) ≤ 0) then (997 * (((bal (st.pre (.var "TokenB")) s1 pool) - (st.pre (.var "ReserveB"))) - (if ¬(st.call.arg "buy_a" = 0) then 0 else st.call.arg "out"))) else (1000 * (((bal (st.pre (.var "TokenB")) s1 pool) - (st.pre (.var "ReserveB"))) - (if ¬(st.call.arg "buy_a" = 0) then 0 else st.call.arg "out")))))) ≥ (((st.pre (.var "ReserveA")) * 1000) * ((st.pre (.var "ReserveB")) * 1000)) ∧   -- gate
  st.post = s4 ∧
  st.writes = [.bal ((if ¬(st.call.arg "buy_a" = 0) then (st.pre (.var "TokenB")) else (st.pre (.var "TokenA")))) (st.call.argA "to"), .bal ((if ¬(st.call.arg "buy_a" = 0) then (st.pre (.var "TokenB")) else (st.pre (.var "TokenA")))) (pool), .bal ((if st.call.arg "buy_a" = 0 then (st.pre (.var "TokenB")) else (st.pre (.var "TokenA")))) (pool), .bal ((if st.call.arg "buy_a" = 0 then (st.pre (.var "TokenB")) else (st.pre (.var "TokenA")))) (st.call.argA "to"), .var "ReserveA", .has (.var "ReserveA"), .var "ReserveB", .has (.var "ReserveB")] ∧
  st.ret = 2

/-- `withdraw(to: Address, share_amount: i128, min_a: i128, min_b: i128)`
    effects, in execution order:
      write @map:Shares(to, @at(91)) := (Select(@not(ICmp_EQ(@has(@map:Shares(to, @at(92))), 1)), 0, @map:Shares(to, @at(93))) - share_amount)
      write storage.TotalShares/95 := (storage.TotalShares/97 - share_amount)
      transfer storage.TokenA/6: @pool -> to : ((@call:balance(storage.TokenA/6, @vec(@pool), @at(85)) * share_amount) / storage.TotalShares/88)
      transfer storage.TokenB/6: @pool -> to : ((@call:balance(storage.TokenB/6, @vec(@pool), @at(90)) * share_amount) / storage.TotalShares/88)
      write storage.ReserveA/98 := (@call:balance(storage.TokenA/6, @vec(@pool), @at(85)) - ((@call:balance(storage.TokenA/6, @vec(@pool), @at(85)) * share_amount) / storage.TotalShares/88))
      write storage.ReserveB/99 := (@call:balance(storage.TokenB/6, @vec(@pool), @at(90)) - ((@call:balance(storage.TokenB/6, @vec(@pool), @at(90)) * share_amount) / storage.TotalShares/88))
    conditions to succeed:
      require_auth to
      gate: Select(@not(ICmp_EQ(@has(@map:Shares(to, @at(106))), 1)), 0, @map:Shares(to, @at(107))) ≥ share_amount
      gate: ((@call:balance(storage.TokenA/6, @vec(@pool), @at(85)) * share_amount) / storage.TotalShares/88) ≥ min_a
      gate: ((@call:balance(storage.TokenB/6, @vec(@pool), @at(90)) * share_amount) / storage.TotalShares/88) ≥ min_b
      gate: Select(@not(ICmp_EQ(@has(@map:Shares(to, @at(92))), 1)), 0, @map:Shares(to, @at(93))) ≥ share_amount
-/
def withdraw : Step → Prop := fun st => ∃ u : Unk,
  let c := st.call.caller
  let pool := st.call.self
  let s1 := ((st.pre).set (.entry "Shares" (st.call.argA "to")) (((getOr0 st.pre (.entry "Shares" (st.call.argA "to"))) - st.call.arg "share_amount"))).set (.has (.entry "Shares" (st.call.argA "to"))) (1)
  let s2 := ((s1).set (.var "TotalShares") (((st.pre (.var "TotalShares")) - st.call.arg "share_amount"))).set (.has (.var "TotalShares")) (1)
  let s3 := xfer ((st.pre (.var "TokenA"))) s2 (pool) (st.call.argA "to") ((Int.tdiv ((bal (st.pre (.var "TokenA")) st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares"))))
  let s4 := xfer ((st.pre (.var "TokenB"))) s3 (pool) (st.call.argA "to") ((Int.tdiv ((bal (st.pre (.var "TokenB")) st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares"))))
  let s5 := ((s4).set (.var "ReserveA") (((bal (st.pre (.var "TokenA")) st.pre pool) - (Int.tdiv ((bal (st.pre (.var "TokenA")) st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares")))))).set (.has (.var "ReserveA")) (1)
  let s6 := ((s5).set (.var "ReserveB") (((bal (st.pre (.var "TokenB")) st.pre pool) - (Int.tdiv ((bal (st.pre (.var "TokenB")) st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares")))))).set (.has (.var "ReserveB")) (1)
  st.call.fn = "withdraw" ∧
  c ≠ pool ∧
  st.call.argA "to" ∈ st.call.signers ∧   -- require_auth to
  (getOr0 st.pre (.entry "Shares" (st.call.argA "to"))) ≥ st.call.arg "share_amount" ∧   -- gate
  (Int.tdiv ((bal (st.pre (.var "TokenA")) st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares"))) ≥ st.call.arg "min_a" ∧   -- gate
  (Int.tdiv ((bal (st.pre (.var "TokenB")) st.pre pool) * st.call.arg "share_amount") (st.pre (.var "TotalShares"))) ≥ st.call.arg "min_b" ∧   -- gate
  st.post = s6 ∧
  st.writes = [.entry "Shares" (st.call.argA "to"), .has (.entry "Shares" (st.call.argA "to")), .var "TotalShares", .has (.var "TotalShares"), .bal ((st.pre (.var "TokenA"))) (pool), .bal ((st.pre (.var "TokenA"))) (st.call.argA "to"), .bal ((st.pre (.var "TokenB"))) (pool), .bal ((st.pre (.var "TokenB"))) (st.call.argA "to"), .var "ReserveA", .has (.var "ReserveA"), .var "ReserveB", .has (.var "ReserveB")] ∧
  st.ret = (u.i 0)

/-- the contract's entry points (each a `Step → Prop`). -/
def entries : List (Step → Prop) := [__constructor, balance_shares, deposit, get_rsrvs, swap, withdraw]

end Contract
