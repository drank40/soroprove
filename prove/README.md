# prove: agent proofs against locked invariants

Proves developer invariants about the `slice --lean model` output with an LLM agent, so that
the invariant cannot change while the proof does. One directory per contract:

```
Check.lean, lakefile.lean, lean-toolchain     shared, trusted: the checker and build
Spec/Common.lean                              shared, trusted: Run (any call sequence), Bystander
contracts/<c>/SOURCE                          the lifted IR the model is emitted from
contracts/<c>/Gen/Model.lean                  slice --lean model output (via gen.sh), trusted
contracts/<c>/Spec/Defs.lean                  developer definitions, trusted
contracts/<c>/Spec/Invariants.lean            the locked statements (`sorry`), trusted
contracts/<c>/spec.lock                       lock.sh: hashes of everything trusted
contracts/<c>/reference/Solution.lean         a past accepted agent proof (regression test)
```

```
./gen.sh C          # regenerate C's model; reports whether the spec still states against it
./lock.sh C         # after reviewing a model/spec diff
./agent.sh C [-r rounds] [-t turns] [-m model]   # agent proves C's invariants; runs/C-<time>/
./verify.sh C FILE  # check any proof file against C's locked spec
./tests/run.sh [C…] # reference proofs settle; cheats derived from each spec are rejected
```

The checker reports each locked theorem as PROVED, DISPROVED (the solution proves
`<name>_false : ¬ <statement>`, a kernel-checked counterexample), or REJECT. Theorems marked
PROBE in a spec are expected to be disproved: they pin a known limitation of the model, and
start passing when the emitter recovers what they need.

`verify.sh` takes only the proof file from the prover. It checks `spec.lock`, rejects source
that can run code or switch off checks, and builds in a fresh copy (trusted parts first,
failing if the proof's build touches them). `Check.lean` then requires each theorem to have
the identical elaborated statement, every definition the statement uses to come from the same
trusted module, only `propext` / `Classical.choice` / `Quot.sound` as axioms, and a clean
kernel replay of everything the solution declares.

Not yet sandboxed: the agent and the proof's build run as you, and the agent can write
outside its workspace. A proof can't fake the result, because verification uses only the
proof file, in a fresh copy of the locked tree. But untrusted provers should run in a container.

When the emitter changes a model, its reference proof may stop building, because proofs
destructure the model's conjunctions by position. Re-run `agent.sh` and copy the accepted
proof to `reference/`.
