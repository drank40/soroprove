import StellarLean.SorobanAmmFacts

/-
  Questions about the liquidity pool (`SorobanAmm.lean`), grouped by what
  they are about: auth, storage, transfers. Each theorem statement is a
  question; its proof is the answer.

  Most are proved with `answer` alone. The ones that are not say why.
-/

namespace SorobanAmm.Answers

open Query
open Spec (Addr)

/-! ## Vocabulary for this contract -/

/-- `user` is the pool itself. -/
@[answer] def isPool (u : Addr) : Question := fun _ => u = pool

/-- The call is a swap that buys token A (`buy_a = true`) / buys token B. -/
@[answer] def buysA : Question := fun st => buyA st.call = true
@[answer] def buysB : Question := fun st => buyA st.call = false

/-- `I` holds before / after the call. -/
@[answer] def before (I : Invariant) : Question := fun st => I st.pre
@[answer] def after  (I : Invariant) : Question := fun st => I st.post

/-- The stored reserves are the pool's actual token balances. -/
@[answer] def reservesSynced : Invariant := fun s =>
  num s "ReserveA" = BalanceA.read s pool ∧ num s "ReserveB" = BalanceB.read s pool

/-- The (ghost) list of holders is a proper list that includes the signer. -/
@[answer] def tracked : Question := fun st =>
  st.call.holders.Nodup ∧ st.call.caller ∈ st.call.holders

/-- Every balance of both tokens fits in an i128 and is never negative. -/
@[answer] def validLedgers : Invariant := fun s => ∀ a,
  0 ≤ BalanceA.read s a ∧ BalanceA.read s a ≤ I128_MAX ∧
  0 ≤ BalanceB.read s a ∧ BalanceB.read s a ≤ I128_MAX

attribute [answer] Swap.gainA Swap.gainB

/-! ## Auth -/

/-- Can anyone lose tokens without signing? No: only the signer, and the pool
    (which authorizes its own transfers), can see a token balance go down. -/
theorem only_signer_or_pool_lose_tokens :
    contract ⊨ ∀ₛ user, (neverDecreases BalanceA[user] ∧ₛ neverDecreases BalanceB[user]).except
      (isCaller user ∨ₛ isPool user) := by
  answer

/-- Can anyone lose pool shares without signing? No. -/
theorem only_signer_loses_shares :
    contract ⊨ ∀ₛ user, (neverDecreases Shares[user]).except (isCaller user) := by
  answer

/-- Do tokens only move between the signer and the pool? Yes: for each token,
    the signer's and the pool's balances together stay the same. -/
theorem tokens_move_between_signer_and_pool :
    contract ⊨ unchanged (BalanceA[caller] + BalanceA[pool])
      ∧ₛ unchanged (BalanceB[caller] + BalanceB[pool]) := by
  answer

/-! ## Storage -/

/-- Can the pool's token addresses change after deploy? No. -/
theorem token_addresses_fixed : contract ⊨ unchanged TokenA ∧ₛ unchanged TokenB := by
  answer

/-- Does a call touch anyone's shares except the signer's? No. -/
theorem others_shares_untouched :
    contract ⊨ ∀ₛ user, (unchanged Shares[user]).except (isCaller user) := by
  answer

/-- Does a call touch anyone's token balance except the signer's and the pool's? No. -/
theorem others_tokens_untouched :
    contract ⊨ ∀ₛ user, (unchanged BalanceA[user] ∧ₛ unchanged BalanceB[user]).except
      (isCaller user ∨ₛ isPool user) := by
  answer

/-- After every call, are the stored reserves the pool's real balances? Yes. -/
theorem reserves_match_balances : contract ⊨ after reservesSynced := by
  answer

/-- Does `TotalShares` move exactly with the sum of everyone's shares? Yes
    (counted over tracked holders). -/
theorem total_shares_tracks_sum :
    contract ⊨ (unchanged (TotalShares - Shares.total)).given tracked := by
  answer

/-- After any sequence of pool calls, are both tokens' ledgers still valid? Yes. -/
theorem ledgers_stay_valid {s : Storage} (h : contract.Reachable validLedgers s) :
    validLedgers s := by
  answer

/-! ## Transfers -/

/-- When swapping for token A, does the signer get exactly `out`? Yes. -/
theorem swap_pays_out :
    contract ⊨ (changesBy BalanceA[caller] out).given (calls "swap" ∧ₛ buysA) := by
  answer

/-- When swapping for token B, does the signer get exactly `out` of B? Yes. (This replaces
    `swap_swaps`, which claimed the pool's token-A balance changes by `out`: it changes by the
    amount paid in, so `answer` rightly could not prove it.) -/
theorem swap_pays_out_b :
    contract ⊨ (changesBy BalanceB[caller] out).given (calls "swap" ∧ₛ buysB) := by
  answer

/-- Does a swap ever take more than `in_max` from the signer? No, in either direction. -/
theorem swap_respects_in_max :
    contract ⊨ ((dropsAtMost BalanceB[caller] inMax).given buysA
      ∧ₛ (dropsAtMost BalanceA[caller] inMax).given buysB).given (calls "swap") := by
  answer

