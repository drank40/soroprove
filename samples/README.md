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

**Types.** wasm has two scalar types, and on wasm32 a pointer is always `i32`
and a Val always `i64`; `ponytail-wasm` records that on every parameter and
return as a `wasm.type` attribute. `infer.rs` narrows it from the uses, each an
exact constraint: a value turned into an address is a pointer; one wrapped as
a Val is a Val; one at a host-call position takes that position's ABI type
from `env.json`; one handed to another lifted function takes that parameter's
type, and one returned takes the function's return type, solved to a fixpoint
over the call graph. Where the evidence conflicts or is absent the wasm type
stands, as the integer it is. So `f8(i32, i32, i32)`, the SDK's outlined
`storage().set`, comes out as `f8(env: *mut u8, key: *mut u8, val: *mut u8)`
and `f3(i64)` in `errors.wasm` as `f3(a0: Val)`, called `f3(Val::error(0, 1))`.
Across the corpus below, of 3100 lifted parameters 544 are pointers, 1466 Vals,
4 StorageTypes and 1086 integers; 803 returns are Vals. rustc borrow-checks
the MIR built with these types, so a wrong inference is a compile error, never
a silent one.

**The spec.** `contractspecv0` is the one section that names things: the
exported functions' parameters and declared types, and the user-defined
types -- structs with field names, unions with cases, integer and error enums
with values. `ponytail-wasm` decodes it (`stellar-xdr`, protocol 25) and
carries it into the IR: per export, `spec.name`/`spec.type` on each parameter
and a `spec.sig`; module-wide, one named-metadata line per entry. The MIR
stage then names the parameters (`pick(mut f: Val)`, `read(mut a: Val, mut b:
Val)`), puts the declared signature above each export as `/// spec: fn pick(f:
Flag) -> Result<Symbol, Error>`, prints the whole spec as a comment block in
the header, and decodes against it wherever the derivation is exact: a
contract error code with exactly one case of that value (`Val::error(0, 1) /*
Error::AnError */`); the `match` on `(param.0 >> 32) as u8` of a parameter
declared as an integer enum (`3 /* Flag::D */ =>`); a symbol that is exactly
one union's case name (`Val::sym("Pair") /* DataKey::Pair */`); a map built
from linear memory whose key set is exactly one struct's field set, named for
it (`pair_key = map_new_from_linear_memory(..)`, the join `Map{"a", "b"}` ~
`struct PairKey { a, b }`); and a constant stored into a frame whose address
the host is given as a position it reads Vals from, written as the Val it is
(`_27[0] = Val::sym("Pair") /* DataKey::Pair */.0`). `read`'s storage key
thus reads as what the source wrote: `DataKey::Pair(PairKey { a, b })`. Across
the corpus, 65 of 67 binaries carry a spec; 709 of 731 exports get their
declared signature, 723 error codes their name, 114 maps their struct and 147
frame-slot constants their Val.


The lift itself: one basic block per LLVM block, split at calls; phis as copies
in an edge block; `%Val` as the ADT, its constructor an aggregate and its
payload a field projection; a `StorageType` literal an enum variant, a runtime
one a call to `core::intrinsics::transmute` that rustc lowers to its own
`Transmute` cast; a frame a `[u64; N]` local, its word slots array elements
(`_29[1] = arg_payload1`) and its address `&raw mut`; `trunc to i1` the low
bit, since MIR has no int-to-bool cast; LLVM `noreturn` is `-> !`. Anything
without a MIR equivalent is an error, never a guess. From `three_bugs.mir`,
after rustc's passes:

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
not written. A pure single-use temporary is written into its one use, and a
pure statement nothing reads (rustc kept it for its debuginfo name) is not
written. Constants print through `const fn` constructors in the prelude
(`Val::sym("persisted")`, `Val::u32(2)`, `Val::error(0, 1)`), so the encoding
is written once and rustc checks it; `(x << 32) | 4` reads as `Val::u32(x)`,
`x & 0xff == 77` as `== Tag::AddressObject`, and a `u64` local whose every use
is a `Val(..)` construction is typed `Val` -- the consumer decides, as it does
for a host-call argument. `hello`, from `errors.rs`, against the source in
`errors.reference.rs`:

