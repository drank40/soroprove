import StellarLean.SorobanToken

/-
  The liquidity pool from Soroban's examples (stellar/soroban-examples,
  liquidity_pool/src/lib.rs): a constant-product AMM over two tokens with a
  0.3% swap fee. Translated by hand the way a WASM → Lean converter would
  describe it.

    deposit(to, desired_a, min_a, desired_b, min_b)
        to.require_auth(); compute amounts from the reserves; transfer both
        tokens from `to` to the pool; mint shares to `to`; reserves := balances
    swap(to, buy_a, out, in_max)
        to.require_auth(); compute the sell amount (with fee); transfer it from
        `to` to the pool; check the constant product; transfer `out` from the
        pool to `to`; reserves := balances
    withdraw(to, share_amount, min_a, min_b) -> (i128, i128)
        to.require_auth(); burn `to`'s shares; transfer the matching part of
        both balances from the pool to `to`; reserves := balances

  What the model keeps, because the questions are about it:
  * auth: the signer of the call is `to` (`to.require_auth()`). Each token
    transfer checks `from.require_auth()`: `from` is the signer, or the pool
    itself (a contract authorizes its own calls).
  * storage: the pool's instance storage (`TokenA`, `TokenB`, `TotalShares`,
    `ReserveA`, `ReserveB`) and persistent `Shares(addr)`.
  * transfers: the two token contracts' ledgers live in the same world
    storage, as maps `A.Balance` and `B.Balance`. Each transfer does what the
    token of `SorobanToken.lean` does, including its panics.

  Simplifications:
  * `TokenA`/`TokenB` are stored, but the ledgers are fixed maps rather than
    looked up by those addresses. Sound because no entry point writes
    `TokenA`/`TokenB` (proved in `SorobanAmmAnswers.lean`).
  * i128 overflow in the pool's own arithmetic is left out (token balances
    still check it). Leaving out a panic only adds steps, so every
    "for every successful call" answer still holds for the real contract.
  * Rust's `/` rounds toward zero: `Int.tdiv`. Division by zero panics.
  * Events and TTL extensions are left out; `withdraw`'s returned pair is not
    recorded.
-/

namespace SorobanAmm

open Query
open Spec (Addr)

/-- The pool's own address (`e.current_contract_address()`). Opaque: nothing
    is known about it, so every answer holds whatever the address is. -/
opaque pool : Addr

/-! ## Storage layout -/

def TokenA      : Term Addr := var "TokenA"
def TokenB      : Term Addr := var "TokenB"
def TotalShares : Term Int  := var "TotalShares"
def ReserveA    : Term Int  := var "ReserveA"
def ReserveB    : Term Int  := var "ReserveB"
/-- `DataKey::Shares(Address)`, in persistent storage. -/
def Shares      : Map Int   := ⟨"Shares"⟩
/-- The ledgers of token A and token B (storage of the token contracts). -/
def BalanceA    : Map Int   := ⟨"A.Balance"⟩
def BalanceB    : Map Int   := ⟨"B.Balance"⟩

abbrev I128_MAX : Int := SorobanToken.I128_MAX

/-- A number variable of the pool. -/
abbrev num (s : Storage) (name : String) : Int := read s name

def isqrt (x : Int) : Int := Nat.sqrt x.toNat

/-! ## Arguments -/

def desiredA (c : Call) : Int := c.arg "desired_a"
def desiredB (c : Call) : Int := c.arg "desired_b"
def minA     (c : Call) : Int := c.arg "min_a"
def minB     (c : Call) : Int := c.arg "min_b"
def buyA     (c : Call) : Bool := c.arg "buy_a" != 0
def out      (c : Call) : Int := c.arg "out"
def inMax    (c : Call) : Int := c.arg "in_max"
def share    (c : Call) : Int := c.arg "share_amount"

/-! ## Calling a token: `token::Client::transfer(from, to, amount)` -/

