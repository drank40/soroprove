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

## Proof by vibe

Choose **vibe** as a theorem's proof (the `:= by` dropdown) and press **Check in Lean**.
A Claude agent then searches for a proof or a counterexample within the **Vibe budget**
(seconds, in the title bar), and the **Vibe** tab follows it live: every version it
writes is checked by Lean as soon as it is saved, and the card shows the time used, the
proof with Lean's errors on their lines, and the outcome:

- **Proved**: Lean accepts a proof of exactly the block's statement, with the standard
  axioms only (`propext`, `Classical.choice`, `Quot.sound`).
- **Counterexample found**: Lean accepts a refutation, with a concrete call that breaks
  the claim. The card shows the call and the storage before and after, labelled with the
  contract's storage interface (`storage` in `vocab.js`, recovered from the wasm by
  stellar-diver), changed rows highlighted.
- **Undecided**: neither within the budget.

The developer still writes the statement with blocks; the agent never gets to change it.
It edits only a proof body; `vibe.py` places that body after the contract's prelude and
appends a tail of its own that restates the statement and accepts only
`VibeProof.<name>` (or `VibeProof.<name>_false` for a refutation) as its proof. The body
may not contain anything that runs code or changes how the tail is read (`#eval`,
macros, notation, instances, `axiom`, …).

The agent is `claude -p` on the Claude subscription of whoever runs the server (the
server removes `ANTHROPIC_API_KEY` from its environment), in `--safe-mode` with no MCP
servers: no user settings, memory or connectors, file tools confined to a temporary
workspace plus `StellarLean/`, and the only shell command it may run is `./check`.
`VIBE_MODEL` picks the model. Because jobs spend that subscription, `/vibe` answers only
requests from this machine, or anyone with the token when the server runs with
`VIBE_TOKEN=…` (needed behind ngrok or any other proxy; the page asks for it once).