```rust
pub fn hello(mut a0: Val) -> Val {
    unsafe {
        let mut arg_payload: u64;
        let mut lshr: u64;
        let mut l0_0: Val;
        let mut to_val: Val;
        arg_payload = a0.0;
        if (arg_payload < 21474836480u64) & ((arg_payload & 255u64) == Tag::U32Val) {
            lshr = arg_payload.wrapping_shr(32u64 as u32);
            put_contract_data(Val::sym("persisted"), Val::TRUE, StorageType::Persistent);
            match lshr as u32 {
                0 => { l0_0 = Val::sym("hello"); }          // Flag::A => Ok(symbol_short!("hello"))
                1 => { l0_0 = Val::error(0, 1); }           // Flag::B => Err(Error::AnError)
                2 => { f3(Val::error(0, 1)); trap(); }      // Flag::C => panic_with_error!(AnError)
                3 => { f4(); }                              // Flag::D => panic!("an error")
                _ => { f3(Val::error(0, 9)); trap(); }      // Flag::E => panic_with_error!(from_contract_error(9))
            }
            to_val = l0_0;
            return to_val;
        } else {
            trap();
        }
    }
}
fn f3(mut a0: Val) { unsafe { fail_with_error(a0); return; } }
fn f4() -> ! { unsafe { trap(); } }
```

    ponytail-wasm contract.wasm --inline > contract.inline.ll
    cd ponytail-mir && cargo run --release -- ../contract.inline.ll          # MIR
    cd ponytail-mir && cargo run --release -- ../contract.inline.ll --rust   # Rust, from the MIR

Across the corpus below: 67 of 67 binaries, 1568 functions, build MIR that
rustc accepts without a diagnostic and emit Rust that stable rustc accepts,
all of it structured (57 s in total). Against the first MIR pipeline, which
ran a hand-picked subset of passes and printed every temporary: Rust lines
326k -> 149k, locals 122k -> 32k, labels 4553 -> 1016, raw `Val(n)` literals
3222 -> 0, and 1607 tag checks named. A function whose control flow the
structurer cannot place -- a jump into a region from outside it, which would
mean an irreducible graph -- is emitted as a `loop { match __bb }` state
machine with a comment saying so; the corpus has none.

**Frames and storage.** A frame the host is handed as a position it reads
Vals from (`vec_new_from_linear_memory`, the values of `map_new_..`) is a Val
array, and when every slot is stored exactly once in the block of the one call
that takes it, with every pointer derived from it flowing into that call and
nowhere else, it is written as the literal at the call. Frame words are array
elements otherwise. The linear-memory imports are then the SDK constructors
they implement, with the data as the literals the source had: `Val::vec(&[..])`
for `Vec::from_array`, `Val::map(&["a", "b"], &[..])` for a struct,
`Val::symbol("..")` and `Val::string("..")` with the text read from the data
section, and a lifted helper that builds a symbol from two of its parameters
is `Symbol::new` taking a `&str`. Each is defined in the header as the host
call it is: the host reads the same bytes. `read`'s key thus reads as the
source wrote it:

```rust
pair_key = Val::map(&["a", "b"], &[a, b]); // PairKey { a, b }
vec_new_from_linear_memory_21 = Val::vec(&[Val::sym("Pair") /* DataKey::Pair */, pair_key]); // DataKey::Pair(PairKey { a, b })
has_contract_data_23 = has_contract_data(vec_new_from_linear_memory_21, StorageType::Persistent);
```