def spendOn (m : Map Int) (s : Storage) (who : Addr) (amt : Int) : Storage :=
  s.set (.entry m.name who) (.int (m.read s who - amt))

def receiveOn (m : Map Int) (s : Storage) (who : Addr) (amt : Int) : Storage :=
  s.set (.entry m.name who) (.int (m.read s who + amt))

/-- The storage after the token moves `amt` from `src` to `dst`. -/
def xfer (m : Map Int) (s : Storage) (src dst : Addr) (amt : Int) : Storage :=
  receiveOn m (spendOn m s src amt) dst amt

/-- The token's checks; any failing one panics the whole call. -/
def XferOk (st : Step) (m : Map Int) (s : Storage) (src dst : Addr) (amt : Int) : Prop :=
  (src = st.call.caller ∨ src = pool) ∧                -- from.require_auth()
  0 ≤ amt ∧                                            -- check_nonnegative_amount
  amt ≤ m.read s src ∧                                 -- "insufficient balance"
  m.read (spendOn m s src amt) dst + amt ≤ I128_MAX    -- no i128 overflow

/-! ## deposit -/

/-- `get_deposit_amounts`; `none` = panic. -/
def depositAmounts (dA mA dB mB rA rB : Int) : Option (Int × Int) :=
  if rA = 0 ∧ rB = 0 then some (dA, dB)
  else if rA = 0 then none                                -- division by zero
  else
    let b := (dA * rB).tdiv rA
    if b ≤ dB then
      if b < mB then none else some (dA, b)               -- "amount_b less than min"
    else if rB = 0 then none                              -- division by zero
    else
      let a := (dB * rA).tdiv rB
      if a > dA ∨ a < mA then none else some (a, dB)      -- "amount_a invalid"

namespace Deposit
variable (st : Step)

def amounts : Option (Int × Int) :=
  depositAmounts (desiredA st.call) (minA st.call) (desiredB st.call) (minB st.call)
    (num st.pre "ReserveA") (num st.pre "ReserveB")
def amtA : Int := ((amounts st).getD (0, 0)).1
def amtB : Int := ((amounts st).getD (0, 0)).2

/-- After `token_a_client.transfer(to, pool, amount_a)`. -/
def s1 : Storage := xfer BalanceA st.pre st.call.caller pool (amtA st)
/-- After `token_b_client.transfer(to, pool, amount_b)`. -/
def s2 : Storage := xfer BalanceB (s1 st) st.call.caller pool (amtB st)

def balA : Int := BalanceA.read (s2 st) pool
def balB : Int := BalanceB.read (s2 st) pool

def firstDeposit : Prop := ¬ (0 < num st.pre "ReserveA" ∧ 0 < num st.pre "ReserveB")

def newTotal : Int :=
  let t := num (s2 st) "TotalShares"
  if 0 < num st.pre "ReserveA" ∧ 0 < num st.pre "ReserveB" then
    min ((balA st * t).tdiv (num st.pre "ReserveA")) ((balB st * t).tdiv (num st.pre "ReserveB"))
  else isqrt (balA st * balB st)

def minted : Int := newTotal st - num (s2 st) "TotalShares"

end Deposit

open Deposit in
def deposit : Step → Prop := fun st =>
  let to := st.call.caller
  st.call.fn = "deposit" ∧
  to ≠ pool ∧                                -- Soroban forbids re-entering the pool
  (amounts st).isSome ∧                      -- get_deposit_amounts did not panic
  0 < amtA st ∧ 0 < amtB st ∧                -- "both amounts must be strictly positive"
  XferOk st BalanceA st.pre to pool (amtA st) ∧
  XferOk st BalanceB (s1 st) to pool (amtB st) ∧
  (firstDeposit st → 0 ≤ balA st * balB st) ∧ -- sqrt of a negative panics
  st.post =                                  -- mint_shares, put_reserve_a, put_reserve_b
    ((((s2 st).set (.entry "Shares" to) (.int (Shares.read (s2 st) to + minted st))
      ).set (.var "TotalShares") (.int (num (s2 st) "TotalShares" + minted st))
      ).set (.var "ReserveA") (.int (balA st))
      ).set (.var "ReserveB") (.int (balB st)) ∧
  st.writes = [.entry "A.Balance" to, .entry "A.Balance" pool, .entry "B.Balance" to,
    .entry "B.Balance" pool, .entry "Shares" to, .var "TotalShares", .var "ReserveA",
    .var "ReserveB"] ∧
  st.ret = .none