/-- Does a deposit ever take more than desired? No. -/
theorem deposit_respects_desired :
    contract ⊨ (dropsAtMost BalanceA[caller] desiredA ∧ₛ dropsAtMost BalanceB[caller] desiredB).given
      (calls "deposit") := by
  answer

/-- Does a deposit always take both tokens? Yes. -/
theorem deposit_takes_both :
    contract ⊨ (decreases BalanceA[caller] ∧ₛ decreases BalanceB[caller]).given (calls "deposit") := by
  answer

-- theorem deposit_not_both :
--     contract ⊨ (decreases BalanceA[caller] ∧ₛ decreases BalanceB[caller]).except (calls "deposit") := by
--   answer

/-- Does a withdrawal pay at least `min_a` and `min_b`? Yes. -/
theorem withdraw_respects_min :
    contract ⊨ (gainsAtLeast BalanceA[caller] minA ∧ₛ gainsAtLeast BalanceB[caller] minB).given
      (calls "withdraw") := by
  answer

/-- Does a withdrawal burn exactly `share_amount` of the signer's shares? Yes. -/
theorem withdraw_burns_shares :
    contract ⊨ (changesBy Shares[caller] (- share ·)).given (calls "withdraw") := by
  answer

/-- Can you withdraw more shares than you have? No, the call fails. -/
theorem withdraw_fails_without_shares (st : Step)
    (h : Shares.read st.pre st.call.caller < share st.call) : ¬ withdraw st := by
  answer

/-- Can you buy more token A than the pool holds in reserve? No, the call fails. -/
theorem swap_fails_beyond_reserve (st : Step) (hb : buyA st.call = true)
    (h : num st.pre "ReserveA" < out st.call) : ¬ swap st := by
  answer

/-- Can you swap for a negative amount? No, the call fails. -/
theorem swap_fails_negative (st : Step) (h : out st.call < 0) : ¬ swap st := by
  answer

/-! ## Harder questions, proved by hand

  `answer` does not prove these: the first is about a product of two
  reserves (`grind` does not reason about products of unknowns), the second
  asks for an example call to exist, the third needs a fact about `/`. -/

theorem factor_le (b r o : Int) : factor b r o ≤ 1000 * (b - o) := by
  simp only [factor]; split <;> omega

/-- One direction of a swap, given that the bought side's reserve was in sync. -/
theorem swapVia_product {sell buy : Side} {st : Step} (h : swapVia sell buy st)
    (hd : sell.bal.name ≠ buy.bal.name) (hr : sell.reserve ≠ buy.reserve)
    (hne : st.call.caller ≠ pool)
    (hsync : num st.pre buy.reserve = buy.bal.read st.pre pool) :
    num st.pre sell.reserve * num st.pre buy.reserve
      ≤ num st.post sell.reserve * num st.post buy.reserve := by
  have hbuy : Swap.balBuy sell buy st = Swap.rBuy buy st := by
    simp [Swap.balBuy, Swap.s1, read_xfer_other _ _ _ _ _ _ _ hd, Swap.rBuy, hsync]
  have hout := (swapVia_xfers h hne hd).2.1
  have hS : num st.post sell.reserve = Swap.balSell sell buy st := by
    simp [swapVia_post h, read_set_var, hr]
  have hB : num st.post buy.reserve = Swap.rBuy buy st - out st.call := by
    simp [swapVia_post h, read_set_var, hbuy]
  have hg := h.2.2.2.2.1
  have hpos := h.2.2.2.2.2.2.2.1
  rw [hbuy] at hg hpos
  -- What was bought: the factor is exactly the new reserve (no fee on the way out).
  have hfB : factor (Swap.rBuy buy st) (Swap.rBuy buy st) (out st.call)
      = 1000 * (Swap.rBuy buy st - out st.call) := by
    simp only [factor]; split <;> omega
  rw [hfB] at hg
  -- What was sold: the factor is at most the new reserve (the fee is kept).
  have := Int.mul_le_mul_of_nonneg_right (factor_le (Swap.balSell sell buy st) (Swap.rSell sell st) 0)
    (by omega : (0 : Int) ≤ 1000 * (Swap.rBuy buy st - out st.call))
  rw [hS, hB]
  show Swap.rSell sell st * Swap.rBuy buy st ≤ _
  have key : 1000000 * (Swap.rSell sell st * Swap.rBuy buy st)
      ≤ 1000000 * (Swap.balSell sell buy st * (Swap.rBuy buy st - out st.call)) := by
    have e1 : (1000 * Swap.rSell sell st) * (1000 * Swap.rBuy buy st)
        = 1000000 * (Swap.rSell sell st * Swap.rBuy buy st) := by grind
    have e2 : 1000 * (Swap.balSell sell buy st - 0) * (1000 * (Swap.rBuy buy st - out st.call))
        = 1000000 * (Swap.balSell sell buy st * (Swap.rBuy buy st - out st.call)) := by grind
    omega
  exact Int.le_of_mul_le_mul_left key (by decide)

