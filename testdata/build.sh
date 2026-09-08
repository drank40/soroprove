#!/bin/sh
# Build every fixture contract.
#
# Toolchain and wasm targets come from ../rust-toolchain.toml; rustup installs
# any listed target on demand, so a fresh machine needs no extra setup. The
# version is pinned rather than `stable` because fixture wasm has to be
# byte-reproducible -- a codegen change should show up as a diff, not as noise.
#
# THE ONE THING THAT WILL BITE YOU: soroban-sdk's major version selects the
# protocol stamped into `contractenvmetav0`, and a host rejects any contract
# whose protocol is newer than its own ("contract protocol number is newer than
# host", vm/parsed_module.rs). rs-soroban-env 25.2.1 is protocol 25, so the
# fixtures pin `soroban-sdk = "25"`. Bump both together or the host will not
# load what you built.
#
# `stellar contract build` works too and is equivalent (cargo plus a metadata
# stamp), but it is not required. On this NixOS box the cargo-installed CLI
# needs a newer libstdc++ than nix-ld ships:
#   LD_LIBRARY_PATH=$(nix build nixpkgs#gcc14.cc.lib --no-link --print-out-paths)/lib stellar ...
set -eu
cd "$(dirname "$0")"

for m in */Cargo.toml; do
    d=${m%/Cargo.toml}
    printf '=== %s\n' "$d"
    (cd "$d" && cargo build --release --target wasm32v1-none)
done

echo
echo "=== artifacts ==="
ls -l */target/wasm32v1-none/release/*.wasm