/-! ## swap

  `buy_a` picks which token is sold and which is bought. The code is the same
  for both directions, so it is written once over a `Side`. -/

structure Side where
  bal     : Map Int   -- the token's ledger
  reserve : String    -- the pool's reserve variable for it

def sideA : Side := ⟨BalanceA, "ReserveA"⟩
def sideB : Side := ⟨BalanceB, "ReserveB"⟩

/-- `new_invariant_factor`: the reserve after the swap, fee taken off what came in
    (scaled by 1000). -/
def factor (balance reserve out : Int) : Int :=
  let delta := balance - reserve - out
  1000 * reserve + (if delta > 0 then 997 * delta else 1000 * delta)

namespace Swap
variable (sell buy : Side) (st : Step)

def rSell : Int := num st.pre sell.reserve
def rBuy  : Int := num st.pre buy.reserve
def sellAmt : Int := (rSell sell st * out st.call * 1000).tdiv ((rBuy buy st - out st.call) * 997) + 1

/-- After `sell_token_client.transfer(to, pool, sell_amount)`. -/
def s1 : Storage := xfer sell.bal st.pre st.call.caller pool (sellAmt sell buy st)
def balSell : Int := sell.bal.read (s1 sell buy st) pool
def balBuy  : Int := buy.bal.read (s1 sell buy st) pool
/-- After `transfer_a`/`transfer_b(to, out)`. -/
def s2 : Storage := xfer buy.bal (s1 sell buy st) pool st.call.caller (out st.call)

end Swap

open Swap in
def swapVia (sell buy : Side) : Step → Prop := fun st =>
  let to := st.call.caller
  out st.call ≤ rBuy buy st ∧                          -- "not enough token to buy"
  (rBuy buy st - out st.call) * 997 ≠ 0 ∧              -- division by zero
  sellAmt sell buy st ≤ inMax st.call ∧                -- "in amount is over max"
  XferOk st sell.bal st.pre to pool (sellAmt sell buy st) ∧
  -- "constant product invariant does not hold" (the product, in the other order)
  (1000 * rSell sell st) * (1000 * rBuy buy st)
    ≤ factor (balSell sell buy st) (rSell sell st) 0
      * factor (balBuy sell buy st) (rBuy buy st) (out st.call) ∧
  XferOk st buy.bal (s1 sell buy st) pool to (out st.call) ∧
  0 < balSell sell buy st ∧ 0 < balBuy sell buy st - out st.call ∧  -- "new reserves …"
  st.post =
    ((s2 sell buy st).set (.var sell.reserve) (.int (balSell sell buy st))
      ).set (.var buy.reserve) (.int (balBuy sell buy st - out st.call)) ∧
  st.writes = [.entry sell.bal.name to, .entry sell.bal.name pool, .entry buy.bal.name pool,
    .entry buy.bal.name to, .var sell.reserve, .var buy.reserve] ∧
  st.ret = .none

def swap : Step → Prop := fun st =>
  st.call.fn = "swap" ∧ st.call.caller ≠ pool ∧
  if buyA st.call then swapVia sideB sideA st else swapVia sideA sideB st

/-! ## withdraw -/

namespace Withdraw
variable (st : Step)

