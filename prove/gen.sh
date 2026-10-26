#!/usr/bin/env bash
# gen.sh CONTRACT: regenerate the contract's Gen/Model.lean with the current
# `slice --lean model` (input: the .ll named in contracts/CONTRACT/SOURCE, relative to the
# repo root) and check that the locked spec still states against it. Does not re-lock:
# review the model diff, then run lock.sh.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
root=$(cd "$here/.." && pwd)
# a big contract can need a larger expression budget: contracts/CONTRACT/CAP.
SLICE_CAP=$(cat "$cdir/CAP" 2>/dev/null || echo 1500) \
  "$root/target/release/slice" "$root/$(cat "$cdir/SOURCE")" --lean model > "$cdir/Gen/Model.lean"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
assemble "$work"
if out=$(cd "$work" && lake build Spec 2>&1); then echo "$contract: spec states against the model"
else grep -E 'error' <<<"$out" | head -20; echo "$contract: spec no longer elaborates against the model"; exit 1; fi
if [ -f "$cdir/spec.lock" ] && (cd "$here" && sha256sum --quiet -c "$cdir/spec.lock" 2>/dev/null); then
  echo "$contract: unchanged (lock holds)"
else echo "$contract: changed: review, then ./lock.sh $contract, ./tests/run.sh $contract, ./agent.sh $contract"; fi
