#!/bin/sh
# Compile a reconstructed contract against its own soroban-sdk version, to
# check that `--contract` output is real, buildable source. The corpus gate
# only type-checks the `--rust` (Val-level) output; this checks the contract.
#
#   ./samples/verify-contract.sh <contract.wasm> [sdk-version]
#
# The sdk version defaults to what the binary's contractmetav0 records. The
# reconstructed contract's own header also prints its inferred dependencies;
# add those to the crate below to build a contract that uses them.
set -eu
cd "$(dirname "$0")/.."
wasm=${1:?usage: verify-contract.sh <contract.wasm> [sdk-version]}
WASM=./target/release/stellar-diver
MIR=./mir
sdk=${2:-$($WASM "$wasm" --sdk | awk '{print $1}')}
work=$(mktemp -d)
mkdir -p "$work/src"
cat > "$work/Cargo.toml" <<EOF
[package]
name = "reconstructed"
version = "0.0.0"
edition = "2021"
[lib]
crate-type = ["cdylib"]
[dependencies]
soroban-sdk = "=$sdk"
[profile.release]
opt-level = "z"
overflow-checks = true
panic = "abort"
[workspace]
EOF
$WASM "$wasm" --inline 2>/dev/null > "$work/c.ll"
(cd "$MIR" && cargo run --release -q -- "$work/c.ll" --contract) > "$work/src/lib.rs" 2>/dev/null
echo "sdk $sdk; $(grep -c '^    pub fn ' "$work/src/lib.rs") exports, $(grep -c 'todo!' "$work/src/lib.rs") todo"
if (cd "$work" && cargo build --release --target wasm32v1-none 2>"$work/err"); then
    echo "COMPILES: $(basename "$wasm")"
else
    echo "FAILS: $(basename "$wasm")"; grep -E '^error' "$work/err" | head
fi