def balA  : Int := BalanceA.read st.pre pool
def balB  : Int := BalanceB.read st.pre pool
def total : Int := num st.pre "TotalShares"
def outA  : Int := (balA st * share st.call).tdiv (total st)
def outB  : Int := (balB st * share st.call).tdiv (total st)

/-- After `burn_shares(to, share_amount)`. -/
def s1 : Storage :=
  (st.pre.set (.entry "Shares" st.call.caller)
      (.int (Shares.read st.pre st.call.caller - share st.call))
    ).set (.var "TotalShares") (.int (total st - share st.call))
/-- After `transfer_a(to, out_a)`. -/
def s2 : Storage := xfer BalanceA (s1 st) pool st.call.caller (outA st)
/-- After `transfer_b(to, out_b)`. -/
def s3 : Storage := xfer BalanceB (s2 st) pool st.call.caller (outB st)

end Withdraw

open Withdraw in
def withdraw : Step → Prop := fun st =>
  let to := st.call.caller
  st.call.fn = "withdraw" ∧
  to ≠ pool ∧
  share st.call ≤ Shares.read st.pre to ∧         -- "insufficient shares"
  total st ≠ 0 ∧                                 -- division by zero
  minA st.call ≤ outA st ∧ minB st.call ≤ outB st ∧ -- "min not satisfied"
  XferOk st BalanceA (s1 st) pool to (outA st) ∧
  XferOk st BalanceB (s2 st) pool to (outB st) ∧
  st.post =
    ((s3 st).set (.var "ReserveA") (.int (balA st - outA st))
      ).set (.var "ReserveB") (.int (balB st - outB st)) ∧
  st.writes = [.entry "Shares" to, .var "TotalShares", .entry "A.Balance" pool,
    .entry "A.Balance" to, .entry "B.Balance" pool, .entry "B.Balance" to,
    .var "ReserveA", .var "ReserveB"]

/-! ## Deploy: `__constructor(token_a, token_b)` -/

/-- Storage right after deploy: token addresses ordered, no shares, empty reserves. -/
def deployed : Invariant := fun s =>
  (read s "TokenA" : Addr) < read s "TokenB" ∧
  num s "TotalShares" = 0 ∧ num s "ReserveA" = 0 ∧ num s "ReserveB" = 0 ∧
  ∀ a, Shares.read s a = 0

/-! ## Reading storage after a token transfer -/

theorem read_xfer (m : Map Int) (s : Storage) (src dst a : Addr) (amt : Int) :
    m.read (xfer m s src dst amt) a
      = m.read s a - (if a = src then amt else 0) + (if a = dst then amt else 0) := by
  simp only [xfer, receiveOn, spendOn, Map.read_set]
  by_cases h1 : a = dst <;> by_cases h2 : a = src <;> by_cases h3 : dst = src <;>
    simp_all <;> omega

