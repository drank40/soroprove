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

| contract | entrypoints | effects | guards | remaining `opaque` (besides `pool`) | theorems |
|---|---|---|---|---|---|
| atomic_swap    | 1  | 6  | 2 + 2 signers | none | 3 |
| increment      | 1  | 1  | 0  | none | 0 |
| liquidity_pool | 6  | 21 | 11 | integer `sqrt` (a loop), tuple returns | 5 |
| token          | 13 | 13 | 12 | allowance struct, string metadata getters | 3 |
| single_offer   | 5  | 6  | 5  | `Offer` struct fields | 0 |
| timelock       | 2  | 3  | 0  | `ClaimableBalance` struct | 0 |
| mint_lock      | 6  | 4  | 1  | `MinterConfig`/`MinterStats` structs (values and keys) | 0 |

The proved theorems:

- **token:** a transfer conserves `from + to`; a self-transfer leaves the balance unchanged; no one spends more than they hold.
- **atomic_swap:** `a` pays exactly `min_a_for_b`, `b` receives exactly that, and the contract keeps nothing.
- **liquidity_pool:** `withdraw` burns exactly `share_amount` and conserves token A between the pool and the caller, and afterwards `ReserveA` equals the pool's actual balance. The emitter also generates `swap_keeps_product` and `no_drain` for this contract.

### What is still `opaque`, and why

- **`#[contracttype]` structs** are stored as Soroban maps. Their fields aren't decomposed yet, which covers most of the opaques in single_offer, timelock and mint_lock.
- **Loops**, such as `liquidity_pool`'s integer square root, have no closed form to lift.
- **Tuple and Vec returns:** the model's `ret` is a single `Int`.

### Assumptions

- Each token ledger is keyed by the storage slot that holds the token's address (`"TokenA"`), or by the address itself when the token is an argument. So distinct slots are assumed to hold distinct tokens.
- Effects inside a single helper call are ordered at that call's position in the entrypoint.
