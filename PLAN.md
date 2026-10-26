# soroban-lean: a Lean 4 model of the Soroban runtime

Goal: a faithful, executable Lean model of the Soroban contract runtime
(Wasm VM + host), efficient enough to prove properties of real compiled
contracts (`.wasm` bytes), in the spirit of qedsvm for Solana. qedsvm's measured
weaknesses on real programs (see `~/doc/work/solana/qedsvm-eval/REPORT.md`)
were avoided by design from the start:

- **Unmodeled runtime calls.** qedsvm's lifter stopped at `sol_get_clock_sysvar`.
  Here *every* host function in `env.json` is in the generated table from day
  one, and a call is never silently skipped.
- **Whole-path symbolic triples that check in O(n^2.3..2.9).** Here proofs are
  compositional (per-function summaries) and the step relation unfolds in O(1)
  per instruction (structured big-step over instruction lists, no PC indexing
  into array literals).
- **Executor that re-decodes the binary per call and diverges on fees.** Here
  the module is decoded once, and the budget/fuel model is taken from the host
  source.

## Pinned sources (vendor/, never edited)

| What | Version | Why |
|---|---|---|
| rs-soroban-env | v30.0.0 @ 0c99950 | host + common + env.json (202 host fns, 11 modules) |
| soroban-wasmi (+ wasmi_core 0.13.0, wasmi_arena 0.4.1, wasmparser-nostd 0.100.2) | 29.0.0 (crates.io, sha256 = Cargo.lock) | the engine the host runs contracts on |
| stellar-xdr | 30.0.0 (crates.io, sha256 = Cargo.lock) | ScVal/ScError/... XDR types used by host fns |
| rs-soroban-sdk | v29.0.1 | SDK that real contracts are built with (guest side) |
| soroban-examples | 03d42aa | real contracts to verify |
| WebAssembly/testsuite | 7ef86dd (2023-03, pre-Wasm-3.0) | Wasm conformance tests |

## Accuracy policy

1. Every Lean definition that models runtime behaviour carries a `-- src:` comment
   giving the pinned file and line it was transcribed from.
2. Nothing is "assumed to work like the spec". wasmi's actual behaviour is the
   reference wherever wasmi and the Wasm spec could differ (for example, trap
   ordering and fuel charging).
3. Generated artefacts (the host-fn table) are produced by scripts from the
   pinned sources, never typed by hand.
4. Every layer gets differential tests against the real implementation: the Wasm
   spec testsuite plus a Rust harness driving the real soroban-env-host v30 on
   the same inputs.

## Wasm feature set (src: soroban-env-host/src/budget/wasmi_helper.rs:136-159)

- consume_fuel, bulk_memory, mutable_global and sign_extension are ON.
- saturating_float_to_int, multi_value, reference_types, tail_call,
  extended_const and floats are OFF.
- Fuel mode: Eager.

So the values are only i32/i64, every block has at most one result, there are
no ref types, and memory is single and 32-bit.

## Layers / milestones

- [ ] M1 Host-fn table: `tools/gen_env.py` reads env.json and generates
      `SorobanLean/Env/HostFns.lean` (all 202 fns: module/export ids, arg/ret
      Val types, protocol bounds) plus import resolution.
- [ ] M2 Val: the 64-bit tagged encoding (soroban-env-common/src/val.rs and
      friends): tags, small values, symbols, object handles, Error, and the
      `try_marshal_from_value` / `check_env_arg` checks.
- [ ] M3 Wasm: binary decoder (in Lean, over the actual bytes), the Soroban
      validation rules (parsed_module.rs), and an interpreter with wasmi
      semantics for traps and fuel. Conformance against the testsuite subset.
- [ ] M4 Host core: object table (relative/absolute handles), storage
      (persistent/temporary/instance plus TTL), contexts/frames, events,
      ledger info, auth, budget (ContractCostType models), errors → traps.
- [ ] M5 Host fns: semantics for all 202, module by module, each citing source.
      Differential harness vs the real host.
- [ ] M6 Proof engine: compositional function summaries, an O(1)-per-instruction
      step tactic, memory/stack-frame reasoning, host-call summaries.
- [ ] M7 Real properties on real wasm: soroban-examples `increment` (counter +1),
      `token` (transfer conserves balances, requires auth, rejects overdraft).
      Measure cost and make sure it scales roughly linearly.

