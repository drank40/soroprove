#!/bin/sh
# Fingerprints for one soroban-sdk version: build the reference contract
# against it with symbol names kept, lift it, keep every SDK/core function
# under its real name. The table lands in the cache ponytail-wasm reads
# ($PONYTAIL_FINGERPRINTS, default ~/.cache/ponytail-wasm/fingerprints).
#
#   ponytail-wasm contract.wasm --sdk        # -> "22.0.7 1.81.0": sdk, rustc
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
out=${PONYTAIL_FINGERPRINTS:-$HOME/.cache/ponytail-wasm/fingerprints}
bin=${PONYTAIL_WASM:-$here/../target/release/ponytail-wasm}
target=${TARGET:-wasm32v1-none}
[ -x "$bin" ] || { echo "gen.sh: build ponytail-wasm first (cargo build --release), or set PONYTAIL_WASM" >&2; exit 2; }

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
"$bin" "$build/target/$target/release/ponytail_ref.wasm" --fingerprints > "$file"
echo "$file: $(grep -vc '^#' "$file") functions"
