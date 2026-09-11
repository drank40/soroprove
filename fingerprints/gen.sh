#!/bin/sh
# Fingerprints for one soroban-sdk version: build the reference contract
# against it with symbol names kept, lift it, keep every SDK/core function
# under its real name. The table lands in the cache stellar-diver reads
# ($DIVER_FINGERPRINTS, default ~/.cache/stellar-diver/fingerprints).
#
#   stellar-diver contract.wasm --sdk        # -> "22.0.7 1.81.0": sdk, rustc
#   fingerprints/gen.sh 22.0.7               # this toolchain
#   fingerprints/gen.sh 22.0.7 1.81.0        # a rustup toolchain, for an exact match
#
# Versions this machine has not built before need the network (cargo fetches
# that soroban-sdk); a toolchain given as the second argument must be
# installed (rustup toolchain install 1.81.0 --target wasm32v1-none).
set -eu
ver=${1:?usage: gen.sh <soroban-sdk version> [rust toolchain]}
tc=${2:-}
here=$(cd "$(dirname "$0")" && pwd)
out=${DIVER_FINGERPRINTS:-$HOME/.cache/stellar-diver/fingerprints}
bin=${DIVER_WASM:-$here/../target/release/stellar-diver}
target=${TARGET:-wasm32v1-none}
[ -x "$bin" ] || { echo "gen.sh: build stellar-diver first (cargo build --release), or set DIVER_WASM" >&2; exit 2; }

# The build tree stays in the cache: a second run for the same version is incremental.
build="$out/build/$ver${tc:++rustc$tc}"
mkdir -p "$build"
cp -r "$here/ref/." "$build"
sed -i "s/^soroban-sdk = .*/soroban-sdk = \"=$ver\"/" "$build/Cargo.toml"
# rustup's cargo, not whatever shell wraps this one: the wasm target is rustup's.
rustup=${RUSTUP:-$(command -v rustup || echo "$HOME/.cargo/bin/rustup")}
(cd "$build" && "$rustup" run "${tc:-stable}" cargo build --release --target "$target")

mkdir -p "$out"
file="$out/$ver${tc:++rustc$tc}.txt"
"$bin" "$build/target/$target/release/diver_ref.wasm" --fingerprints > "$file"
echo "$file: $(grep -vc '^#' "$file") functions"
