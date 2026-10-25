# Aquarius AMM — WorkingSupply under-counting → reward-reserve over-distribution

> ## ⛔ RETRACTED / NOT EXPLOITABLE (2026-09-23)
> **This finding does not hold against the real deployed contracts.** The `f156` fresh-init returning `shares` (instead of 0) is a **real latent bug** — a *lone, single-sided* `checkpoint_working_balance` on a fresh account at nonzero balance under-increments `WorkingSupply` by exactly `shares` (proven on real bytecode: `aqua-poc::isolate_lone_checkpoint_vs_paired_transfer`, WS rose by `f204(X)−X` not `f204(X)`). **But that lone path is not reachable on-chain**, so there is no over-distribution and no loss of funds.
>
> Why unreachable:
> 1. `checkpoint_working_balance` requires `require_auth(token_contract)` — only the LP share token can call it.
> 2. The share token calls it in **only** `transfer`/`transfer_from`, always **paired** (both `from` and `to`), and it runs `checkpoint_reward(to)` **before** crediting the receiver (share token `transfer` lines 1200 vs 1208) — so the receiver is effectively checkpointed at **balance 0 first** → the working-balance checkpoint sees `old_wb = 0` → **no undercount**. `mint`/`burn` don't checkpoint; `deposit` is explicitly two-step.
> 3. Net: every real checkpoint is preceded by a balance-0 checkpoint, so the fresh-init-at-nonzero bug never fires. `WorkingSupply == Σ WorkingBalance` is preserved (`aqua-poc::real_token_invariant_and_no_overdistribution`: sum_WB == WS, total == funded) and cycling via real transfers does **not** collapse WS (`aqua-poc::flash_cycle_withdraw_crossledger_real_hook`).
>
> **Root cause of the false positive:** all earlier "exploit" PoCs used a **mock LP token with no transfer hook**, letting a fresh account hold shares while never being checkpointed — an unreachable state that manufactured the lone/unpaired checkpoint the bug needs.
>
> **Consequence:** **All monetary-impact figures below (buffers, $111k–$165k, flash-loan economics, timing/viability) are INVALID** and retained only for provenance. No loss of funds. Report at most as an informational/defense-in-depth note (fix `f156` to return 0 anyway), **not** as a vulnerability.

**Severity:** ~~High~~ → **None (not exploitable on-chain; false positive from a mock LP token without the real transfer hook)**
**Target:** Aquarius liquidity-pool contract, wasm `ae0da5a84b15805c5c7931ac567a8d1b34be3f26b483993d9ff80cb2c3de9852` (~$15.6M TVL across 23 live pool instances, e.g. `CA6PUJLBYKZKUEKLZJMKBZLEKP2OTHANDEOWSFF44FTSYLKQPIICCJBE`).
**Method:** Recovered by decompiling the on-chain wasm with stellar-diver (wasm → LLVM IR → Rust) and reading the reward-accounting helpers; every claim below is verified against the decompiled source (line refs into `cj_aqua.rust.rs`).

## Root cause

The gauge-style reward system tracks a per-user `WorkingBalance[user]` and a global running `WorkingSupply` (instance key, discriminant → `Vec[Symbol("WorkingSupply")]`, numeric key `1050248`). Reward rate per unit is
`inv = 1e22 * generated / WorkingSupply` and a user's reward is `reward = WorkingBalance * Σinv / 1e22`.
Correctness depends on the invariant **WorkingSupply == Σ WorkingBalance**.

`f156` (get-or-init WorkingBalance, lines 12637–12735) — for a user with **no** stored WorkingBalance entry, the fresh-init branch (12721–12731) stores `WorkingBalance[user] = shares` **and returns `shares` as the old value**:
```
_ => { // WorkingBalance[user] absent
    f296(fp64, a2, a3, Persistent);           // store WorkingBalance[user] = u128(a3,a2) = current balance
    (*(a0+8)) = a3; (*(a0)) = a2;             // RETURN old_wb = current balance   <-- should be 0
}
```

`f197` (update WorkingBalance + WorkingSupply, lines 14516–14589) uses that return as `old_wb`:
```
f156(fp, user, shares) -> old_wb            // = shares for a fresh user (bug)
f150(fp, ...)          -> WS_old            // running WorkingSupply (key 1050248)
f204(...)              -> new_wb
WS_new = WS_old + new_wb - old_wb           // lines 14555-14571
f296(1050248, WS_new, Instance)             // store running WorkingSupply
f296(WorkingBalance[user], new_wb, Persistent)
```
For a user whose **first checkpoint happens at a non-zero balance**, the correct delta is `new_wb - 0`; the code computes `new_wb - shares`, so **WorkingSupply is under-added by exactly the user's `shares`**, while `WorkingBalance[user] = new_wb` still earns rewards.