/-- Can a swap lower `reserve_a * reserve_b`? No, when the reserves were in sync
    before the call (which every call leaves them: `reserves_match_balances`). -/
theorem swap_keeps_product :
    contract ⊨ (neverDecreases (ReserveA * ReserveB)).given
      (calls "swap" ∧ₛ before reservesSynced) := by
  refine Contract.models_of_steps fun st hst ⟨hfn, hsync⟩ => ?_
  have hfn : st.call.fn = "swap" := hfn
  have hs : swap st := by
    rcases step_of_contract hst with h | h | h
    · exact absurd ((deposit_fn h).symm.trans hfn) (by decide)
    · exact h
    · exact absurd ((withdraw_fn h).symm.trans hfn) (by decide)
  simp only [neverDecreases, get_mul, get_ReserveA, get_ReserveB]
  rcases swap_dir hs with ⟨-, hv⟩ | ⟨-, hv⟩
  · have := swapVia_product hv (by decide) (by decide) hs.2.1 hsync.1
    rw [Int.mul_comm (num st.pre "ReserveA"), Int.mul_comm (num st.post "ReserveA")]
    exact this
  · exact swapVia_product hv (by decide) (by decide) hs.2.1 hsync.2

/-- A pool holding 1 of each token with 2 shares outstanding, and a signer with
    no shares. -/
def lopsided : Storage := fun k =>
  if k = .entry "A.Balance" pool then .int 1
  else if k = .entry "B.Balance" pool then .int 1
  else if k = .var "TotalShares" then .int 2
  else .none

/-- `withdraw(to, share_amount = -1, min_a = 0, min_b = 0)` on `lopsided`. -/
def negWithdraw : Step :=
  let st0 : Step :=
    { call := { caller := pool + 1, args := ⟨0, 0⟩, holders := [], fn := "withdraw",
                arg := fun n => if n = "share_amount" then -1 else 0 }
      pre := lopsided, post := lopsided, writes := [] }
  { st0 with
    post := ((Withdraw.s3 st0).set (.var "ReserveA") (.int (Withdraw.balA st0 - Withdraw.outA st0))
              ).set (.var "ReserveB") (.int (Withdraw.balB st0 - Withdraw.outB st0))
    writes := [.entry "Shares" (pool + 1), .var "TotalShares", .entry "A.Balance" pool,
      .entry "A.Balance" (pool + 1), .entry "B.Balance" pool, .entry "B.Balance" (pool + 1),
      .var "ReserveA", .var "ReserveB"] }

/-- Can a withdrawal hand out shares for nothing? In some storage states, yes.
    `withdraw` never checks `share_amount ≥ 0`: with `-1`, both payouts round
    to 0 (`1 * -1 / 2` is 0 in Rust), "burning" `-1` shares adds one, and no
    token moves. -/
theorem withdraw_can_mint_free_shares :
    ∃ st, withdraw st ∧ share st.call < 0 ∧ increases Shares[caller] st ∧
      unchanged BalanceA[caller] st ∧ unchanged BalanceB[caller] st := by
  refine ⟨negWithdraw, ?_, ?_, ?_, ?_, ?_⟩ <;>
    simp [negWithdraw, withdraw, Withdraw.outA, Withdraw.outB, Withdraw.balA, Withdraw.balB,
      Withdraw.total, Withdraw.s1, Withdraw.s2, Withdraw.s3, XferOk, share, minA, minB, lopsided,
      Map.read, Query.read, Storage.set, spendOn, xfer, receiveOn, increases, unchanged, caller,
      Shares, BalanceA, BalanceB, I128_MAX, SorobanToken.I128_MAX] <;> decide

/-- When is that impossible? Whenever the pool holds at least `TotalShares` of
    token A: then a negative `share_amount` makes `out_a` negative and token A's
    transfer panics. (The same holds for token B.) -/
theorem withdraw_share_nonneg (st : Step) (h : withdraw st)
    (ht : 0 < num st.pre "TotalShares") (hA : num st.pre "TotalShares" ≤ BalanceA.read st.pre pool) :
    0 ≤ share st.call := by
  apply Classical.byContradiction
  intro hs
  have hx := (withdraw_xferA h).1
  simp only [Withdraw.outA, Withdraw.balA, Withdraw.total] at hx
  have hn : BalanceA.read st.pre pool ≤ BalanceA.read st.pre pool * (- share st.call) := by
    have := Int.mul_le_mul_of_nonneg_left (by omega : (1 : Int) ≤ - share st.call)
      (by omega : 0 ≤ BalanceA.read st.pre pool)
    simpa using this
  have hq : 1 ≤ (BalanceA.read st.pre pool * (- share st.call)) / num st.pre "TotalShares" :=
    Int.le_ediv_of_mul_le ht (by omega)
  rw [show BalanceA.read st.pre pool * share st.call
      = -(BalanceA.read st.pre pool * (- share st.call)) by rw [Int.mul_neg, Int.neg_neg],
    Int.neg_tdiv, Int.tdiv_eq_ediv_of_nonneg (by omega)] at hx
  omega

end SorobanAmm.Answers
