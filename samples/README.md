# Samples

Each `.wasm` here has four checked-in goldens next to it, one pipeline: `.ll`
is `--all`, every function as lowered; `.inline.ll` is `--inline`, the exports
after LLVM has folded the SDK plumbing into them; `.mir` is the MIR
`../ponytail-mir` builds from that IR inside rustc; `.rs` is the Rust it emits
from that MIR. `./build.sh` regenerates all of it; `git diff samples/` is then
the regression gate.

`cargo test` here lowers every `.wasm` in all three IR modes and asserts the
module passes `module.verify()`; `cargo test` in `../ponytail-mir` runs
`three_bugs.inline.ll` through MIR and Rust and compiles the Rust with stable
rustc. A sample that stops verifying or type-checking fails one of them.

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

`--inline` goes further and lets LLVM do the interpretation. Helpers become
`internal` and O1's inliner folds the single-call-site and small ones into the
export; the shadow-stack frame LLVM's wasm backend opens in every function
(`global.get 0; i32.const N; i32.sub; local.tee L; global.set 0`) is
recovered as an `alloca`, so the frame is the function-local memory it really
is; a load whose address inlining made constant is read from the data segment.
`set_flag` then reads as the syscall it is, complete (`three_bugs.inline.ll`):

```llvm
define %Val @set_flag() local_unnamed_addr {
entry:
  %v_Symbol__f__ = call %Val @soroban.val.from_payload(i64 11022)
  %v_true = call %Val @soroban.val.from_payload(i64 1)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %put_contract_data = call %Val @ledger.put_contract_data(%Val %v_Symbol__f__, %Val %v_true, i64 %Persistent)
  %v_void = call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v_void
}
```