The reward path uses this running (under-counted) WorkingSupply as the divisor:
- `f273` (inv creation, 15305–15385): `inv = u256(1e22) * generated / WorkingSupply`, denominator = the value read by `f150` from key `1050248` (caller line 6790 reads it into `ld70/ld72`; line 6823 passes `ld70,ld72` as the divisor).
- `f159` (per-user accrual, 13319–13323): `reward = Σinv * WorkingBalance / 1e22`.
- `claim` pays it out in **real reward tokens**: `f122(reward_token, from=contract, to=user, amount)` (line 1222).

Because `Σ WorkingBalance > WorkingSupply` after any shares reach a first-checkpointed-at-nonzero account, `Σ(WorkingBalance_i * inv) > generated`, i.e. the pool distributes **more reward tokens than were funded** — the excess is drained from the reward reserve.

## Why deposit is safe but the bug is reachable

`deposit` is a two-step checkpoint: it checkpoints with the **pre-mint** balance (0) first, establishing `WorkingBalance=0`, then re-checkpoints at the real balance with `old_wb=0` — correct. Every **single-step** checkpoint at a non-zero balance for a user with no prior entry hits the buggy branch. Reachable, unprivileged paths:
- `claim(user)` has **no `require_auth`** (lines 1167–1169 only check the arg is an Address) and reads the user's **real** LP balance via cross-contract `balance()` (`f85`, line 1180) — so anyone can force any holder's first checkpoint at their current balance.
- Any share transfer to a fresh account (standard SEP-41 share token) results in that account being first-checkpointed at a non-zero balance (via the transfer hook or a later `claim`/`withdraw`).

## Exploit (unprivileged, no admin/privileged role)

1. Attacker deposits `X` LP into account `A0` (correct: `WorkingBalance[A0]=X`, `WorkingSupply += X`).
2. Attacker transfers the `X` shares `A0 → A1` (a fresh account they control).
3. Attacker calls `claim(A1)` (or the transfer already checkpointed `A1`). `A1` is first-checkpointed at balance `X`: `f156` fresh-init returns `old_wb=X`, `f197` computes `ΔWS = new_wb - X ≈ 0`, so `WorkingBalance[A1]=X` but `WorkingSupply` is **not** increased.
4. Now `Σ WorkingBalance ≥ 2X` while `WorkingSupply ≈ X`. `inv` is inflated ~2×; `A1` earns ~2× its fair reward share. Repeating with additional fresh accounts (or cycling the stake) drives `WorkingSupply` arbitrarily low relative to `Σ WorkingBalance`, inflating `inv` toward the point where the attacker claims the **entire** reward emission each period — draining the reward reserve at the expense of honest LPs and the protocol's funded emissions.

## Impact

Unprivileged, unconditional (normal operation; not init- or admin-gated) drain of the reward/emissions reserve (real reward tokens) on all live pool instances sharing this wasm. Does not touch swap-liquidity principal, but the emissions reserve is real, funded value owed to LPs.

## Fix

In `f156`, the fresh-init branch must return `old_wb = 0` (the user contributed nothing to WorkingSupply yet), not the current share balance — while still initializing the stored WorkingBalance as appropriate. Equivalently, ensure `WorkingSupply` is credited `new_wb` (delta from 0) on a user's first checkpoint. Add an invariant assertion `WorkingSupply == Σ WorkingBalance` in tests, and checkpoint share transfers with the same two-step semantics as deposit.

## Local PoC — executed against the REAL mainnet bytecode (no network)

`reconstructed/aqua-poc/` runs the actual deployed contract `ae0da5a8.wasm` in a local Soroban VM (soroban-sdk 25.3.0 test env), with a minimal mock LP/share token (deployed by the pool itself from an uploaded wasm hash), a mock pools-plane, and a mock veAQUA boost token/feed. `cargo test -- --nocapture` runs two scenarios:

- **CONTROL** (both users use the correct two-step checkpoint): honest=50,000 second=50,000 → **total 100,000 == funded**. No over-distribution.
- **EXPLOIT** (second user single-step-checkpointed on a fresh account, i.e. the transfer/claim path): honest=100,000 attacker=100,000 → **total 200,000 = 200% of the 100,000 funded**. The attacker walks away with 100,000 **unfunded** reward tokens.

The two scenarios are identical except for the one checkpoint pattern, so the over-distribution is isolated to the `f156` fresh-init behaviour on the real bytecode — not to the harness. This confirms end-to-end (a) the WorkingSupply under-count, (b) that `get_user_reward` on the real contract pays each user against the undercounted supply, and (c) the monetary effect: total paid = `(Σ working_balance / WorkingSupply) × emissions`, which exceeds funded emissions whenever any shares reach an account that is first-checkpointed single-step.

