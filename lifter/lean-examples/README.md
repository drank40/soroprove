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

## Writing proofs against a model

Like the hand-written `SorobanAmm.lean`, each model names what a proof talks
about. Every name below is `@[simp]`, so `simp` sees through it.

- **Storage layout:** one `Key` per slot, map, tuple key and struct field.
  ```lean
  Offer : Key                               -- .var "Offer"
  Offer.seller : Key                        -- .fld Offer "seller"
  Balance (a : Addr) : Key                  -- .entry "Balance" a
  Minter (c m : Int) : Key                  -- .tup "Minter" [c, m]
  Minter.limit (c m : Int) : Key            -- .fld (Minter c m) "limit"
  ```
- **Inputs**, per entrypoint: `trade.buyer st`, `trade.buy_token_amount st`,
  `set_minter.config.limit st` (a field of a struct argument),
  `deposit.claimants.len st`, and `pool st`, the contract's own address.
- **Effects**, per entrypoint, in execution order:
  - the states after each one, `trade.s1 st`, `trade.s2 st u`, …;
  - each transfer's amount, `withdraw.amt1 st`, …;
  - the main def says `st.post = trade.s3 st u`.

  A name takes `u` when it depends on a value the reconstruction leaves open.

For example, from `proofs/single_offer.lean`:

```lean
theorem trade_pays_seller (st : Step) (h : trade st)
    (hs : st.pre Offer.seller ≠ pool st) (hb : st.pre Offer.seller ≠ trade.buyer st)
    (ht : st.pre Offer.buy_token ≠ st.pre Offer.sell_token) :
    bal (st.pre Offer.buy_token) st.post (st.pre Offer.seller)
      = bal (st.pre Offer.buy_token) st.pre (st.pre Offer.seller) + trade.buy_token_amount st := by
  obtain ⟨u, _, _, _, _, hpost, _⟩ := h
  simp at hs hb ht
  rw [hpost]; simp [xfer, bal, Storage.set, hs, hb, ht, Ne.symm ht]
```

## What a theorem here means

Each model is built to **over-approximate** its contract: every successful
invocation of the real contract is a step its entrypoint's predicate admits,
for some choice of `u : Unk` (the values the reconstruction leaves open). So a
theorem `∀ st, entry st → P st` proved here holds for every successful
invocation of the contract. That holds under the assumptions below, and provided
the bytecode-to-Lean reconstruction is right.

The reconstruction is not formally verified. It is built so that it never
claims more than it knows, and it is checked against the real bytecode.

**By construction**, where the reconstruction can't be exact it weakens the
model:
- An unrecovered value, key or branch condition is an existential `u.i n` /
  `u.k n` / `u.b n`. It is never a guess, and never `False`.
- A call into another contract that isn't a SEP-41 `transfer` or `balance`
  leaves every token ledger open (`havoc`). The contract's own storage is
  unchanged, since Soroban forbids re-entry.
- Effects inside a loop, or past the analysis depth, leave all storage open.
- A guard binds only where its branch is reached (`reach → pass`). One that
  can't be stated is dropped.
- `require_auth(x)` means x is among the signers, under the condition the call
  runs in.
- Effects and reads are in execution order, including inside helpers.
- `get(k).unwrap_or(0)` is `getOr0`, gated on the presence bit. An absent key
  is not assumed to hold 0.

**By test**, `conformance/run.sh` runs each contract's real wasm in the Soroban
test VM under random invocations. It records every successful one: call,
signers, ledger info, storage and token balances before and after, and the
return value. It then evaluates the model's own conjuncts and post state on each
step in Lean. A step the model doesn't admit is a reconstruction bug.
`conformance/mutate.py` injects bugs into the models and confirms the check
catches them.

```
./lean-examples/conformance/run.sh [soroban-examples dir] [runs per contract]
```

CONFORMANCE_RESULTS

### Assumptions

- Every token the contract calls `transfer` or `balance` on behaves per SEP-41.
  Any other cross-contract call is uninterpreted (`havoc`).
- Encoding: addresses are `Addr` (Int) numbered in the host's order (so
  `obj_cmp` is `<`). Integers are their values (i128/u32/…, unbounded). Void
  is `2` and bools are `0`/`1` (their Val payloads). Struct arguments are
  flattened into args named like `config.limit`.
- A theorem that chains two steps (`b.pre = a.post`, e.g. `create_once`)
  assumes no ledger TTL expiry between them.

## Results

| contract | entrypoints | effects | guards (gates + auths) | still open (`u`) | theorems |
|---|---|---|---|---|---|
| atomic_swap    | 1  | 7  | 2 + 2  | none | 3 |
| increment      | 1  | 2  | 0      | none | 0 |
| liquidity_pool | 6  | 22 | 10 + 3 | integer `sqrt` (a loop), tuple returns | 3 |
| token          | 13 | 14 | 12 + 7 | `decimal` as stored by the constructor, `approve`'s amount | 3 |
| single_offer   | 5  | 7  | 6 + 4  | `trade`'s `amount * sell_price / buy_price`, `get_offer`'s struct return | 5 |
| timelock       | 2  | 6  | 4 + 2  | the `TimeBoundKind` enum value | 3 |
| mint_lock      | 6  | 6  | 1 + 3  | what `client.mint` does to the ledgers, `minter`'s tuple return | 2 |

Storage keys:
- `#[contracttype]` structs are stored field by field, as `.fld k "field"`,
  nested structs included (`.fld (.fld (.var "Balance") "time_bound") "timestamp"`).
- Multi-field key variants become `.tup`, e.g. `.tup "Minter" [contract, minter]`.
  So do variants that carry a struct, like token's
  `Allowance(AllowanceDataKey { from, spender })`.
- `.has k` is k's presence bit: every write sets it to 1, `remove` sets it to 0.
- `.bal t a` is token `t`'s balance of `a`.

The proved theorems:

- **token:** a transfer conserves `from + to`; a self-transfer leaves the balance unchanged; no one spends more than they hold.
- **atomic_swap:** for distinct tokens and parties, `a` pays exactly `min_a_for_b`, `b` receives exactly that, and the contract keeps nothing.
- **liquidity_pool:** `withdraw` burns exactly `share_amount`. For a pool of two distinct tokens, it conserves token A between the pool and the caller, and afterwards `ReserveA` equals the pool's actual balance.
- **single_offer:** `create` records seller and tokens from its arguments and can run only once; `updt_price` needs the seller's signature and keeps the seller and tokens; `trade` pays the seller the buyer's `buy_token_amount`; `withdraw` needs the seller's signature and pays the seller.
- **timelock:** the contract can be funded only once; a balance can be claimed only once; `claim` pays the claimant exactly the recorded amount in the recorded token.
- **mint_lock:** only the admin configures a minter, and the config is stored under `(contract, minter)`; a non-admin `mint` succeeds only for a configured minter, within its epoch limit.

### What is still open, and why

- **Loops**, such as `liquidity_pool`'s integer square root, have no closed form to lift.
- **Tuple and whole-struct returns:** the model's `ret` is a single `Int`.
- **Enum values carried as data** (timelock's `TimeBoundKind`, stored as `Vec[Symbol]`) aren't decoded.
- **Inlined i128 multiplication:** in `single_offer::trade`, rustc expands `checked_mul` by a `u32` into limb arithmetic, which isn't recognized as a multiply.
- **Path-dependent addresses:** token's `approve` stores the amount at a frame offset chosen by a `phi`.
- **Uninterpreted calls:** mint_lock's `client.mint` leaves the token ledgers open.
