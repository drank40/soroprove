#!/bin/sh
# Rebuild the sample contracts and regenerate the checked-in .ll goldens.
#
# The goldens are the regression gate: run this, then `git diff samples/` shows
# exactly what a change to the lowering did. That is the whole point of pinning
# the toolchain in ../rust-toolchain.toml -- a codegen change should be a diff,
# not noise.
#
# THE ONE THING THAT WILL BITE YOU: soroban-sdk's major version selects the
# protocol stamped into `contractenvmetav0`, and a host rejects any contract
# whose protocol is newer than its own ("contract protocol number is newer than
# host", vm/parsed_module.rs). rs-soroban-env 25.2.1 is protocol 25, so the
# samples pin `soroban-sdk = "25"`. Bump both together.
#
# `stellar contract build` is equivalent (cargo plus a metadata stamp) but not
# required. On this NixOS box the cargo-installed CLI needs a newer libstdc++
# than nix-ld ships:
#   LD_LIBRARY_PATH=$(nix build nixpkgs#gcc14.cc.lib --no-link --print-out-paths)/lib stellar ...
set -eu
cd "$(dirname "$0")"

BIN=../target/release/ponytail-wasm
[ -x "$BIN" ] || { echo "build ponytail-wasm first: nix-shell --run 'cargo build --release'" >&2; exit 2; }
# The SDK fingerprint tables checked in next door, so the goldens name the
# same helpers on every machine (see ../fingerprints/gen.sh).
export PONYTAIL_FINGERPRINTS="$PWD/../fingerprints"

# `release` is the profile real contracts ship with. `fat` inlines more, which
# produces genuinely different codegen for the same source -- useful corpus
# diversity for a tool whose whole risk is being tuned to one compiler shape.
for prof in release fat; do
    (cd three_bugs && cargo build --profile "$prof" --target wasm32v1-none)
done
cp three_bugs/target/wasm32v1-none/release/three_bugs.wasm three_bugs.wasm
cp three_bugs/target/wasm32v1-none/fat/three_bugs.wasm     three_bugs-fat.wasm

# Goldens, one pipeline: every function as lowered (--all); the exports with
# the SDK plumbing inlined and folded by LLVM (--inline); then, from that IR,
# the MIR ponytail-mir builds inside rustc (.mir) and the Rust it emits from
# the MIR (.rs). The last two need ../ponytail-mir's nightly with rustc-dev.
for w in *.wasm; do
    "$BIN" "$w" --all    > "${w%.wasm}.ll"
    "$BIN" "$w" --inline > "${w%.wasm}.inline.ll"
    printf '%-22s %6s bytes wasm -> %5s lines IR, %4s inlined\n' "$w" "$(stat -c%s "$w")" \
        "$(wc -l < "${w%.wasm}.ll")" "$(wc -l < "${w%.wasm}.inline.ll")"
done
if (cd ../ponytail-mir && cargo build --release -q 2>/dev/null); then
    for ll in *.inline.ll; do
        b=${ll%.inline.ll}
        (cd ../ponytail-mir && cargo run --release -q -- "../samples/$ll")        > "$b.mir" 2>/dev/null
        (cd ../ponytail-mir && cargo run --release -q -- "../samples/$ll" --rust) > "$b.rs"  2>/dev/null
        printf '%-22s -> %5s lines MIR, %4s lines Rust\n' "$ll" "$(wc -l < "$b.mir")" "$(wc -l < "$b.rs")"
    done
else
    echo "ponytail-mir did not build (nightly with rustc-dev missing?); .mir/.rs goldens left as they were" >&2
fi