theorem read_xfer_other (m m' : Map Int) (s : Storage) (src dst a : Addr) (amt : Int)
    (h : m.name ≠ m'.name) : m'.read (xfer m s src dst amt) a = m'.read s a := by
  simp only [xfer, receiveOn, spendOn, Map.read_set_other _ _ _ _ _ _ h]

@[simp] theorem num_xfer (m : Map Int) (s : Storage) (src dst : Addr) (amt : Int) (n : String) :
    num (xfer m s src dst amt) n = num s n := by
  simp [xfer, receiveOn, spendOn]

theorem xfer_apply (m : Map Int) (s : Storage) (src dst : Addr) (amt : Int) (k : Key)
    (h1 : k ≠ .entry m.name src) (h2 : k ≠ .entry m.name dst) :
    xfer m s src dst amt k = s k := by
  simp [xfer, receiveOn, spendOn, Storage.set, h1, h2]

/-! ## Which map a write touches -/

@[simp] theorem A_set_S (s : Storage) (w a : Addr) (v : Val) :
    BalanceA.read (s.set (.entry "Shares" w) v) a = BalanceA.read s a :=
  Map.read_set_other _ _ _ _ _ _ (by decide)
@[simp] theorem B_set_S (s : Storage) (w a : Addr) (v : Val) :
    BalanceB.read (s.set (.entry "Shares" w) v) a = BalanceB.read s a :=
  Map.read_set_other _ _ _ _ _ _ (by decide)
@[simp] theorem S_set_S (s : Storage) (w a : Addr) (v : Val) :
    Shares.read (s.set (.entry "Shares" w) v) a
      = if a = w then Stored.ofVal v else Shares.read s a :=
  Map.read_set Shares _ _ _ _
@[simp] theorem S_xfer_A (s : Storage) (src dst a : Addr) (x : Int) :
    Shares.read (xfer BalanceA s src dst x) a = Shares.read s a :=
  read_xfer_other _ _ _ _ _ _ _ (by decide)
@[simp] theorem S_xfer_B (s : Storage) (src dst a : Addr) (x : Int) :
    Shares.read (xfer BalanceB s src dst x) a = Shares.read s a :=
  read_xfer_other _ _ _ _ _ _ _ (by decide)
@[simp] theorem A_xfer_B (s : Storage) (src dst a : Addr) (x : Int) :
    BalanceA.read (xfer BalanceB s src dst x) a = BalanceA.read s a :=
  read_xfer_other _ _ _ _ _ _ _ (by decide)
@[simp] theorem B_xfer_A (s : Storage) (src dst a : Addr) (x : Int) :
    BalanceB.read (xfer BalanceA s src dst x) a = BalanceB.read s a :=
  read_xfer_other _ _ _ _ _ _ _ (by decide)

/-! ## The contract -/

theorem ne_AB : BalanceA.name ≠ BalanceB.name := by decide
theorem ne_BA : BalanceB.name ≠ BalanceA.name := by decide
theorem ne_SA : Shares.name ≠ BalanceA.name := by decide
theorem ne_SB : Shares.name ≠ BalanceB.name := by decide

def contract : Contract where
  entries := [deposit, swap, withdraw]
  framed e he st h k hk := by
    simp only [List.mem_cons, List.not_mem_nil, or_false] at he
    rcases he with rfl | rfl | rfl
    · obtain ⟨-, -, -, -, -, -, -, -, hpost, hw, -⟩ := h
      rw [hw] at hk
      simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hk
      rw [hpost]
      simp only [Storage.set, hk, ite_false, Deposit.s2, Deposit.s1]
      rw [xfer_apply BalanceB _ _ _ _ _ hk.2.2.1 hk.2.2.2.1, xfer_apply BalanceA _ _ _ _ _ hk.1 hk.2.1]
    · obtain ⟨-, -, h⟩ := h
      split at h <;>
      · obtain ⟨-, -, -, -, -, -, -, -, hpost, hw, -⟩ := h
        rw [hw] at hk
        simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hk
        rw [hpost]
        simp only [Storage.set, hk, ite_false, Swap.s2, Swap.s1]
        rw [xfer_apply _ _ _ _ _ _ hk.2.2.1 hk.2.2.2.1, xfer_apply _ _ _ _ _ _ hk.1 hk.2.1]
    · obtain ⟨-, -, -, -, -, -, -, -, hpost, hw⟩ := h
      rw [hw] at hk
      simp only [List.mem_cons, List.not_mem_nil, or_false, not_or] at hk
      rw [hpost]
      simp only [Storage.set, hk, ite_false, Withdraw.s3, Withdraw.s2, Withdraw.s1]
      rw [xfer_apply BalanceB _ _ _ _ _ hk.2.2.2.2.1 hk.2.2.2.2.2.1,
        xfer_apply BalanceA _ _ _ _ _ hk.2.2.1 hk.2.2.2.1]
      simp [Storage.set, hk.1, hk.2.1]

end SorobanAmm
