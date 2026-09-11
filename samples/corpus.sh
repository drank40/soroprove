#!/bin/sh
# The corpus gate, in one run: lift every binary, build the MIR and the Rust,
# type-check the Rust with stable rustc, generate the contract, and print the
# numbers HANDOFF.md tracks. Run inside nix-shell (LLVM), after both crates
# are built in release.
#
#   ./samples/corpus.sh <soroban-ret checkout> [out dir]
#
# The corpus is soroban-ret's benchmark-data/mainnet (24 mainnet contracts)
# and tests/fixtures (43 SDK fixtures), plus the three vendored samples. Not
# vendored here; clone https://github.com/Inferara/soroban-ret.
set -u
root=${1:?usage: corpus.sh <soroban-ret checkout> [out dir]}
out=${2:-$(mktemp -d)}
cd "$(dirname "$0")/.."
WASM=./target/release/stellar-diver
MIR=./mir/target/release/stellar-diver-mir
[ -x "$WASM" ] && [ -x "$MIR" ] || { echo "build both crates first (cargo build --release; cd mir && cargo build --release)" >&2; exit 2; }

lifted=0; lift_fail=0
# samples/errors.wasm and samples/test_udt.wasm are fixtures of that corpus already.
for w in "$root"/benchmark-data/mainnet/*.wasm "$root"/tests/fixtures/*.wasm samples/three_bugs.wasm; do
    b=$(basename "$w" .wasm)
    if $WASM "$w" --inline > "$out/$b--inline.ll" 2> "$out/$b.lift.err"; then lifted=$((lifted + 1)); else lift_fail=$((lift_fail + 1)); echo "LIFT-FAIL $b: $(head -1 "$out/$b.lift.err")"; fi
done
echo "lifted $lifted, failed $lift_fail; bottoms (calls to diver.unknown): $(cat "$out"/*.ll | grep -c 'call .*@diver.unknown')"
echo "helpers named by SDK fingerprints: $(grep -h '^; sdk' "$out"/*.ll | sed -E 's/.*: ([0-9]+) of ([0-9]+) helpers named.*/\1 \2/' | awk '{n+=$1; t+=$2} END {print n" of "t}')"

ok=0; fail=0
for ll in "$out"/*--inline.ll; do
    b=$(basename "$ll" --inline.ll)
    # cargo run, not the binary: librustc_driver is found through the toolchain.
    if ! (cd mir && timeout 300 cargo run --release -q -- "$ll" --rust) > "$out/$b.rs" 2> "$out/$b.err"; then fail=$((fail + 1)); echo "RS-FAIL $b: $(grep -m1 -E 'stellar-diver-mir:|^error|panicked' "$out/$b.err" | cut -c1-160)"; continue; fi
    if timeout 120 rustc --crate-type lib --edition 2021 --emit metadata -o "$out/$b.rmeta" "$out/$b.rs" 2> "$out/$b.tc.err"; then ok=$((ok + 1)); else fail=$((fail + 1)); echo "TYPECHECK-FAIL $b: $(grep -m1 '^error' "$out/$b.tc.err" | cut -c1-160)"; fi
    (cd mir && timeout 300 cargo run --release -q -- "$ll" --contract) > "$out/$b.contract.rs" 2>/dev/null || echo "CONTRACT-FAIL $b"
done
echo "rust: $ok type-check, $fail failed; functions stellar-diver-mir dropped: $(cat "$out"/*.err | grep -c 'stellar-diver-mir:')"
rows=$(cat "$out"/*.rs | grep -cE '^//   (persistent|instance|temporary|\?)')
alts=$(cat "$out"/*.rs | grep -cE '^//   (persistent|instance|temporary|\?) +.*(::\{| \| )')
locals=$(cat "$out"/*.rs | grep -cE '^//   (persistent|instance|temporary|\?) +[A-Za-z_0-9]+::[a-z_][a-z_0-9]* ')
echo "storage rows $rows: $alts with alternatives, $locals keyed by an unresolved local"
one=$(cat "$out"/*.rs | grep -oE '= [A-Za-z0-9_]+_into_val[_0-9]*\([^)]*\); // [^ ]+' | grep -vc '::{')
many=$(cat "$out"/*.rs | grep -oE '= [A-Za-z0-9_]+_into_val[_0-9]*\([^)]*\); // [^ ]+' | grep -c '::{')
echo "derives named: $(cat "$out"/*.rs | grep -cE '^fn [A-Za-z0-9]+_(into_val|try_from_val)'); into_val calls resolved to one case: $one, left as alternatives: $many"
exports=$(cat "$out"/*.contract.rs | grep -cE '^    pub fn ')
partial=$(cat "$out"/*.contract.rs | awk '/^    pub fn /{bad=0} /not reconstructed:/{if(!bad){b++; bad=1}} END{print b+0}')
echo "contract exports $exports, reconstructed whole $((exports - partial)); statements left at the Val level: $(cat "$out"/*.contract.rs | grep -c 'not reconstructed:'); blockers:"
cat "$out"/*.contract.rs | grep -oE 'not reconstructed: [a-z ]+' | sort | uniq -c | sort -rn | head -6
echo "outputs in $out"
