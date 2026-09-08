# Samples

Each `.wasm` here has a checked-in `.ll` golden next to it. `./build.sh`
regenerates both; `git diff samples/` is then the regression gate.

`cargo test` lowers every `.wasm` in this directory and asserts the module
passes `module.verify()`, so a sample that stops verifying fails the build.

## `three_bugs/` — source, built here

A contract written to exercise the three defects this tool exists to prevent,
found by auditing `Inferara/soroban-ret` against SDK ground truth:

| function | shape | the defect it targets |
|---|---|---|
| `set_flag` | stores `&true` | `true` is `Val` payload 1 (`Tag::True`); rendering it as the integer `1` writes `ScVal::U32(1)` instead of `ScVal::Bool(true)` |
| `pick` | five-way dispatch, one arm a bare `Err` return | that arm branches straight to the function epilogue rather than a block tail, and a depth-indexed structurizer drops it |
| `read` | key is `DataKey::Pair(PairKey { a, b })` | a nested-struct storage key built from two params — recovering the shape but not the values must stay a hole |

Built at two profiles, because a tool whose risk is being tuned to one compiler
shape should be tested against more than one:

- `three_bugs.wasm` — `release` (`opt-level="z"`, fat LTO), what contracts ship as
- `three_bugs-fat.wasm` — `fat` (`opt-level=3`), inlines more, different codegen

**Known limitation.** At every profile tried, the SDK's generic
`storage().set::<K,V>` stays outlined, so the `Val` constant is passed as an
`i64` parameter to a helper and never reaches a host call site in the same
function. So this sample does *not* exhibit the constant-at-a-Val-position
shape, which is why `errors.wasm` is vendored below.

That outlining is also why the default (exports-only) view of `set_flag` is two
opaque helper calls. Release wasm has no name section, so helpers are `f<index>`,
and each declared helper carries the set of host functions it reaches -- so the
reader can see the `put_contract_data` behind `f17` without `--all`:

```llvm
define %Val @set_flag() {
entry:
  call void @f33()
  call void @f17()
  %v_void = call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v_void
}
declare void @f33() #6      ; attributes #6 = { "soroban.calls" }            -- reaches nothing (empty fn)
declare void @f17() #9      ; attributes #9 = { "soroban.calls"="ledger.put_contract_data" }
```

`f33` really is an empty function in the wasm (`(func (;33;) (type 10))`); the
call is faithful, not a decoding gap. `--all` defines every helper instead.

## `errors.wasm` — vendored, 796 bytes

The canonical case: it exhibits all three shapes in one exported function, and
it is the binary the analysis was done against.

- Provenance: `tests/fixtures/test_errors.wasm` in
  [Inferara/soroban-ret](https://github.com/Inferara/soroban-ret) (Apache-2.0),
  itself built from `tests/errors` in
  [stellar/rs-soroban-sdk](https://github.com/stellar/rs-soroban-sdk) (Apache-2.0).
- `errors.reference.rs` is that SDK test contract's **source**, so the golden IR
  can be read against what the contract actually says. Comparing the two is how
  the three defects were found in the first place.

What it shows, from `errors.ll`:

```llvm
%v_Symbol__persisted__ = call %Val @soroban.val.from_payload(i64 3867323444879862030)
%v_true                = call %Val @soroban.val.from_payload(i64 1)
%Persistent            = call i64  @soroban.storage_type(i64 1)
%put_contract_data     = call %Val @ledger.put_contract_data(%Val %v_Symbol__persisted__, %Val %v_true, i64 %Persistent)
switch i32 %sel, label %c7 [ i32 0, label %c6      ; Flag::A -> Ok(Symbol "hello")
                             i32 1, label %c5      ; Flag::B -> Err(AnError)
                             i32 2, label %c9      ; Flag::C -> panic_with_error
                             i32 3, label %c8 ]    ; Flag::D -> panic;  default = Flag::E
```

`%v_true` is `true`, not `1`. All five destinations are present, including the
`Flag::B` arm. The `%v_` prefix carries the decode in the SSA name rather than a
comment, so it survives optimisation passes.

Syscalls read as syscalls: the result is named after the host function, a
`StorageType` operand is `%Persistent` rather than `i64 1`, and each host
declaration carries the wasm import it was resolved from as an attribute, so
the IR stays traceable to the binary:

```llvm
declare %Val @ledger.put_contract_data(%Val, %Val, i64) #1
attributes #1 = { "soroban.import"="l._" "soroban.sig"="(Val, Val, StorageType) -> Void" }
```

## Wider corpus, not vendored

The gate during development ran against 43 SDK-derived fixtures and 24 real
mainnet contracts (Blend, Soroswap, Aqua, Phoenix, Reflector, FxDAO, Comet,
xycloans) from `soroban-ret`'s `tests/fixtures/` and `benchmark-data/mainnet/`.
Those are not copied here — clone that repo and point the binary at them:

```sh
for f in <soroban-ret>/benchmark-data/mainnet/*.wasm; do
    ./target/release/ponytail-wasm "$f" --all >/dev/null || echo "FAILED $f"
done
```

67 binaries, 134 runs (both modes), all verify.

In exports mode 641 of the 716 export returns carry a value; 75 are bottom.
A bottom return means the returned value is one the model does not carry: it
came from an operator that is not modelled (a linear-memory load, `select`,
a global), or it was the result of a typed `block`/`if`, which the operand
stack does not thread across `end` (549 such labels in the corpus). No `exit`
block survives in any output, so a conditional `br_if` to the function's own
label -- the one return shape still lowered as bottom -- does not occur here.
