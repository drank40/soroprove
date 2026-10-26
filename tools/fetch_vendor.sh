#!/usr/bin/env bash
# Fetch the pinned sources the model is transcribed from (see PLAN.md).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p vendor/crates && cd vendor
clone() { [ -d "$2" ] || git clone -q --depth 1 --branch "$3" "$1" "$2"; (cd "$2" && echo "$2 $(git rev-parse --short HEAD)"); }
clone https://github.com/stellar/rs-soroban-env rs-soroban-env v30.0.0
clone https://github.com/stellar/rs-soroban-sdk rs-soroban-sdk v29.0.1
[ -d soroban-examples ] || { git clone -q https://github.com/stellar/soroban-examples && git -C soroban-examples checkout -q 03d42aa; }
[ -d wasm-testsuite ] || { git clone -q --depth 1 https://github.com/WebAssembly/testsuite wasm-testsuite && git -C wasm-testsuite fetch -q --shallow-since=2023-01-01 origin; git -C wasm-testsuite checkout -q 7ef86dd; }
crate() {
  local n=$1 v=$2 sum=$3
  [ -d "crates/$n-$v" ] && return
  curl -sSfL "https://static.crates.io/crates/$n/$n-$v.crate" -o "$n.crate"
  echo "$sum  $n.crate" | sha256sum -c --quiet
  tar -xzf "$n.crate" -C crates && rm "$n.crate"
}
crate soroban-wasmi 29.0.0 7c0a869066f1f4718289c1d5fb2a7ed0f459a15a5df176b7083babc01814962c
crate wasmi_core 0.13.0 $(awk '$0=="name = \"wasmi_core\""{getline;getline;getline;print $3;exit}' rs-soroban-env/Cargo.lock | tr -d '"')
crate wasmi_arena 0.4.1 $(awk '$0=="name = \"wasmi_arena\""{getline;getline;getline;print $3;exit}' rs-soroban-env/Cargo.lock | tr -d '"')
crate wasmparser-nostd 0.100.2 d5a015fe95f3504a94bb1462c717aae75253e39b9dd6c3fb1062c934535c64aa
crate stellar-xdr 30.0.0 56f2fb2008b42fc746c0f6b46e375600068dd91f07748e9f1737c6341a2255f2
echo ok
