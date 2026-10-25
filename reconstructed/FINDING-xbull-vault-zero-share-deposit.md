# xBull Blend-vault — `deposit` rounding to 0 shares silently burns user funds (LOW)

**Contract:** xBull Blend-vault (ERC-4626-style), wasm hash `0fb61144`, mainnet e.g. `CAPPWPX7Q3TNMXUS6SWGWXPHIAUIU4WQVGFI2R75UDRWYMDOEUJEDBGN`.
**Severity:** LOW (user-fund-loss under normal operation; not attacker-profitable).
**Status:** confirmed on the real deployed bytecode (`reconstructed/xbull-poc/`, test `first_deposit_inflation_is_griefing_not_theft`).

## Summary
`deposit(assets, receiver, from, operator)` converts `assets → shares` with a muldiv (helper `f58`, 1e7 virtual scale). When the result floors to **0 shares**, the contract still pulls `assets` from the depositor and mints nothing — the deposit does **not revert**. The depositor loses the assets; their value accrues to existing shareholders. The `VaultInvalidSharesAmount = 404` error exists in the ABI but is not enforced on the deposit path.

## Proof (real bytecode, soroban-sdk 25.3.0 test VM)
Setup: real vault wasm via `contractimport!`, SAC underlying + SAC share token, `min_deposit = 1`, empty `targets`.
1. Attacker `deposit(1)` → 1 share.
2. Attacker `transfer(1e9)` directly to the vault → `total_assets` = 1_000_000_001 (idle balance is counted), share price now ~1e9/share.
3. **Victim `deposit(1_000_000)` → 0 shares, NO revert → victim loses 1_000_000.**

## Why it is NOT attacker-profitable (not a theft primitive)
`redeem`/`withdraw` pay out only from **strategy** withdrawals; the vault's idle token balance is never paid out. So the value the attacker donated (and the victim's lost deposit, while idle) is **permanently unextractable** by the attacker — the attacker spends 1e9 to cause a 1e6 loss (griefing at a net loss), and cannot recover it (`recover()` is admin-only, sweeps to admin). The extractable portion (strategy funds) cannot be inflated without minting shares, so there is no profit path. Confirmed: attacker PnL = −1_000_000_001.

## Reachability
- The **inflation precondition** (empty/fresh vault, attacker is first depositor) does not apply to a live vault with existing TVL.
- The **generally-reachable** issue is the 0-share-no-revert itself: any depositor whose amount is small relative to a legitimately high share price silently loses funds. Under the 1e7 virtual scale this requires a very high share price, so it is uncommon in normal operation → LOW severity.

## Secondary defect (informational)
`max_withdraw` / `total_assets` count the vault's idle balance, but `withdraw`/`redeem` can only pay from strategy withdrawals → the view over-reports the actually-withdrawable amount (settlement inconsistency).

## Recommendation
- In `deposit` (and `mint`), revert with `VaultInvalidSharesAmount` (404) when the computed shares are 0 (enforce the existing guard on this path).
- Reconcile `total_assets`/`max_withdraw` with what `withdraw`/`redeem` can actually settle (either make idle balance withdrawable, or exclude it from the withdrawable view).

## Caveat
Tested with empty `targets` (no Blend strategy mock; Blend's positions interface is heavy). The idle-donation path is conclusively unprofitable regardless of targets. A strategy mock would only further close the (already-blocked) theft path; it does not affect defect #1.