## Monetary impact (corrected 2026-09-22 — measured live on-chain)

The hard cap per pool is that pool's **actual on-chain balance of the AQUA reward token** (SAC `CAUIKL3IY…`), read live via `balance(pool)`. For the flagship XLM/USDC pool `CA6PUJLB…` this is exactly **91,405,936.29 AQUA**, equal to `configured − claimed` (fully funded, physically present, and *separate* from the XLM/USDC swap reserves — the bug drains the reward reserve, not swap principal).

Enumerating every reward-bearing pool via the Aquarius router (`get_tokens_for_reward` → `get_pools`) and classifying each by wasm hash (`stellar contract fetch` + sha256):

| wasm | pools | AQUA reserve | USD @ $0.00036056 |
|---|---|---|---|
| **`ae0da5a8…` (this decompiled contract — CONFIRMED)** | **17** | **3,505,820,840 AQUA** | **≈ $1,264,059** |
| `12fca5a7…` (other Aquarius impl, not yet decompiled) | — | 771,396,562 AQUA | ≈ $278,135 |
| `f1077e0b…` (other Aquarius impl, not yet decompiled) | — | 58,162,922 AQUA | ≈ $20,971 |
| **all reward pools** | 38 | 4,335,380,325 AQUA | ≈ $1,563,165 |

- **Confirmed at risk (this wasm, 17 pools): ≈ 3.51B AQUA ≈ $1.26M.** Largest single pool `CCY2PXGM…` = 2.44B AQUA ≈ $879k.
- The other two implementations share the protocol and almost certainly the reward module; if they share this bug, total exposure ≈ **$1.56M**. Not yet verified (needs their wasm decompiled).
- The original finding's "$36k / low-six-figures" figure looked at a single pool and **under-counted by ~35×**.

Per emission period the over-distribution multiplier = `Σ WorkingBalance / WorkingSupply`; a single unprivileged `claim` on a fresh account creates an imbalance without raising `WorkingSupply`, and additional fresh accounts raise the multiplier linearly (PoC: n=1,4,16,64 → 2×,5×,17×,65× — real reward-token transfers on `ae0da5a8.wasm`). The cumulative drain is capped by the reserve figures above.

**Realizability:** these are notional reward-token amounts (LP/protocol loss), real regardless of cash-out. AQUA daily volume ≈ 2.28B AQUA (~$824k), mcap ~$15.9M; the confirmed reserve is ~1.5× a day's AQUA volume, so it is realizable over days-to-weeks with slippage, not in a single trade. Exact per-pool amounts: `reconstructed/aquarius-impact-amounts.{md,json}`.

## Confidence / caveats

The WorkingSupply-under-count arithmetic and the inv/reward chain are verified in the decompiled code (refs above) AND executed against the real mainnet bytecode (PoC above). One real-world reachability note remains: getting shares into a first-checkpointed-single-step account is a standard SEP-41 LP transfer followed by `claim`/`checkpoint` — the `claim` path is in this contract; the share-token `transfer` hook is a separate contract not modelled here, but `claim(freshAccount)` alone triggers the buggy branch, which the PoC exercises directly.

## Is it an instant drain? Severity & stop criteria (2026-09-22)

**Answer: not a single-transaction atomic drain, but a near-instant one** — after a no-wait setup phase, ~1 ledger (~5 s) of elapsed time lets one `claim` take 100% of a pool's reward reserve.

Why it can't be atomic: payout = `WorkingBalance × (acc_now − acc_last)/SCALE`, and `acc` grows only with real time (`acc += SCALE·tps·dt/WorkingSupply`). Within one ledger `dt = 0`, so a claim in the same ledger as setup pays 0 (PoC: `same-ledger pending = 0`).

