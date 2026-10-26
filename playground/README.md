# Theorem Blocks

A Scratch-style editor for StellarLean questions. Each brick of `Query.lean`
(`changesBy`, `calls`, `BalanceA[…]`, `caller`, `∧ₛ`, `.given`, …) is a block;
snap them into a `theorem` hat to build statements such as

```lean
contract ⊨ (changesBy BalanceA[caller] out).given (calls "swap" ∧ₛ buysA)
```

```bash
cd playground && npm install && python3 server.py
```

Then open http://localhost:8765/. To reach it from other machines, pass a
port and host: `python3 server.py 8765 0.0.0.0`.

## Blocks

| Shape | Type | Examples |
|---|---|---|
| hexagon | question / invariant | `unchanged`, `changesBy`, `calls`, `buysA`, `∧ₛ`, `.given`, `∀ₛ`, `reservesSynced` |
| round | storage value | `TotalShares`, `BalanceA [ ]`, `Shares.total`, `+ − ×` |
| square | who / argument / entry point | `caller`, `pool`, `user`, `out`, `(- amount ·)`, `"swap"` |

A slot accepts only blocks of the right type, so `calls` takes an entry point
and `BalanceA [ ]` takes a who. `∀ₛ user` binds the `user` block, and an
unbound `user` is flagged.

The right panel shows the Lean (hover or click to find the block), a reading
in plain words, and the results of **Check in Lean**. That button sends the
statements to `server.py`, which writes a file under the contract's prelude
and runs `lake env lean` on it (run `lake build` first). The server accepts
only tokens the blocks can produce, so arbitrary Lean cannot be sent to it.

**Words** relabels the blocks in English; **Import Lean…** turns pasted
statements into blocks.

## Files

- `vocab.js`: the contracts and their vocabulary (also read by `server.py`).
  Add a contract or a brick here.
- `lean.js`: block definitions, printing to Lean and words, parsing Lean.
- `app.js`, `index.html`, `style.css`: the editor (Blockly, zelos renderer).
- `server.py`: static files and `/check`.

For the AMM the server repeats the vocabulary of `SorobanAmmAnswers.lean` in
its prelude and imports `SorobanAmmFacts`, so checks work while that file does
not build.
