#!/usr/bin/env bash
# Conformance: run each example's real wasm in the Soroban test VM (random
# invocations), then check that the Lean model admits every successful one.
#   lean-examples/conformance/run.sh [soroban-examples dir] [runs]
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
examples="$(cd "${1:-$here/../../../soroban-examples}" && pwd)"
runs="${2:-200}"
SLICE="$here/../../target/release/slice"
LEAN=${LEAN:-$HOME/.elan/bin/lean}
tmp=${KEEP:-$(mktemp -d)}
mkdir -p "$tmp"
(cd "$here" && cargo run --release --offline -q -- "$examples" "$tmp" "$runs")
status=0
for obs in "$tmp"/*.obs.lean; do
  n=$(basename "$obs" .obs.lean)
  f="$tmp/$n.check.lean"
  "$SLICE" "$here/../$n.ll" --lean check > "$f"
  cat "$here/check.lean" "$obs" >> "$f"
  echo '#eval report observations' >> "$f"
  echo "== $n"
  out=$("$LEAN" "$f" 2>&1) || true
  echo "$out" | grep -v '^$' | sed 's/^/  /'
  grep -q 'RESULT ok' <<<"$out" || status=1
done
exit $status
