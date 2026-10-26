# Lean models of the soroban-examples contracts

Each `<contract>.lean` is emitted by `slice --lean model` from the contract's
compiled wasm: one `Step → Prop` per entrypoint, in the style of
[`SorobanAmm.lean`](https://github.com/julian-osec/stellar-lean-playground/blob/2b32f28b646832eba25909501ec1e4a5d1196e23/StellarLean/SorobanAmm.lean).
Each def threads the entrypoint's effects (SEP-41 transfers, storage writes) in
program order as states `s1, s2, …`, and lists its guards (`require_auth`,
every panic condition, `Err` returns). Values are written over call arguments,
named storage slots, and token ledgers.

`proofs/<contract>.lean` holds theorems about a model; `check.sh` appends them
to the freshly generated model and typechecks the result.

```
./lean-examples/check.sh          # regenerate every model, append proofs, typecheck
```

## Regenerating the inputs

`check.sh` reads the decompiled IR, `<contract>.ll`. The repo gitignores `*.ll`
as generated output, so regenerate them first:

```
cd soroban-examples/<contract> && stellar contract build
./target/release/stellar-diver <wasm> --inline > lean-examples/<contract>.ll
```

## Results

| contract | entrypoints | effects | guards (gates + auths) | remaining `opaque` (besides `pool`) | theorems |
|---|---|---|---|---|---|
| atomic_swap    | 1  | 7  | 2 + 2  | none | 3 |
| increment      | 1  | 2  | 0      | none | 0 |
| liquidity_pool | 6  | 22 | 12 + 3 | integer `sqrt` (a loop), tuple returns | 5 |
| token          | 13 | 14 | 12 + 7 | `decimal` as stored by the constructor, `approve`'s amount | 3 |
| single_offer   | 5  | 7  | 6 + 4  | `trade`'s `amount * sell_price / buy_price`, `get_offer`'s struct return | 4 |
| timelock       | 2  | 6  | 4 + 2  | the `TimeBoundKind` enum value | 3 |
| mint_lock      | 6  | 5  | 1 + 3  | `minter`'s tuple return | 2 |

`#[contracttype]` structs are stored field by field, as `.fld k "field"`, nested
structs included (`.fld (.fld (.var "Balance") "time_bound") "timestamp"`).
Multi-field key variants become `.tup`, e.g. `.tup "Minter" [contract, minter]`,
and so do variants that carry a struct (token's `Allowance(AllowanceDataKey {
from, spender })`). `has(k)` reads `.has k`, which every write sets to 1 and
`remove` sets to 0.

The proved theorems:

- **token:** a transfer conserves `from + to`; a self-transfer leaves the balance unchanged; no one spends more than they hold.
- **atomic_swap:** `a` pays exactly `min_a_for_b`, `b` receives exactly that, and the contract keeps nothing.
- **liquidity_pool:** `withdraw` burns exactly `share_amount` and conserves token A between the pool and the caller, and afterwards `ReserveA` equals the pool's actual balance. The emitter also generates `swap_keeps_product` and `no_drain` for this contract.
- **single_offer:** `create` records seller and tokens from its arguments and can run only once; `updt_price` needs the seller's signature and keeps the seller and tokens; `withdraw` needs the seller's signature and pays the seller.
- **timelock:** the contract can be funded only once; a balance can be claimed only once; `claim` pays the claimant exactly the recorded amount in the recorded token.
- **mint_lock:** only the admin configures a minter, and the config is stored under `(contract, minter)`; a non-admin `mint` succeeds only for a configured minter, within its epoch limit.

### What is still `opaque`, and why

- **Loops**, such as `liquidity_pool`'s integer square root, have no closed form to lift.
- **Tuple and whole-struct returns:** the model's `ret` is a single `Int`.
- **Enum values carried as data** (timelock's `TimeBoundKind`, stored as `Vec[Symbol]`): the model doesn't decode them.
- **Inlined i128 multiplication:** in `single_offer::trade`, rustc expands `checked_mul` by a `u32` into limb arithmetic, which isn't recognized as a multiply.
- **Path-dependent addresses:** token's `approve` stores the amount at a frame offset chosen by a `phi`, so it stays opaque rather than guessed.

When a branch condition can't be rendered, it becomes an opaque `Step → Bool`.
It never becomes `False`, which would claim the guarded effect cannot happen.

### Assumptions

- Each token ledger is keyed by the storage slot that holds the token's address (`"TokenA"`, `"Offer.buy_token"`), or by the address itself when the token is an argument. So distinct slots are assumed to hold distinct tokens.
- An absent key reads as 0 (`get(k).unwrap_or(0)` / `unwrap_or_default()`).
- The host's object order (`obj_cmp`, e.g. `token_a < token_b`) is the order on `Addr`.
- Loops terminate. The code after a loop runs whenever the loop is entered.
- Effects inside a single helper call are ordered at that call's position in the entrypoint.