Every `put/get/has/del/extend_ttl_contract_data` call site is then collected
into the contract's storage schema, in the header: durability, the key in the
contract's terms, and the operations and functions that use it. Two passes
over the functions make it interprocedural: a helper's returned shape, with
its parameters as placeholders, is substituted at each call (`lc = f42(..) //
BackstopDataKey::UserBalance(PoolUserKey { pool, user })`); a helper that uses
a parameter as a key reports the access at its callers (`has: deposit via
f45`); a symbol whose text position is constant only in a caller is read from
the data itself, which `ponytail-wasm` passes along as `soroban.rodata`. The
spec gives the names, the uses give the roles and the keys the spec never
had:

```
// storage, from every put/get/has/del/extend_ttl call: durability, key, uses.
//   persistent  DataKey::Pair(PairKey { a, b })   [has: read]
//   persistent  Val::sym("f")   [put(Val::TRUE): set_flag]
```

and, from blend's backstop on mainnet, `instance Symbol("BToken") [put(..):
__constructor, has: deposit via f45, get: deposit via f45, ..]` and
`persistent BackstopDataKey::UserBalance(PoolUserKey { pool, user }) [has:
f66, get: f66, extend_ttl: f66, ..]`. Making that possible needed the last
piece of the wasm lowering: a typed `block`/`if`/`loop` result now travels
through an entry-block slot, so the key constructors that select their case
with a `br_table` return a value instead of bottom (38 -> 10 bottom returns
across the corpus). Across the corpus, 32 binaries touch storage, 467 access
entries; 109 keys are named after a spec type or a symbol, 316 stay a local
of the function that built them (a value the model does not carry: a load, a
helper's bottom, a computed symbol).


What still reads as machine output: sub-word frame writes
(`*(frame.wrapping_offset(16) as *mut u32) = 29`, a panic `Location`), because
only whole aligned words become array elements; `llvm.*` intrinsics (15 call
sites) as typed `extern "C"` declarations; a pointer parameter's pointee,
whose layout the accesses give (`+0: u64, +8: u64`) but whose name the spec
does not give, since it describes ScVal shapes, not memory; and a storage key
that is a helper's result the shape pass could not follow -- a value loaded
from memory, a symbol computed at run time, a multi-value block -- which the
schema lists as `f66::lc`, the function's own local, rather than as a shape.

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

## SDK fingerprints: `fingerprints/`

A contract is mostly the SDK: conversions, storage internals, panics,
compiler-builtins. The binary says which SDK and rustc built it
(`contractmetav0`: `rssdkver`, `rsver`; `ponytail-wasm x.wasm --sdk` prints
them), and for a given version the SDK's functions are known exactly, so
`fingerprints/gen.sh <sdk-version> [rust-toolchain]` builds the reference
contract in `fingerprints/ref/` against that version with symbol names kept,
lifts it, and writes `<version>.txt` (or `<version>+rustc<ver>.txt`): one line
per SDK/core function -- two fingerprints and the demangled path. The table
lands in `$PONYTAIL_FINGERPRINTS`, else `~/.cache/ponytail-wasm/fingerprints`;
the tables the samples and tests need are checked in here, and are searched
too. Every lift picks the table nearest the binary's version (toolchain match
preferred), names each helper whose fingerprint it knows, stamps the path as
the `sdk.name` attribute, and says what it did in the IR's first line:

```
; sdk 22.0.7 rustc 1.81.0; fingerprints 25.3.2.txt (nearest): 9 of 91 helpers named, 4 by shape
```

Two fingerprints, because the same source does not give the same bytes. The
exact one hashes the code with data addresses normalised and callees replaced
by their own fingerprints, one round deep; it matches only the same build.
The shape one is order-free -- signature, host functions called, constants,
call and loop counts -- and survives what wasm-opt and register allocation do
to a function (`if` for `block/br_if`, values on the stack for locals); it is
trusted only when it names exactly one function. In the Rust, a named helper
is `fn Storage_has_internal(..)` under a `///` line with the full path.

Ceiling: the reference has to leave a function out of line for it to be in
the table, and a `#[contracttype]` derive is the contract's own code, so a
big mainnet contract names ten to twenty of its helpers this way; the rest
are its business logic. A wider reference is a wider table.

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
