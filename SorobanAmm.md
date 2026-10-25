# Soroban liquidity pool in Lean

The constant-product AMM from
[stellar/soroban-examples `liquidity_pool`](https://github.com/stellar/soroban-examples/blob/main/liquidity_pool/src/lib.rs),
translated by hand the way a WASM → Lean converter would, then questioned about
**auth**, **storage** and **transfers**.

| File | What it is |
|---|---|
| `StellarLean/SorobanAmm.lean` | The model: `deposit`, `swap`, `withdraw`, the token transfers they make, and the frame proof |
| `StellarLean/SorobanAmmFacts.lean` | What a converter would emit for `answer`: entry points, preconditions, the effect of each entry point on every ledger, share and variable |
| `StellarLean/SorobanAmmAnswers.lean` | 21 questions: 18 proved by `answer`, 3 by hand |
| `scripts/proof_times.py` | Per-theorem proving time |

## How the model works

- **World storage.** The pool's own slots (`TokenA`, `TokenB`, `TotalShares`,
  `ReserveA`, `ReserveB`, `Shares(addr)`) sit in the same storage as the ledgers
  of the two tokens (`A.Balance`, `B.Balance`). So a cross-contract
  `token.transfer` is a write to storage like any other, with the token's own
  panics as preconditions.
- **Auth.** The signer is `to` (`to.require_auth()`). Every token transfer also
  checks `from.require_auth()`: `from` must be the signer, or the pool itself.
  The pool's address is an `opaque` constant, so every answer holds whatever
  address the pool is deployed at.
- **One entry point, two directions.** `swap`'s `buy_a` picks the sold side and
  the bought side. The code is the same for both, so the model writes it once
  over a `Side`.
- **What the model leaves out.** i128 overflow in the pool's own arithmetic is
  not modelled. Leaving out a panic only adds possible calls, so every "for every
  successful call" answer still holds for the real contract. The model does
  keep: token balance overflow, division by zero, Rust's round-toward-zero
  division (`Int.tdiv`) and every `panic!`.

## Questions and proving times

Each time is the median of 5 runs on this machine: statement plus proof,
measured by Lean's profiler with async elaboration off. Re-run with:

```bash
python3 scripts/proof_times.py StellarLean/SorobanAmmAnswers.lean
```

| | Question | Proved by | ms |
|---|---|---|---:|
| **Auth** | Can anyone but the signer or the pool lose tokens? No | `answer` | 163 |
| | Can anyone but the signer lose shares? No | `answer` | 64 |
| | Do tokens only move between the signer and the pool? Yes | `answer` | 169 |
| **Storage** | Can the token addresses change after deploy? No | `answer` | 49 |
| | Does a call touch anyone else's shares? No | `answer` | 59 |
| | Does a call touch anyone else's token balance? No | `answer` | 107 |
| | After every call, are the reserves the pool's real balances? Yes | `answer` | 55 |
| | Does `TotalShares` move exactly with the sum of shares? Yes | `answer` | 90 |
| | After any sequence of calls, are both ledgers valid (0 ≤ b ≤ i128 max)? Yes | `answer` (invariant) | 698 |
| **Transfers** | Swapping for A, does the signer get exactly `out`? Yes | `answer` | 68 |
| | Does a swap take more than `in_max`? No, either direction | `answer` | 98 |
| | Does a deposit take more than desired? No | `answer` | 87 |
| | Does a deposit always take both tokens? Yes | `answer` | 91 |
| | Does a withdrawal pay at least `min_a`/`min_b`? Yes | `answer` | 91 |
| | Does a withdrawal burn exactly `share_amount`? Yes | `answer` | 63 |
| | Withdraw more shares than you have? Fails | `answer` | 18 |
| | Buy more A than the reserve holds? Fails | `answer` | 21 |
| | Swap for a negative amount? Fails | `answer` | 25 |
| **Harder** | Can a swap lower `reserve_a × reserve_b`? No (reserves in sync before) | by hand | 229 |
| | Can a withdrawal hand out shares for nothing? In some states, yes | by hand (example) | 134 |
| | …impossible whenever the pool holds ≥ `TotalShares` of token A | by hand | 46 |

The 18 `answer` proofs take 2.0 s together, and the whole file takes 2.4 s. The
facts file is checked once per contract (0.9 s), and the model takes 0.1 s.

For comparison, the token's 9 `answer` questions (`SorobanTokenAnswers.lean`)
take 0.35 s. The AMM's single-call questions take about 2–4× as long as the
token's (50–170 ms against 30–40 ms), because `grind` has to rule out three
entry points and two swap directions. The invariant question costs the most in
both contracts: 698 ms against 121 ms.

### Why three questions need a hand proof

- **Constant product.** It multiplies two unknowns, and `grind` does not reason
  about products of unknowns. The hand proof uses the code's own check
  (`new_inv_a * new_inv_b ≥ old_inv_a * old_inv_b`), the fact that the fee
  factor never exceeds the new reserve, and the sync of the reserves.
- **Free shares.** It asks for an example to exist, and `answer` cannot build
  examples.
- **When free shares are impossible.** It needs facts about `/` on unknowns.

## Finding: `withdraw` accepts a negative `share_amount`

`withdraw` never checks `share_amount ≥ 0`. Take `share_amount = -1` on a pool
holding 1 of each token with 2 shares outstanding:

- both payouts round to 0 (`1 * -1 / 2` is 0 in Rust);
- the "insufficient shares" check passes;
- "burning" −1 shares *adds* one share to the signer and to `TotalShares`;
- no token moves.

`withdraw_can_mint_free_shares` proves this call succeeds.

**Is it reachable?** That is not proved. It needs `TotalShares` to exceed
*both* pool balances. `withdraw_share_nonneg` proves the trick is impossible
whenever the pool holds at least `TotalShares` of token A (the same argument
works for token B). An informal argument says normal use keeps
`TotalShares² ≤ balance_a × balance_b`, which rules that state out. Proving
it would need a nonlinear invariant over `sqrt` and division, so it's the
natural next hard question. Either way, an explicit `share_amount > 0` check
in `withdraw` (as `deposit` has for its amounts) would remove the question.

## Changes to the shared library

- `Query.Call` has two new fields with defaults: `fn` (which entry point is
  called) and `arg` (named number arguments). Existing files needed four
  `⟨…⟩` constructors rewritten with field names.
- New bricks: `calls "swap"`, `dropsAtMost`, `gainsAtLeast`, and
  `+`/`-`/`*` on number terms.
- New storage lemmas: reading a map or a variable after writing another slot.