Why it is effectively instant anyway — the drain rate is `∝ 1/WorkingSupply`, and WorkingSupply can be driven arbitrarily low with **no waiting**:
- The LP **share token's `transfer` is a checkpoint hook** (CONFIRMED by decompiling the share token `CAVKLYY4…`: `transfer`/`transfer_from` call the pool's `checkpoint_working_balance` for *both* `from` and `to` — `f95` = cross-contract call, symbols `checkpoint_working_balance`/`checkpoint_reward`). So permissionless SEP-41 transfers checkpoint the sender at its reduced balance and the receiver fresh.
- Cycling a chunk of shares through fresh accounts therefore **decrements WorkingSupply on every transfer** (sender-side `WS −= old_wb`) while the receiver-side bug adds nothing — driving `WorkingSupply → ~0` (floored only by f197's underflow trap, i.e. ~one step size).
- PoC on real bytecode (`instant_drain_probe_lowering_working_supply`): 199 leap-frog steps drove `WorkingSupply` from 1e12 → 5e9 (all no-wait setup txs); then **dt = 5 s → one `claim` drained 100% of the reserve**, pool reward balance left = 0. `time_to_drain_full_reserve = reserve × WS / (WB × tps)` → ~5 s at that WS, and lower WS shortens it to a single ledger.

So the realistic attack is: (1) hold some LP shares; (2) cycle them through fresh accounts via ordinary transfers (drives WorkingSupply toward 0 — seconds-to-minutes of back-to-back txs, no privileged calls); (3) wait ~1 ledger; (4) `claim(attacker)` → drains the pool's entire reward reserve. Fully unprivileged.

**What bounds / stops it:**
- **Permanent fix:** f156 must return `old_wb = 0` for a fresh user (see Fix). Removes the imbalance at the source.
- **Emergency containment (reactive):** `kill_claim(admin)` — CONFIRMED that `claim` gates on this flag (`f63(9) & 1`, same flag as `get_is_killed_claim`); when set, `claim` refuses to pay. `set_emergency_mode` is a second lever. Must be applied per pool (or via router) — 17 confirmed pools.
- **Detectability:** the setup is loud and on-chain observable — `WorkingSupply` collapses far below `Σ WorkingBalance` / `get_total_shares`, driven by mass transfer-cycling through fresh accounts. Monitoring `get_rewards_info().working_supply` vs `get_total_shares()` flags it before the final claim.
- **What does NOT stop it:** f197's underflow trap (only floors WS at ~one step size, still near-zero); require_auth on `checkpoint_working_balance` (satisfied by the share token on every transfer); require_auth on `claim` (there is none).

**Rating: Critical.** Unprivileged, full reward-reserve drain (~$1.26M confirmed across 17 pools), near-instant after a permissionless setup, containable only by an admin pause or the fix.

## Independent validation (2026-09-22)

Re-decompiled `ae0da5a8.wasm` fresh (`cj_aqua.rust.rs`, 17,497 lines) and re-checked every link:

1. **f156 fresh-init bug — CONFIRMED** (`cj_aqua.rust.rs:12721-12731`): for a user with no `WorkingBalance` entry, stores `WorkingBalance = shares` and *returns `shares` as the old value* (should be 0).
2. **f197 arithmetic — CONFIRMED** (`14547-14577`): `WorkingSupply = WS_old + new_wb − old_wb`, and writes `WorkingBalance = new_wb`. With `old_wb = shares` and `new_wb ≈ shares`, WS stays flat while WB is set → persistent imbalance.
3. **Call chain — CORRECTED & CONFIRMED**: the WS write is reached as `claim`/`checkpoint_working_balance` → **f159** (`13055`) → **f197** → f156 (the original note attributed it directly to f197; the intermediary is f159). f150 is get-or-init and only *reads* WS for an established pool, so claim/checkpoint never legitimately re-adds the missing supply.
4. **Unprivileged reachability — CONFIRMED**: `claim(user)` (`1066`) has **no `require_auth(user)`** — line `1168` only checks the arg is an `AddressObject` — reads the victim's *real* LP balance via cross-contract `balance()` (`f85`, `1180`), then checkpoints single-step. `checkpoint_working_balance` (`9384`) requires `require_auth(token_contract)` (`9426`), which the LP share-token itself satisfies on a normal transfer (the transfer-hook path). Both routes are unprivileged.
5. **Extraction is real — CONFIRMED**: `claim` transfers reward tokens out of the pool to the caller-chosen account: `f122(reward_token, from = current_contract, to = user, amount)` (`1222`). No owner auth, so `claim(attacker_acct)` pays the inflated amount to the attacker.
6. **PoC on real bytecode — 4/4 pass** (`reconstructed/aqua-poc`, soroban-sdk test VM):
   - `claim_alone_creates_the_imbalance`: one `claim()` on a fresh account → WorkingSupply delta = 0 while its WorkingBalance = 10¹³ (self-contained, no hook, no auth).
   - `exploit_scales_and_transfers_real_tokens`: n fresh accounts → real reward-token take = n × a period's emissions (2×/5×/17×/65× for n=1/4/16/64), `ΣWB/WS = n+1`.
   - `control_*` / `exploit_working_supply_undercount`: two-step = no over-distribution; single-step = 200%.
7. **Monetary impact — measured live** (see corrected table above; raw data `aquarius-impact-amounts.json`): confirmed reserve at risk **≈ 3.51B AQUA ≈ $1.26M** across 17 pools on this wasm.

Residual unknowns (do not affect the confirmed loss): (a) the share-token transfer-hook's sender-side behaviour, which only changes how *cheaply* the multiplier can be pushed past 2× (capital-free cycling vs. capital-proportional); (b) whether the two other Aquarius reward-pool wasms (`12fca5a7…`, `f1077e0b…`, +$0.30M) share the bug — not yet decompiled.
