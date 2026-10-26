# Aquarius reward-drain — corrected impact (measured live on-chain)

_As of 2026-09-22 · AQUA=$0.00036056 · XLM=$0.2157 · AQUA 24h vol ~$824k (≈2.28B AQUA) · mcap ~$15.9M_

Bug: `WorkingBalance` fresh-init helper returns the user's `shares` as the "old" value instead of `0`,
so a single-step checkpoint sets `WorkingBalance` without raising `WorkingSupply`. Driving `WorkingSupply→0`
(via the LP share-token transfer hook / `claim`, both unprivileged) inflates every reward payout.
`claim` transfers real reward AQUA out (no `require_auth(user)`), near-instant after a no-wait setup.

## All THREE Aquarius pool implementations share the bug (decompiled + verified)

Same fresh-init bug (byte-identical logic) AND the same `#2019 InsufficientBalance` guard in `claim`:

| wasm | pools | AQUA balance | **reward buffer (drainable)** | buffer USD |
|---|--:|--:|--:|--:|
| `ae0da5a8` (constant-product) | 17 | 3,505.8M | 307.4M | $110,834 |
| `12fca5a7` | 14 | 771.4M | 92.2M | $33,231 |
| `f1077e0b` | 7 | 58.2M | 58.2M | $20,971 |
| **ALL reward pools** | **38** | 4,335.4M | **457.7M AQUA** | **≈ $165,037** |

## What is / isn't at risk (this is the key correction)

- **Directly & near-instantly drainable: the reward BUFFERS = ~458M AQUA ≈ $165k.** These are accrued
  emissions owed to honest LPs. Proven end-to-end on real bytecode (drive WS→0, one ledger, `claim`).
- **Swap principal is PROTECTED.** `claim` has a `#2019 InsufficientBalance` guard: it refuses any reward
  payout that would drop the reward-token balance below the tracked swap reserve
  (`reward_payout + swap_reserve ≤ balance`; f85=balance, f87=reserves — verified statically AND empirically:
  draining 89.9M passed, 625M reverted, boundary exactly balance−reserve). The buffer is also invariant
  under swaps (tested: a USDC→AQUA swap left the buffer unchanged) and under deposit/withdraw. So an attacker
  cannot enlarge the buffer or reach the ~$9.6M of swap principal directly.
- **Ongoing:** with WorkingSupply pinned ~0, the attacker captures ~all FUTURE emissions across all 38 pools
  until the bug is fixed — this compounds the $165k over time.
- **Realizable cash-out:** selling ~458M AQUA (≈20% of a day's AQUA volume) nets ≈ its market value minus
  modest slippage (tested: dumping AQUA extracts ~90% of a pool's paired reserve at the CP asymptote).

## Correction history (do not repeat in the report)
- First stated ~$1.26M — WRONG: it counted the full AQUA balances, including swap reserves the `#2019`
  guard protects. Corrected drainable = reward buffers only.
- The `$9.6M` swap principal in these pools is NOT directly drainable (guard holds).

## Severity
Unprivileged, near-instant drain of **all accrued LP rewards (~$165k)** across 38 live pools + ongoing
emission theft until fixed. Stoppable only by `kill_claim`/emergency mode (reactive; setup is detectable via
`working_supply` collapsing below `get_total_shares`) or the fix (fresh-init must return `old_wb = 0`).

Raw per-pool data: `aqua-enum-raw.json`. Decompiled sources: `cj_aqua.rust.rs` (ae0da5a8),
`aqua-12fca5a7.rust.rs`, `aqua-f1077e0b.rust.rs`. PoC (all tests pass on real bytecode): `aqua-poc/`.