Nothing here is pattern-matched. The key was a constant stored to a frame slot
and reloaded through a pointer three helpers down: after inlining, the tool
folds `inttoptr(ptrtoint(frame) + 8)` back to the frame (LLVM will not, on
provenance grounds that do not hold for wasm's flat memory), GVN forwards the
store, DSE drops it, and the frame goes with it. `true` is the byte at `&true`
in the data segment; `Persistent` is the `i64 1` an inlined wrapper passed
along. Two assumptions carry this, both stated in the code: the data segment is
constant unless some store in the module targets it at a constant address (Rust
keeps mutable statics out of rodata, so this is the usual decompiler bet), and
wasm `unreachable` is a trap (`@soroban.trap`), never LLVM's "cannot happen" --
lowered bare, O1 turned the SDK's argument checks into `llvm.assume` and they
vanished. Helpers the cost model leaves outlined stay in the file as `define
internal`. Forcing `alwaysinline` on all of them was tried first: 5.7 GB and
no result on a 187-function contract.

## `ponytail-mir`: wasm -> LLVM -> MIR -> Rust

From the `--inline` IR, `../ponytail-mir` (a nightly crate on `rustc_private`)
makes the MIR rustc's own. It generates a stub crate from the `.ll`'s
declarations -- `Val` and `StorageType`, one `extern "C"` per host function
and intrinsic, one static per wasm global, one empty `fn` per defined function
-- compiles it in-process, and replaces rustc's `build_mir_inner_impl` hook so
that each stub's MIR *is* the body lifted from the LLVM function of the same
name. From there rustc treats it like any body it built itself: it
borrow-checks it (the NLL type check verifies every statement), validates it
after every pass (`-Zvalidate-mir`), and optimizes it with its own inliner,
GVN, copy propagation and dead-code passes (`-Zmir-opt-level=3`).
`optimized_mir` is what gets printed and what the Rust is emitted from.

The lift itself: one basic block per LLVM block, split at calls; phis as copies
in an edge block; `%Val` as the ADT, its constructor an aggregate and its
payload a field projection; a `StorageType` literal an enum variant, a runtime
one a call to `core::intrinsics::transmute` that rustc lowers to its own
`Transmute` cast; a frame a `[u64; N]` local whose raw address is taken;
`trunc to i1` the low bit, since MIR has no int-to-bool cast; LLVM `noreturn`
is `-> !`. Anything without a MIR equivalent is an error, never a guess. From
`three_bugs.mir`, after rustc's passes:

```
fn set_flag() -> Val {
    debug v_Symbol__f__ => const Val(11022_u64);
    debug v_true => const Val(1_u64);
    debug Persistent => const StorageType::Persistent;
    debug put_contract_data => _1;
    debug v_void => const Val(2_u64);
    let mut _0: Val;
    let mut _1: Val;

    bb0: {
        _1 = put_contract_data(const Val(11022_u64), const Val(1_u64), const StorageType::Persistent) -> [return: bb1, unwind unreachable];
    }

    bb1: {
        _0 = const Val(2_u64);
        return;
    }
}
```

`--rust` emits Rust from that MIR, structured with rustc's own analyses over
the body: reverse postorder, dominators, predecessors. A block two edges reach
sits after its immediate dominator in a labelled block, so a jump to it is
`break 'b`; a loop header is `'l: loop { .. }`, its back edges `continue 'l`,
the merge nodes of its body inside the loop and its exits after; every other
block is written inline where its one predecessor branches. A jump that is the
last thing before its target falls through, and a label nothing jumps to is
not written. Every local is declared once and assigned where MIR assigns it,
and rustc's definite-initialisation check confirms what MIR's borrow check
established. Constants print through `const fn` constructors in the prelude
(`Val::sym("persisted")`, `Val::u32(2)`, `Val::error(0, 1)`), so the encoding
is written once and rustc checks it; a `u64` local whose every use is a
`Val(..)` construction is typed `Val` too -- the consumer decides, as it does
for a host-call argument -- which is how a phi merging `Symbol("a")` and
`Error(Contract, 1)` reads. `pick`, from `three_bugs.rs`:

```rust
pub fn pick(mut a0: Val) -> Val {
    unsafe {
        let mut arg_payload: u64;
        let mut cmp: bool;
        let mut and: u64;
        let mut cmp2_not: bool;
        let mut or_cond: bool;
        let mut lshr: u64;
        let mut _8: u8;
        let mut brif_not: Val;
        let mut to_val: Val;
        arg_payload = a0.0;
        cmp = arg_payload < 21474836480u64;
        and = arg_payload & 255u64;
        cmp2_not = and == 4u64;
        or_cond = cmp & cmp2_not;
        if or_cond {
            lshr = arg_payload.wrapping_shr(32u64 as u32);
            _8 = lshr as u8;
            match _8 {
                0 => { brif_not = Val::sym("a"); }
                1 => { brif_not = Val::error(0, 1); }
                2 => { f37(); trap(); }
                3 => { f50(); }
                _ => { brif_not = Val::sym("e"); }
            }
            to_val = brif_not;
            return to_val;
        } else {
            trap();
        }
    }
}
```

    ponytail-wasm contract.wasm --inline > contract.inline.ll
    cd ponytail-mir && cargo run --release -- ../contract.inline.ll          # MIR
    cd ponytail-mir && cargo run --release -- ../contract.inline.ll --rust   # Rust, from the MIR

Across the corpus below: 67 of 67 binaries, 1568 functions, build MIR that
rustc accepts without a diagnostic and emit Rust that stable rustc accepts,
all of it structured (47 s in total). Handing the passes to rustc instead of
running a hand-picked subset cut the Rust by 15%, the locals by 20% and the
labels by 78%, and left no raw `Val(n)` literal in 3894 constants. A function
whose control flow the structurer cannot place -- a jump into a region from
outside it, which would mean an irreducible graph -- is emitted as a
`loop { match __bb }` state machine with a comment saying so; the corpus has
none.

What still reads as machine output: the two frames of `read` are `[u64; 2]`
locals written through raw pointers, because the SDK builds the map's value
array and the vec's element array in memory and hands the host their
addresses; and `llvm.*` intrinsics (`memset`, `bswap`, `fshl`, 15 call sites
in the corpus) are typed `extern "C"` declarations rather than `core::ptr` and
`u64` methods.

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

67 binaries, 201 runs (three modes), all verify, 7 seconds in total.

In exports mode 678 of the 716 export returns carry a value; 38 are bottom.
A bottom return means the returned value is one the model does not carry: a
`select`, a load through a pointer, or the result of a typed `block`/`if`,
which the operand stack does not thread across `end` (549 such labels in the
corpus). No `exit` block survives in any output, so a conditional `br_if` to
the function's own label -- the one return shape still lowered as bottom --
does not occur here.

In `--inline` mode 526 host calls carry a decoded linear-memory argument
(`%Symbol_...`, `%Vec_...`, `%Map_...`), 801 StorageType literals are named,
and 896 helpers stay outlined because LLVM's cost model left them so.
