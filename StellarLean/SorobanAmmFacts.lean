import StellarLean.SorobanAmm
import StellarLean.Answer

/-
  Facts about the liquidity pool for the `answer` tactic.

  As in `SorobanTokenFacts.lean`, nothing here is specific to a question: it
  is what a WASM → Lean converter would emit for every entry point,
  mechanically, from the code:
  * which entry points the contract has;
  * each precondition (each `panic!` that did not fire, and each token
    transfer's own checks);
  * the effect on storage: every ledger entry, share balance and variable
    after the call.
-/

namespace SorobanAmm

open Query
open Spec (Addr)

/-! ## Entry points -/

@[answer →] theorem step_of_contract {st : Step} (h : contract.Steps st) :
    deposit st ∨ swap st ∨ withdraw st := by
  obtain ⟨e, he, hst⟩ := h
  simp only [contract, List.mem_cons, List.not_mem_nil, or_false] at he
  rcases he with rfl | rfl | rfl <;> simp_all

/-! ## Storage layout -/

@[answer =] theorem get_TokenA (c : Call) (s : Storage) : TokenA.get c s = read s "TokenA" := rfl
@[answer =] theorem get_TokenB (c : Call) (s : Storage) : TokenB.get c s = read s "TokenB" := rfl
@[answer =] theorem get_TotalShares (c : Call) (s : Storage) :
    TotalShares.get c s = num s "TotalShares" := rfl
@[answer =] theorem get_ReserveA (c : Call) (s : Storage) :
    ReserveA.get c s = num s "ReserveA" := rfl
@[answer =] theorem get_ReserveB (c : Call) (s : Storage) :
    ReserveB.get c s = num s "ReserveB" := rfl

/-- A variable is a storage slot. -/
@[answer =] theorem read_var [Stored α] (s : Storage) (n : String) :
    (read s n : α) = Stored.ofVal (s (.var n)) := rfl

@[answer =] theorem I128_MAX_eq : I128_MAX = 2 ^ 127 - 1 := rfl

attribute [answer] desiredA desiredB minA minB out inMax share

/-! ## A token transfer, read back -/

theorem read_spendOn_ne (m : Map Int) (s : Storage) (w a : Addr) (x : Int) (h : a ≠ w) :
    m.read (spendOn m s w x) a = m.read s a := by
  simp [spendOn, Map.read_set, h]

/-- The token's checks, for a transfer between two different accounts. -/
theorem XferOk.facts {st : Step} {m : Map Int} {s : Storage} {src dst : Addr} {x : Int}
    (h : XferOk st m s src dst x) (hne : dst ≠ src) :
    0 ≤ x ∧ x ≤ m.read s src ∧ m.read s dst + x ≤ I128_MAX := by
  obtain ⟨-, h1, h2, h3⟩ := h
  rw [read_spendOn_ne _ _ _ _ _ hne] at h3
  exact ⟨h1, h2, h3⟩

/-! ## Sums over holders -/

theorem sum_add_only (hs : List Addr) (f : Addr → Int) (w : Addr) (d : Int) :
    (hs.map fun a => f a + only w d a).sum = (hs.map f).sum + (hs.map (only w d)).sum := by
  induction hs <;> grind

/-! ## deposit -/

theorem depositAmounts_le {dA mA dB mB rA rB a b : Int}
    (h : depositAmounts dA mA dB mB rA rB = some (a, b)) : a ≤ dA ∧ b ≤ dB := by
  unfold depositAmounts at h
  split at h
  · simp_all
  · split at h
    · simp at h
    · simp only at h
      split at h
      · split at h
        · simp at h
        · simp only [Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          omega
      · split at h
        · simp at h
        · split at h
          · simp at h
          · simp only [Option.some.injEq, Prod.mk.injEq] at h
            omega

section
variable {st : Step} (h : deposit st)
include h

@[answer →] theorem deposit_fn : st.call.fn = "deposit" := h.1
@[answer →] theorem deposit_ne : st.call.caller ≠ pool := h.2.1

theorem deposit_le_desired : Deposit.amtA st ≤ desiredA st.call ∧ Deposit.amtB st ≤ desiredB st.call := by
  obtain ⟨-, -, hsome, -⟩ := h
  obtain ⟨⟨a, b⟩, hp⟩ := Option.isSome_iff_exists.mp hsome
  have := depositAmounts_le hp
  simp only [Deposit.amtA, Deposit.amtB, Deposit.amounts] at *
  rw [hp]
  exact this

/-- `get_deposit_amounts` never takes more than desired. -/
@[answer →] theorem deposit_amtA_le : Deposit.amtA st ≤ desiredA st.call := (deposit_le_desired h).1
@[answer →] theorem deposit_amtB_le : Deposit.amtB st ≤ desiredB st.call := (deposit_le_desired h).2
/-- "both amounts must be strictly positive" -/
@[answer →] theorem deposit_amtA_pos : 0 < Deposit.amtA st := h.2.2.2.1
@[answer →] theorem deposit_amtB_pos : 0 < Deposit.amtB st := h.2.2.2.2.1

/-- Token A's checks on `transfer(to, pool, amount_a)`. -/
@[answer →] theorem deposit_xferA :
    Deposit.amtA st ≤ BalanceA.read st.pre st.call.caller ∧
    BalanceA.read st.pre pool + Deposit.amtA st ≤ I128_MAX :=
  let ⟨_, h2, h3⟩ := h.2.2.2.2.2.1.facts (Ne.symm h.2.1); ⟨h2, h3⟩

/-- Token B's checks on `transfer(to, pool, amount_b)`. -/
@[answer →] theorem deposit_xferB :
    Deposit.amtB st ≤ BalanceB.read st.pre st.call.caller ∧
    BalanceB.read st.pre pool + Deposit.amtB st ≤ I128_MAX := by
  have ⟨_, h2, h3⟩ := h.2.2.2.2.2.2.1.facts (Ne.symm h.2.1)
  simp only [Deposit.s1, B_xfer_A] at h2 h3
  exact ⟨h2, h3⟩

theorem deposit_post : st.post =
    ((((Deposit.s2 st).set (.entry "Shares" st.call.caller)
        (.int (Shares.read (Deposit.s2 st) st.call.caller + Deposit.minted st))
      ).set (.var "TotalShares") (.int (num (Deposit.s2 st) "TotalShares" + Deposit.minted st))
      ).set (.var "ReserveA") (.int (Deposit.balA st))
      ).set (.var "ReserveB") (.int (Deposit.balB st)) := h.2.2.2.2.2.2.2.2.1

@[answer =] theorem deposit_balA (a : Addr) : BalanceA.read st.post a = BalanceA.read st.pre a
    - (if a = st.call.caller then Deposit.amtA st else 0) + (if a = pool then Deposit.amtA st else 0) := by
  simp [deposit_post h, Deposit.s2, Deposit.s1, read_xfer]

@[answer =] theorem deposit_balB (a : Addr) : BalanceB.read st.post a = BalanceB.read st.pre a
    - (if a = st.call.caller then Deposit.amtB st else 0) + (if a = pool then Deposit.amtB st else 0) := by
  simp [deposit_post h, Deposit.s2, Deposit.s1, read_xfer]

@[answer =] theorem deposit_shares (a : Addr) : Shares.read st.post a
    = Shares.read st.pre a + (if a = st.call.caller then Deposit.minted st else 0) := by
  simp only [deposit_post h, Map.read_set_var, S_set_S, Deposit.s2, Deposit.s1, S_xfer_A, S_xfer_B,
    ofVal_int]
  split <;> simp_all

/-- The change of any sum of share balances. -/
@[answer =] theorem deposit_sharesSum (hs : List Addr) :
    (hs.map (Shares.read st.post)).sum
      = (hs.map (Shares.read st.pre)).sum + (hs.map (only st.call.caller (Deposit.minted st))).sum := by
  rw [← sum_add_only]
  congr 1
  exact List.map_congr_left fun a _ => by rw [deposit_shares h]; rfl

@[answer =] theorem deposit_total :
    num st.post "TotalShares" = num st.pre "TotalShares" + Deposit.minted st := by
  simp [deposit_post h, read_set_var, Deposit.s2, Deposit.s1]

/-- The reserves are set to the pool's balances. -/
@[answer =] theorem deposit_resA : num st.post "ReserveA" = BalanceA.read st.post pool := by
  simp [deposit_post h, read_set_var, Deposit.balA]
@[answer =] theorem deposit_resB : num st.post "ReserveB" = BalanceB.read st.post pool := by
  simp [deposit_post h, read_set_var, Deposit.balB]

/-- Frame: only these eight slots are written. -/
@[answer =] theorem deposit_frame (k : Key)
    (h1 : k ≠ .entry "A.Balance" st.call.caller) (h2 : k ≠ .entry "A.Balance" pool)
    (h3 : k ≠ .entry "B.Balance" st.call.caller) (h4 : k ≠ .entry "B.Balance" pool)
    (h5 : k ≠ .entry "Shares" st.call.caller) (h6 : k ≠ .var "TotalShares")
    (h7 : k ≠ .var "ReserveA") (h8 : k ≠ .var "ReserveB") : st.post k = st.pre k :=
  contract.framed _ (by simp [contract]) st h k (by
    rw [h.2.2.2.2.2.2.2.2.2.1]; simp [h1, h2, h3, h4, h5, h6, h7, h8])

/-- Variables `deposit` does not write (a converter lists them from `DataKey`). -/
@[answer =] theorem deposit_keeps_TokenA : st.post (.var "TokenA") = st.pre (.var "TokenA") :=
  deposit_frame h _ (by simp) (by simp) (by simp) (by simp) (by simp) (by simp) (by simp) (by simp)
@[answer =] theorem deposit_keeps_TokenB : st.post (.var "TokenB") = st.pre (.var "TokenB") :=
  deposit_frame h _ (by simp) (by simp) (by simp) (by simp) (by simp) (by simp) (by simp) (by simp)

@[answer →] theorem deposit_ret : st.ret = .none := h.2.2.2.2.2.2.2.2.2.2

end

/-! ## swap -/

namespace Swap

/-- What the signer sells. -/
def paid (st : Step) : Int := if buyA st.call then sellAmt sideB sideA st else sellAmt sideA sideB st

/-- What the signer gains of token A (negative: pays) and of token B. -/
def gainA (st : Step) : Int := if buyA st.call then out st.call else - paid st
def gainB (st : Step) : Int := if buyA st.call then - paid st else out st.call

end Swap

section
variable {sell buy : Side} {st : Step} (h : swapVia sell buy st)
  (hd : sell.bal.name ≠ buy.bal.name) (hne : st.call.caller ≠ pool)
include h

theorem swapVia_post : st.post =
    ((Swap.s2 sell buy st).set (.var sell.reserve) (.int (Swap.balSell sell buy st))
      ).set (.var buy.reserve) (.int (Swap.balBuy sell buy st - out st.call)) := h.2.2.2.2.2.2.2.2.1

theorem swapVia_sell (a : Addr) (hd : sell.bal.name ≠ buy.bal.name) :
    sell.bal.read st.post a = sell.bal.read st.pre a
      - (if a = st.call.caller then Swap.sellAmt sell buy st else 0)
      + (if a = pool then Swap.sellAmt sell buy st else 0) := by
  simp only [swapVia_post h, Map.read_set_var, Swap.s2, read_xfer_other _ _ _ _ _ _ _ hd.symm,
    Swap.s1, read_xfer]

theorem swapVia_buy (a : Addr) (hd : sell.bal.name ≠ buy.bal.name) :
    buy.bal.read st.post a = buy.bal.read st.pre a
      + (if a = st.call.caller then out st.call else 0)
      - (if a = pool then out st.call else 0) := by
  simp only [swapVia_post h, Map.read_set_var, Swap.s2, read_xfer, Swap.s1,
    read_xfer_other _ _ _ _ _ _ _ hd]
  omega

theorem swapVia_other (m : Map Int) (a : Addr) (h1 : sell.bal.name ≠ m.name)
    (h2 : buy.bal.name ≠ m.name) : m.read st.post a = m.read st.pre a := by
  simp only [swapVia_post h, Map.read_set_var, Swap.s2, Swap.s1, read_xfer_other _ _ _ _ _ _ _ h1,
    read_xfer_other _ _ _ _ _ _ _ h2]

theorem swapVia_var (n : String) (h1 : n ≠ sell.reserve) (h2 : n ≠ buy.reserve) :
    num st.post n = num st.pre n := by
  simp [swapVia_post h, read_set_var, h1, h2, Swap.s2, Swap.s1]

theorem swapVia_resSell (hr : sell.reserve ≠ buy.reserve) (hd : sell.bal.name ≠ buy.bal.name) :
    num st.post sell.reserve = sell.bal.read st.post pool := by
  simp only [swapVia_post h, read_set_var, hr, ite_true, ite_false, ofVal_int, Map.read_set_var]
  simp [Swap.balSell, Swap.s2, read_xfer_other _ _ _ _ _ _ _ hd.symm]

theorem swapVia_resBuy (hne : st.call.caller ≠ pool) :
    num st.post buy.reserve = buy.bal.read st.post pool := by
  simp only [swapVia_post h, read_set_var, ite_true, ofVal_int, Map.read_set_var]
  simp [Swap.balBuy, Swap.s2, read_xfer, Ne.symm hne]

/-- The two token transfers' checks (the signer and the pool are different). -/
theorem swapVia_xfers (hne : st.call.caller ≠ pool) (hd : sell.bal.name ≠ buy.bal.name) :
    (0 ≤ Swap.sellAmt sell buy st ∧ Swap.sellAmt sell buy st ≤ sell.bal.read st.pre st.call.caller ∧
      sell.bal.read st.pre pool + Swap.sellAmt sell buy st ≤ I128_MAX) ∧
    (0 ≤ out st.call ∧ out st.call ≤ buy.bal.read st.pre pool ∧
      buy.bal.read st.pre st.call.caller + out st.call ≤ I128_MAX) := by
  have h1 := h.2.2.2.1.facts (Ne.symm hne)
  have h2 := h.2.2.2.2.2.1.facts hne
  simp only [Swap.s1, read_xfer_other _ _ _ _ _ _ _ hd] at h2
  exact ⟨h1, h2⟩

end

theorem sideA_bal : sideA.bal = BalanceA := rfl
theorem sideB_bal : sideB.bal = BalanceB := rfl

section
variable {st : Step} (h : swap st)
include h

@[answer →] theorem swap_fn : st.call.fn = "swap" := h.1
@[answer →] theorem swap_ne : st.call.caller ≠ pool := h.2.1

theorem swap_dir : (buyA st.call = true ∧ swapVia sideB sideA st) ∨
    (buyA st.call = false ∧ swapVia sideA sideB st) := by
  have := h.2.2
  cases hb : buyA st.call <;> simp_all

@[answer =] theorem swap_balA (a : Addr) : BalanceA.read st.post a = BalanceA.read st.pre a
    + (if a = st.call.caller then Swap.gainA st else 0) - (if a = pool then Swap.gainA st else 0) := by
  rcases swap_dir h with ⟨hb, hs⟩ | ⟨hb, hs⟩
  · have := swapVia_buy hs a (by decide)
    simp only [sideA_bal] at this
    simp [this, Swap.gainA, hb]
  · have := swapVia_sell hs a (by decide)
    simp only [sideA_bal] at this
    simp only [this, Swap.gainA, Swap.paid, hb]
    split <;> split <;> simp <;> omega

@[answer =] theorem swap_balB (a : Addr) : BalanceB.read st.post a = BalanceB.read st.pre a
    + (if a = st.call.caller then Swap.gainB st else 0) - (if a = pool then Swap.gainB st else 0) := by
  rcases swap_dir h with ⟨hb, hs⟩ | ⟨hb, hs⟩
  · have := swapVia_sell hs a (by decide)
    simp only [sideB_bal] at this
    simp only [this, Swap.gainB, Swap.paid, hb]
    split <;> split <;> simp <;> omega
  · have := swapVia_buy hs a (by decide)
    simp only [sideB_bal] at this
    simp [this, Swap.gainB, hb]

@[answer =] theorem swap_shares (a : Addr) : Shares.read st.post a = Shares.read st.pre a := by
  rcases swap_dir h with ⟨-, hs⟩ | ⟨-, hs⟩ <;> exact swapVia_other hs Shares a (by decide) (by decide)

@[answer =] theorem swap_sharesFn : Shares.read st.post = Shares.read st.pre :=
  funext (swap_shares h)

/-- "not enough token to buy" -/
@[answer →] theorem swap_out_le_reserve :
    if buyA st.call then out st.call ≤ num st.pre "ReserveA"
    else out st.call ≤ num st.pre "ReserveB" := by
  rcases swap_dir h with ⟨hb, hs⟩ | ⟨hb, hs⟩ <;> simp only [hb] <;> exact hs.1

@[answer =] theorem swap_total : num st.post "TotalShares" = num st.pre "TotalShares" := by
  rcases swap_dir h with ⟨-, hs⟩ | ⟨-, hs⟩ <;> exact swapVia_var hs _ (by decide) (by decide)

@[answer =] theorem swap_resA : num st.post "ReserveA" = BalanceA.read st.post pool := by
  rcases swap_dir h with ⟨-, hs⟩ | ⟨-, hs⟩
  · exact swapVia_resBuy hs h.2.1
  · exact swapVia_resSell hs (by decide) (by decide)

@[answer =] theorem swap_resB : num st.post "ReserveB" = BalanceB.read st.post pool := by
  rcases swap_dir h with ⟨-, hs⟩ | ⟨-, hs⟩
  · exact swapVia_resSell hs (by decide) (by decide)
  · exact swapVia_resBuy hs h.2.1

/-- "in amount is over max" -/
@[answer →] theorem swap_paid_le : Swap.paid st ≤ inMax st.call := by
  rcases swap_dir h with ⟨hb, hs⟩ | ⟨hb, hs⟩ <;> simp only [Swap.paid, hb] <;> exact hs.2.2.1

/-- Token A's checks on its transfer (sold or bought). -/
@[answer →] theorem swap_xferA :
    if buyA st.call then
      0 ≤ out st.call ∧ out st.call ≤ BalanceA.read st.pre pool ∧
        BalanceA.read st.pre st.call.caller + out st.call ≤ I128_MAX
    else
      0 ≤ Swap.paid st ∧ Swap.paid st ≤ BalanceA.read st.pre st.call.caller ∧
        BalanceA.read st.pre pool + Swap.paid st ≤ I128_MAX := by
  rcases swap_dir h with ⟨hb, hs⟩ | ⟨hb, hs⟩
  · simpa [hb, sideA_bal] using (swapVia_xfers hs h.2.1 (by decide)).2
  · simpa [hb, Swap.paid, sideA_bal] using (swapVia_xfers hs h.2.1 (by decide)).1

/-- Token B's checks on its transfer (sold or bought). -/
@[answer →] theorem swap_xferB :
    if buyA st.call then
      0 ≤ Swap.paid st ∧ Swap.paid st ≤ BalanceB.read st.pre st.call.caller ∧
        BalanceB.read st.pre pool + Swap.paid st ≤ I128_MAX
    else
      0 ≤ out st.call ∧ out st.call ≤ BalanceB.read st.pre pool ∧
        BalanceB.read st.pre st.call.caller + out st.call ≤ I128_MAX := by
  rcases swap_dir h with ⟨hb, hs⟩ | ⟨hb, hs⟩
  · simpa [hb, Swap.paid, sideB_bal] using (swapVia_xfers hs h.2.1 (by decide)).1
  · simpa [hb, sideB_bal] using (swapVia_xfers hs h.2.1 (by decide)).2

/-- Frame: only these six slots are written (in either direction). -/
@[answer =] theorem swap_frame (k : Key)
    (h1 : k ≠ .entry "A.Balance" st.call.caller) (h2 : k ≠ .entry "A.Balance" pool)
    (h3 : k ≠ .entry "B.Balance" st.call.caller) (h4 : k ≠ .entry "B.Balance" pool)
    (h5 : k ≠ .var "ReserveA") (h6 : k ≠ .var "ReserveB") : st.post k = st.pre k := by
  refine contract.framed _ (by simp [contract]) st h k ?_
  rcases swap_dir h with ⟨-, hs⟩ | ⟨-, hs⟩ <;> rw [hs.2.2.2.2.2.2.2.2.2.1] <;>
    simp [sideA, sideB, BalanceA, BalanceB, h1, h2, h3, h4, h5, h6]

/-- Variables `swap` does not write (a converter lists them from `DataKey`). -/
@[answer =] theorem swap_keeps_TokenA : st.post (.var "TokenA") = st.pre (.var "TokenA") :=
  swap_frame h _ (by simp) (by simp) (by simp) (by simp) (by simp) (by simp)
@[answer =] theorem swap_keeps_TokenB : st.post (.var "TokenB") = st.pre (.var "TokenB") :=
  swap_frame h _ (by simp) (by simp) (by simp) (by simp) (by simp) (by simp)

@[answer →] theorem swap_ret : st.ret = .none := by
  rcases swap_dir h with ⟨-, hs⟩ | ⟨-, hs⟩ <;> exact hs.2.2.2.2.2.2.2.2.2.2

end

/-! ## withdraw -/

section
variable {st : Step} (h : withdraw st)
include h

@[answer →] theorem withdraw_fn : st.call.fn = "withdraw" := h.1
@[answer →] theorem withdraw_ne : st.call.caller ≠ pool := h.2.1
/-- "insufficient shares" -/
@[answer →] theorem withdraw_has_shares : share st.call ≤ Shares.read st.pre st.call.caller := h.2.2.1
/-- "min not satisfied" -/
@[answer →] theorem withdraw_minA : minA st.call ≤ Withdraw.outA st := h.2.2.2.2.1
@[answer →] theorem withdraw_minB : minB st.call ≤ Withdraw.outB st := h.2.2.2.2.2.1

/-- Token A's checks on `transfer_a(to, out_a)`. -/
@[answer →] theorem withdraw_xferA :
    0 ≤ Withdraw.outA st ∧ Withdraw.outA st ≤ BalanceA.read st.pre pool ∧
    BalanceA.read st.pre st.call.caller + Withdraw.outA st ≤ I128_MAX := by
  have := h.2.2.2.2.2.2.1.facts h.2.1
  simpa [Withdraw.s1] using this

/-- Token B's checks on `transfer_b(to, out_b)`. -/
@[answer →] theorem withdraw_xferB :
    0 ≤ Withdraw.outB st ∧ Withdraw.outB st ≤ BalanceB.read st.pre pool ∧
    BalanceB.read st.pre st.call.caller + Withdraw.outB st ≤ I128_MAX := by
  have := h.2.2.2.2.2.2.2.1.facts h.2.1
  simpa [Withdraw.s2, Withdraw.s1] using this

theorem withdraw_post : st.post =
    ((Withdraw.s3 st).set (.var "ReserveA") (.int (Withdraw.balA st - Withdraw.outA st))
      ).set (.var "ReserveB") (.int (Withdraw.balB st - Withdraw.outB st)) :=
  h.2.2.2.2.2.2.2.2.1

@[answer =] theorem withdraw_balA (a : Addr) : BalanceA.read st.post a = BalanceA.read st.pre a
    + (if a = st.call.caller then Withdraw.outA st else 0)
    - (if a = pool then Withdraw.outA st else 0) := by
  simp [withdraw_post h, Withdraw.s3, Withdraw.s2, Withdraw.s1, read_xfer]
  omega

@[answer =] theorem withdraw_balB (a : Addr) : BalanceB.read st.post a = BalanceB.read st.pre a
    + (if a = st.call.caller then Withdraw.outB st else 0)
    - (if a = pool then Withdraw.outB st else 0) := by
  simp [withdraw_post h, Withdraw.s3, Withdraw.s2, Withdraw.s1, read_xfer]
  omega

@[answer =] theorem withdraw_shares (a : Addr) : Shares.read st.post a
    = Shares.read st.pre a - (if a = st.call.caller then share st.call else 0) := by
  simp only [withdraw_post h, Map.read_set_var, Withdraw.s3, Withdraw.s2, S_xfer_A, S_xfer_B,
    Withdraw.s1, S_set_S, ofVal_int]
  split <;> simp_all

/-- The change of any sum of share balances. -/
@[answer =] theorem withdraw_sharesSum (hs : List Addr) :
    (hs.map (Shares.read st.post)).sum
      = (hs.map (Shares.read st.pre)).sum + (hs.map (only st.call.caller (- share st.call))).sum := by
  rw [← sum_add_only]
  congr 1
  exact List.map_congr_left fun a _ => by
    rw [withdraw_shares h]; simp only [only]; split <;> omega

@[answer =] theorem withdraw_total :
    num st.post "TotalShares" = num st.pre "TotalShares" - share st.call := by
  simp [withdraw_post h, read_set_var, Withdraw.s3, Withdraw.s2, Withdraw.s1, Withdraw.total]

@[answer =] theorem withdraw_resA : num st.post "ReserveA" = BalanceA.read st.post pool := by
  simp [withdraw_post h, read_set_var, Withdraw.s3, Withdraw.s2, Withdraw.s1, Withdraw.balA,
    read_xfer, Ne.symm h.2.1]

@[answer =] theorem withdraw_resB : num st.post "ReserveB" = BalanceB.read st.post pool := by
  simp [withdraw_post h, read_set_var, Withdraw.s3, Withdraw.s2, Withdraw.s1, Withdraw.balB,
    read_xfer, Ne.symm h.2.1]

/-- Frame: only these eight slots are written. -/
@[answer =] theorem withdraw_frame (k : Key)
    (h1 : k ≠ .entry "A.Balance" st.call.caller) (h2 : k ≠ .entry "A.Balance" pool)
    (h3 : k ≠ .entry "B.Balance" st.call.caller) (h4 : k ≠ .entry "B.Balance" pool)
    (h5 : k ≠ .entry "Shares" st.call.caller) (h6 : k ≠ .var "TotalShares")
    (h7 : k ≠ .var "ReserveA") (h8 : k ≠ .var "ReserveB") : st.post k = st.pre k :=
  contract.framed _ (by simp [contract]) st h k (by
    rw [h.2.2.2.2.2.2.2.2.2]; simp [h1, h2, h3, h4, h5, h6, h7, h8])

/-- Variables `withdraw` does not write (a converter lists them from `DataKey`). -/
@[answer =] theorem withdraw_keeps_TokenA : st.post (.var "TokenA") = st.pre (.var "TokenA") :=
  withdraw_frame h _ (by simp) (by simp) (by simp) (by simp) (by simp) (by simp) (by simp) (by simp)
@[answer =] theorem withdraw_keeps_TokenB : st.post (.var "TokenB") = st.pre (.var "TokenB") :=
  withdraw_frame h _ (by simp) (by simp) (by simp) (by simp) (by simp) (by simp) (by simp) (by simp)

end

end SorobanAmm
