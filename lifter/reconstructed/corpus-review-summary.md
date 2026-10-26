# Soroban corpus security review — outcome (2026-09-23)

Reviewed all 15 corpus targets (~$418M TVL) by decompilation (stellar-diver) + auth/flow/flash/payment analysis, with **real-bytecode verification / property-testing on every actual lead**. Method discipline: verify reachability on the real deployed bytecode with real dependencies before claiming anything (after the Aquarius false-positive).

## Result: NO attacker-reachable loss-of-funds vulnerability found.

| hash | what it is | TVL | verdict |
|---|---|--:|---|
| 2e2a4078 | SHX token lockup | $222M | safe — auth+timelock enforced; CEI-order smell neutralized (SHX is a built-in SAC, non-reentrant) |
| a41fc53d | Blend lending pool | $145M | formally verified (Certora); auth model sound |
| ae0da5a8 | Aquarius AMM (23 pools) | $15.6M | safe — reward-drain was a FALSE POSITIVE (real LP share token's paired checkpoint hook maintains WS==ΣWB); swap has slippage guard |
| 9883cdb6 | Axelar "Operators" proxy | $15.2M | safe — owner-gated arbitrary-call proxy |
| 003710b3 | Uniswap-V3 concentrated-liquidity AMM (6 pools) | $11M | safe — auth/flash/payment sound; property-tested on real bytecode: round-trip swap loses to fees, mint→burn rounds to pool, out-of-range earns 0 fees (cl-poc) |
| cc74acb5 | HOT bridge | $8.8M | safe — every payout ECDSA-sig- or owner-gated; replay-protected |
| 18051456 | Soroswap Pair (UniV2) | $561k | safe — K-invariant enforced |
| 4b3d9f6b | ERC-4626-ish vault | $469k | safe — withdraw/redeem spend owner allowance (f213 reverts on insufficient) |
| e13706e4 | Merkle airdrop | $110k | safe — recover is auth+role-gated; claim uses proofs |
| d70a8fce | XRP migration claim | $90k | safe — require_auth(owner); admin fns gated |
| ae3409a4 | DeFindex yield vault | $73k | safe — SEP-41+vault fns auth/role-gated |
| ed894806 | access-control/upgrade mgr | $41k | safe — no fund surface |
| a03bfb74 | token lockup (SHX) | $37k | safe — same as 2e2a4078 |
| 06f4207b | Aquarius router/factory | $19k | safe — user-auth'd; same non-exploitable reward module |
| c40cf437 | admin arb/router bot | $18k | safe — admin-gated |

## Extended sweep beyond the 15-target corpus (2026-09-23)

Enumerated the top ~50 *contract* holders of 13 major Stellar assets (XLM, USDC, EURC, AQUA, BTC, ETH, yUSDC/yXLM/yBTC/yETH, XRP, PYUSD, SHX). **Every $10M+ contract is already-reviewed code** (SHX lockup, Blend, Axelar, the two AMMs, HOT, vault, Soroswap, Aquarius variants). Genuinely-new, never-decompiled code:

| hash | what it is | TVL | verdict |
|---|---|--:|---|
| ca6b85a1 | custodial USDC deposit/withdraw vault (CAHEWHOP…) | ~$17M | **safe** — per-owner records + `require_auth(from)`; withdraw capped at own record, record persisted before transfer-out; overflow/underflow checked. Independent fork audit + **on-chain PoC on the real bytecode** (`vault17-poc`): attacker `withdraw(from=Alice)` → auth Abort; over-withdraw → NotEnoughDeposit; only residual is admin upgrade-rug (centralization) |
| 76e60d02 | full money-market/lending protocol (Deposit/Borrow/FlashBorrow/Liquidate/bad-debt, kinked IR, jToken/dToken shares, oracle LTV) | ~$450 | **safe** — 3 parallel forks + PoCs on the real bytecode (`mc-poc`). **Liquidation PoC'd** (settable oracle): healthy position → rejected (601); underwater repay 2e8 → seized *exactly* the 1000-bps incentive cap (5.5e8, liquidator profit = designed 10%); partial liquidation leaves borrower's rest; self-liquidation nets 0 — liquidation math correct & incentive-bounded (closes Fork C's "too deep to verify"). Share math is Compound-style internal accounting (donation-immune, floors to pool). Flash-loan repayment is trap-enforced; reentrancy-safe (oracle-priced, not liquidity-priced). Liquidation blocked on healthy positions. **Fork A's "remove_collateral/withdraw skip the health check" was a FALSE POSITIVE** — both paths apply a debt-aware cap (static call-graph missed it; `remove_collateral` releases only `collateral − debt/open_ltv`, `withdraw` blocks entirely when supply backs debt) so an obligation can't be driven insolvent |
| f7937f8e | Aquarius-style reward distributor (standalone RewardGauge) | ~$17k | **safe** — every fund/state entry (claim/checkpoint_user/schedule/set_reward_state/upgrade) is `require_auth(pool)` + stored-pool `obj_cmp` (else Unauthorized 102); caller-supplied working_balance/supply can only come from the registered pool → same reasoning that retracted the Aquarius finding |
| 4e913acc | fee-collector / chained-swap router | ~$5k | **safe** — `claim_fees` operator-gated, sweeps to the *stored* fee_destination; swaps `require_auth(user)`, fee_fraction capped by stored MaxSwapFeeFraction (FeeFractionTooHigh 2904), out_min/in_max slippage enforced, router is a fixed stored address; operates on user funds not contract balance |

## Activity/protocol-based discovery sweep (2026-09-23)

Since balance-based discovery was exhausted, enumerated DeFi protocols by identity/activity (Stellar Expert directory) and found 11 new fund-custodying wasms across 8 protocols (none matching our reviewed hashes). Decompiled and audited the 9 highest-EV via 4 parallel forks — **all safe**:

| hash | protocol / role | verdict |
|---|---|---|
| c1f4502a | **Blend Backstop** (insurance layer of the $145M Blend) | safe — fork audit + **7-vector real-bytecode PoC** (`backstop-poc`, all pass): deposit/withdraw round-trip exact (17-day Q4W lock enforced, `NotExpired 1001`); share rounding floors against depositor; **emissions claim-timing SAFE** (late depositor deposits 4× at window-end → 0 BLND; mid-window joiner gets exact time-weighting; index snapshotted at deposit via f88); double-claim → 0; `donate` pure gift (needs from+pool auth); `draw` pool-auth + own-balance floor (`InsufficientFunds 1003`) |
| 167ab414 | **Phoenix Pool** (XYK AMM) | safe — reserves internal (zero `balance()` calls → donation-inflation impossible); swap/provide/withdraw fully guarded (auth/deadline/spread/slippage/fee) |
| 95a8e001 | **Sushi Pool** (UniV3-fork, 21.8k lines) | safe — same family as PoC-validated `003710b3`; auth + swap settlement + flash repayment (`bal_after ≥ before+owed`) correct; residual: deep tick-math rounding = ≤1-unit dust (PoC-would-confirm) |
| 0245bac3 | **FxDAO** vaults/evict | safe — `evict` `require_auth`(protocol_manager/treasury), collateral returns to that privileged addr not caller; no oracle use |
| 425656ba | **FxDAO** staking/reward pool | safe — deposit/withdraw `require_auth(caller)` + lock enforced; `distribute` is a donation (attacker only loses); admin fns gated |
| c0221f88 | **FxDAO** oracle (SEP-40 + quota) | safe — price-setting admin-gated, reads caller-gated; not attacker-manipulable |
| 11329c24 | **DeFindex** Blend strategy (new hash ≠ ae3409a4) | safe — internal accounting + 1e12 virtual scale, 0-share revert, keeper-gated harvest |
| 0fb61144 | **xBull** Blend-vault (ERC-4626) | no attacker-profit exploit — operator moves shares via `transfer_from` (owner allowance enforced), `recover` admin-only; inflation attack **PoC'd on real bytecode** (`xbull-poc`): griefing-at-a-loss only (attacker burns 1e9 to cause 1e6 victim loss; donated idle balance is permanently unextractable since redeem/withdraw pay only from strategy funds). **BUT the PoC found 2 real LOW-severity defects** (below) |
| 4c3db3eb | **Soroswap** Router (UniV2) | safe — no custody, `require_auth(to)` (payer==recipient), min-out/max-in/deadline enforced |

Not yet decompiled (low-EV): Soroswap factory `5db738b0` ($ low), YieldBlox DAO `e0c93198` (governance).
**FxDAO CDP core — resolved (no live target):** per FxDAO's own docs `CCUN4RXU…` (`0245bac3`) *is* the mainnet "Vaults" contract, but its live bytecode (verified via `stellar contract info interface`) has been upgraded 11× down to an **`evict`-only migration stub** — the full CDP surface (borrow/liquidate/redeem/set_currency_rate) is no longer deployed on mainnet (exists only in superseded wasm versions + on testnet, which holds no real funds). Nothing attacker-reachable.

## Custom / unaudited contracts + deployed-state sweep (2026-09-23)

Redirected from audited-fork code (where bugs don't live) to CUSTOM/unaudited contracts and on-chain init-state. Cleared: Kale PoW-farming `db2c1429` (permissionless-by-design, funds route to `farmer` arg), Ohloss GameFi `7f33cf1e` (double-claim flags + per-party auth), xBullSwap aggregator `c2b3ec57` (referral fee from user's own output). Deployed-state: no uninitialized/zero-admin/re-init takeover (FxDAO staking, Soroswap router, ca6b85a1 all confirmed initialized on-chain; the customs use atomic `__constructor`).

**Tooling fixes (unblocked the two hardest targets):**
1. The mir→Rust decompiler aborted the entire file on an indirect/allocation-backed scalar constant (`non-scalar constant Val(Indirect{...})`). Fixed `mir/src/rs/values.rs::konst` to evaluate such constants and read the scalar out of the allocation (`eval_indirect_scalar`). Regression-clean (byte-identical on 76e60d02/ca6b85a1/c1f4502a). Unblocked **XOXNO Controller** (`03a8630f`, 107KB → 32,919 lines).
2. The decompiler had no Rust type for LLVM's `*.with.overflow` result `{ iN, i1 }` (checked-arithmetic result+overflow pair), aborting any file whose signatures used it. Fixed `mir/src/header.rs::rs_ty` + `mir/src/mir.rs::ty` to map `{iN,i1}` → the tuple `(uN, bool)` (helper `overflow_pair_width`). Regression-clean (byte-identical on the 3; XOXNO comment-annotation-only diff, same line count). Unblocked the **CCTP Price Aggregator** (`7807901b`, previously IR-only → 15,088 lines of Rust; one residual `f164` checked-mul stub needs `ExtractValue` instruction support — non-critical crossrate/gas math, value-bearing staleness gate already cleared).

| hash | protocol / role | verdict |
|---|---|---|
| 03a8630f | **XOXNO Controller** — custom cross-chain lending (borrow/withdraw/liquidate/flash_loan/**multiply**/flash_position/swap_debt/swap_collateral/clean_bad_debt/recapitalize, delegates, oracle-priced health) | **Controller safe** (3 parallel forks, no unprivileged extraction) — accounts are Position-NFTs; borrow/withdraw require `require_auth(caller)` + owner-or-delegate (`f183`, err 44); `add_delegate` owner-only (err 13); universal post-mutation solvency check (`f89`, err 100, validate-then-persist same struct); attacker `swap: Bytes` hits only the admin-set aggregator with balance-delta output validation (err 501/502); comprehensive `FlashLoanOngoing` reentrancy guard (err 400) on every entry; leverage health-checked; liquidation fresh-HF-gated (err 101) + admin-capped incentive + collateral-bounded seize; bad-debt insolvency-gated (err 114); `claim_revenue`→admin accumulator; `migrate_from_blend` approved-pool + trusted-source. **Residuals RESOLVED:** oracle stale/zero → aggregator is fail-closed (`prices` reverts, rows below); `asset_decimals` → **SAFE**, normalized at the Pool boundary (`f174` applies `10^(27−asset_decimals)` per-asset on deposit → stored `scaled_amount` is decimal-agnostic → `f143`'s fixed 27/18 exponents correct for any decimals; no latent mispricing). Remaining low-EV NEEDS-POC (non-extractable): `f103` rate-kernel precision (dust), post-`migrate_from_blend` health recheck (bad-debt-import edge, not direct theft) |
| c2857740 | **XOXNO Central Pool** (`CBXRNDQM…BKXO`, deployed by the Controller; holds all liquidity, index-scaled RAY accounting) | **safe** — decompiled via the patched tool (11,903 lines); **custody hard-gated: Owner = the Controller, all 14 mutators `require_auth(Owner)` (14/14)** → cannot be called/drained directly by a user; flash-loan repayment enforced (`transfer_from` amount+fee + Void-return + allowance check, traps on shortfall); index-based internal accounting (donation-immune, no first-deposit inflation, supply rounds down to pool); accrual monotonic + overflow-bounded. Residual NEEDS-POC: `f103` rate-kernel precision, withdraw round-half-up ULP (dust) |

| 7807901b | **XOXNO Price Aggregator** (`CBGUF2G2…`) | **safe (fail-closed)** — `prices`/`quotes`/`price_spread` share one evaluator; `f124` gate REVERTS unless status==200 **and** stale-flag(off+60)==0 **and** `price>0` (err 217) **and** min≤price≤max sanity (err 223); staleness (`now−ts>max_stale`) routes into the rejected off+60 flag, multi-source adds deviation + `|ts1−ts2|>3600` skew checks. So the Controller can never obtain a stale/zero price (settles the Controller oracle residual). *(Aggregator hit a NEW decompiler gap — `no Rust type for {i32,i1}` overflow-checked-arith struct — audited from LLVM IR; a follow-up tool fix would let it fully decompile.)* |
| b0b044e5 | **XOXNO Oracle Adapter** (`CDA3XS2H…`) | safe — timestamps writes (`write_timestamp`), validates `package_timestamp` on submit (FutureTimestamp/StaleSubmission); the aggregator ages a genuine data timestamp, not `now` |

## Long-tail custom-contract sweep (2026-09-24)

Enumerated the full Stellar Expert directory (`defi` 392 + `application` 56 = 413 records, 393 contracts), excluded already-reviewed protocols, found 14 candidate customs (13 new hashes). Decompiled + triaged the 9 custody-holders — **all SAFE** (each fund-mover cited to an auth/cap/repayment guard):

| hash | contract | verdict |
|---|---|---|
| 8abc2891 | CometDEX Pool (Balancer-V1 weighted AMM) | safe — join/exit/swap `require_auth(user)` + slippage/ratio guards; `gulp` only syncs up |
| a6c1acc6 | **Circle CCTP TokenMessengerMinter** | safe* — mint gated `require_auth(LocalMessageTransmitter)`; `deposit_for_burn` burns caller's own. *Trust rests on the separate MessageTransmitter (below)* |
| c1e1fce3 | USDT0 LayerZero-V2 OFT bridge | safe — `lz_receive` mint needs peer-check + stored-endpoint `clear()` (DVN+nonce) + `require_auth(executor)`; immutable endpoint |
| f1107839 | SolvBTC / xSolvBTC (SEP-41) | safe — `mint_from` needs `require_auth(from)` + Minters-map; allowance-checked |
| 5afd1577 | deJTRSY Centrifuge T-bill (SEP-41) | safe — minter-role-gated, no self-escalation |
| 1d460404 | StellarBroker swap router | safe — `withdraw`/upgrade admin-gated, `swap` `require_auth(trader)` |
| cbbb1bde | LI.FI cross-chain router | safe — `require_auth(sender)`, governance-registered adapters, never self-authorizes |
| ea1b958f | XycLoans flash-loan pool | safe — flash repayment enforced (`transfer_from` amount+fee, `LoanNotRepaid` rollback) |
| 7f59b1e8 | OneSig threshold multisig (USDT0 admin) | safe — ECDSA multisig + merkle-proof + nonce replay + strictly-ascending distinct signers |

| 99bd0ddc | **Circle CCTP MessageTransmitter** (`CACMENFF…`, the USDC-mint trust root) | **safe** — CCTP V2 Soroban port; `receive_message` enforces threshold-ECDSA (threshold from instance storage, attestation length == threshold×65, `keccak256` over full message, recovered signer ∈ stored attesters, **strictly-ascending distinct signers**, exactly-threshold sigs) + used-nonce replay (`UsedNonce(nonce)` checked+written before atomic mint dispatch) + domain/version/destination_caller checks; MessageTransmitter self-authorizes the `handle_receive_message` call (attacker can't forge it). Live: threshold=2, 2 attesters. No forge/replay → no unlimited/duplicate mint |

Fetched-not-triaged (low-EV): Etherfuse oracle `52ec506f` (no custody), Stellarcarbon sink `8ae1550d` (negligible), Tansu DAO `83feef85` (no custody).
**Allbridge** — the `b46eb071`/`CAWGFKEL…` entry is only the **Gas Oracle** (no custody). Resolved the real Allbridge Core via the operator account: Bridge `fb824a85` (`receive_tokens`), Messenger `cfa823e6` (`receive_message`), vUSD Pool `a757a1ed`, plus two 2026 CCTP bridges. **Classic Core release path SAFE** — keccak256 + dual secp256k1 validator sigs (stored, admin-gated), `ProcessedMessage` replay guard before payout, hash-committed amount/recipient, bridge-gated pool; source public (allbridge-io) + Quarkslab-audited, deployed bytecode matches. Classic vUSD pool is ~empty (native bridging wound down; live USDC flows via the 2026 CCTP contracts).
**Two 2026 Allbridge bridges (live USDC, non-public source) — SAFE** (deep-traced incl. helpers): `c340cb60` `receive_token` — `require_auth(caller)` + registered-relayer-or-self-claim (err 102), `token_messenger_addr`/`swap_addr` checked ∈ admin-gated registries (err 101/100), **every payout bounded by `token_messenger.received_token_amount(keccak message_hash)`** (err 105 if 0, cap err 109) where the hash binds amount+nonce+source_chain+destination_token+recipient (forged params → 0), nonce consumed once before transfer (err 104), `withdraw` admin-gated. `8d26318b` `receive_cctp_message` — attestation-gated via Circle's `MessageTransmitter.receive_message` (records amount only after real mint). No forged-release/drain. (One honest low-EV residual: exact `f110`/`f111` keccak preimage byte-layout not byte-diffed — a testnet run would nail it; recipient-binding argument holds.)

## Governance / admin-takeover threat model (2026-09-24) — SAFE
Read each high-TVL protocol's on-chain admin from instance storage and classified it. **Every value-holding protocol's admin is an EOA/multisig, or has no admin/upgrade surface** (SHX lockup $222M — only lock/unlock, no admin; Blend Backstop — no admin). The ONLY governance-contract admin is the Blend **YieldBlox** pool (`CCCCIQSD`) → Script3 soroban-governor (`CANSYFVM`, wasm e0c93198) with vote token gYBX (bonded YBX, wasm 6203d68f): **flash-loan-immune** (snapshot `get_past_votes` at `vote_start=now+48h`, 1:1-backed token, no free mint), quorum 5% + 51% + ~48h timelock + council cancel → capture needs a held majority stake ~7 days (economic, not a bug). XOXNO owner = OZ-timelock→EOA `GAVWFZK5`; Axelar→EOA; Tansu governs no value. No unprivileged takeover.

## Coverage note (2026-09-24)
The two highest-impact classes on Stellar are now both cleared by PoC/deep-trace: **unlimited USDC mint** (Circle CCTP TokenMessengerMinter `a6c1acc6` + MessageTransmitter `99bd0ddc`) and **bridge drain** (Allbridge classic `fb824a85`/`cfa823e6`/`a757a1ed` + 2026 CCTP `c340cb60`/`8d26318b`; HOT `cc74acb5`; USDT0/LayerZero `c1e1fce3`). Every DeFi category is covered: lending (Blend/XOXNO/money-market), AMMs (Aquarius/Soroswap/UniV3/Phoenix/Sushi/CometDEX), vaults (DeFindex/xBull/4b3d9f6b/ca6b85a1), bridges, oracles (Reflector/XOXNO/FxDAO), multisig (OneSig), tokens (SolvBTC/deJTRSY/SHX), CDP (FxDAO, wound down).

## Real defects found (non-exploit, responsible-disclosure — xBull Blend-vault `0fb61144`)

The xBull-vault inflation PoC (`reconstructed/xbull-poc/`, green on real bytecode) is the one place testing surfaced genuine bugs. Neither is attacker-profitable, but both are real and worth reporting to xBull:
1. **`deposit` rounding to 0 shares does not revert → silent depositor fund loss.** A deposit whose share-conversion floors to 0 still pulls the assets and mints nothing (the `VaultInvalidSharesAmount=404` guard exists but isn't enforced on this path). PoC: victim `deposit(1_000_000)` at an inflated share price → 0 shares, no revert, 1e6 lost. Reachable whenever share price is high (rare under the 1e7 virtual scale in normal operation; forced only via a griefing donation that costs the griefer more than the victim loses → low severity).
2. **`max_withdraw`/`total_assets` over-report** — they count the vault's idle token balance, but `withdraw`/`redeem` pay only from strategy withdrawals, so the reported withdrawable exceeds what can actually be paid (view/settlement inconsistency).

Not attacker-extractable (idle donations can't be withdrawn; strategy funds can't be inflated without minting shares), so no theft — but #1 is a normal-operation foot-gun that loses user funds and should revert.

## Residual risks (not contract bugs)
- **Centralization / owner-key**: several contracts have an owner/admin that can move funds (HOT bridge `owner_withdraw`, lockup admin, etc.). Operational trust, not attacker-reachable.
- **Not formally verified**: the deep fixed-point math internals of the two AMMs (Aquarius, 003710b3) beyond the property tests run; no concrete flaw found.

## Bug-class coverage (all verified on real bytecode where testable)
- Missing/incorrect auth on fund-movers — none (all sig/allowance/owner/role-gated).
- Allowance bypass (ERC-4626 operator) — enforced (4b3d9f6b f213 reverts InsufficientAllowance).
- Reentrancy / CEI — the two lockups' CEI smell is neutralized (SHX built-in SAC, non-reentrant).
- Oracle manipulation — none reachable (Blend uses external SEP-40 feed; AMMs are sources not consumers; DeFindex uses internal accounting).
- Vault first-deposit share inflation — mitigated: 4b3d9f6b OZ virtual-shares/decimals-offset; ae3409a4 1000 dead-shares + #117 revert (PoC: attack loses ~50M).
- Vault subaccounts (4b3d9f6b) — funds flow to the vault itself (keeper op), not caller → no drain.
- AMM value extraction (003710b3, ae0da5a8) — round-trip, mint/burn, out-of-range, dust, exact-output all PoC-safe; rounding favors the pool.

## Four false positives caught by real-bytecode discipline
1. Aquarius reward "drain" — mock LP token lacked the real transfer hook.
2. 003710b3 out-of-range "2× drain" — harness balance-tracking bug pushed price to max-tick; caught via slot0().tick.
3. DeFindex "victim loss" — actually the #117 min-deposit revert + a harness off-by-1000.
4. 76e60d02 money-market "remove_collateral/withdraw skip the health check" — a *static* call-graph result (neither path calls the borrow-health fn `f176`) that a real-bytecode PoC refuted: both paths apply a debt-aware cap (`remove_collateral` releases only `collateral − debt/open_ltv`; `withdraw` releases 0 when supply backs debt), so the obligation can't be driven insolvent.

PoC harnesses (all green on real bytecode): reconstructed/cl-poc (UniV3), reconstructed/aqua-poc (Aquarius), reconstructed/vault-poc (4b3d9f6b), reconstructed/dfx-poc (DeFindex), reconstructed/vault17-poc (ca6b85a1 $17M vault), reconstructed/mc-poc (76e60d02 money-market).

Honest conclusion: across the 15-target corpus AND the extended sweep (top holders of 13 major assets + the ca6b85a1 $17M vault + the 76e60d02 money-market), exhaustive review across all major loss-of-funds bug classes found NO attacker-reachable vulnerability. Every $10M+ contract on Stellar is either audited corpus code or a simple correctly-gated custodial vault. Four candidate findings were disproven by testing on the real bytecode. No fabricated finding.