## Log
(see bottom; newest last)

### 2026-10-25
- M1 done: `tools/gen_env.py` → `SorobanLean/Env/HostFns.lean` (202 fns, 29 ValTys, 11 modules), kernel-checked resolve round-trip.
- M2 (Val) done: tags, bodies, errors (ScErrorType/Code from xdr 30), small symbols, `is_good`, per-type `try_marshal_from_value`. `difftest/val_oracle` vs Lean: 215,616 payloads, 0 mismatches.
- M3a decoder: `SorobanLean/Wasm/{Syntax,Decode,Dump}.lean`; `tools/diff_decode.sh` vs wasmparser-nostd 0.100.2 on 132-module corpus (env test wasms + soroban-ret mainnet + local audits): 131/131 identical canonical dumps, 1 float module rejected.
- TODO: make the decoder total (fuel = remaining bytes) so `decodeModule bytes = .ok m` is kernel-checkable for the proof link.
- M3 Wasm VM done: `Compile.lean` (wasmi translator transcription: fuel charge points, max stack height), `Exec.lean` (big-step, O(1)/instr, structural recursion on a step budget), `Instantiate.lean`.
  - `tools/diff_wasmi.sh`: Lean vs real soroban-wasmi 29.0.0 (Soroban config: features, calibrated fuel costs, Eager) on 7,646 spec-testsuite invocations → 0 differences in outcome AND exact cumulative fuel.
  - `tools/spectest.sh` (WebAssembly/testsuite 7ef86dd): 8,480 pass, 5 "fail" = confirmed wasmi deviation from the spec (bulk-memory `i32 as usize` sign-extension → OutOfFuel before the bounds check).
  - Validation-level checks wasmparser applies with Soroban features are enforced by the decoder (multi-value, first-byte zero, datacount, single table/memory, reftype const exprs). TODO M3c: full operator type-checking validator.
- XDR: `tools/gen_xdr.py` generates all 477 types + 18 consts from stellar-xdr 30.0.0's `xdr-definitions-json` (SCC-based mutual blocks) and a codec transcribing stellar-xdr's runtime (depth per read incl. primitives, length limit, bool==1 rule, padding, max counts, read_xdr_to_end). `difftest/xdr_oracle` (random arbitrary values + bit-flip/truncate/extend mutations of every type) vs Lean: 114,480 cases, 0 mismatches (accept/reject, error kind, re-encoded bytes).
- M4 host core + first M5 slice: `Host/{Budget,Meter,State,Core,Conv,MeteredXdr,E2E,Storage,Vm,Frame,Dispatch,Invoke,E2EFinish}.lean`, `Crypto/Sha256.lean` (SHA-256 + HMAC, checked against FIPS/RFC 4231 vectors).
  - Host monad is `ExceptT HErr (StateM HostState)`: state survives errors as in Rust (budget, objects, lazily decoded entries); `Budget.charge` keeps the bumped counters on overrun.
  - Every `RefCell` conflict that the Rust host turns into (Context, InternalError) inside `with_current_context_mut` is modelled with an explicit borrow flag.
  - Contract → host fn → contract recursion is structural on a Lean gas `n` (`callNInternal (n+1)` runs its VM with nested calls at `n`); `gasOutErr` / `unsupportedErr` are Lean-only markers with tag byte `Bad`, never real host errors.
  - **Differential result: `sl e2e-trace` vs the real host's `invoke_host_function` (patched charge tracer) on the increment contract with mainnet cost params: call0 286/286, call1 306/306, call2 306/306 budget charges identical in order (type, iterations, input), and every output identical (encoded result, ledger changes incl. encoded new entries, rent sizes and TTL changes, cpu, peak mem, all per-type trackers).** ~30 ms per invocation natively.
  - Implemented host fns: has/get/put/del_contract_data, extend_contract_data_ttl, extend_current_contract_instance_and_code_ttl (+ symbol_len/symbol_copy_to_slice/symbol_new_from_slice paths used internally).
  - Explicitly unsupported for now (raise `unsupportedErr`): auth trackers (require_auth), contract events, built-in SAC, executable refs, create/upload host functions, every other host fn. Known modelling choice: no module cache (oracle passes `None`; stellar-core passes one since p23 — cached instantiation path TBD). Wasm function-body type validation (M3c) still trusted for deployed code.
