#!/usr/bin/env bash
# The honest solution must pass; every cheat must be rejected.
cd "$(dirname "$0")/.." || exit 1
fail=0
if ./verify.sh tests/honest/Solution.lean >/dev/null 2>&1; then echo "pass  honest"; else echo "FAIL  honest rejected"; fail=1; fi
for f in tests/cheats/*.lean; do
  if out=$(./verify.sh "$f" 2>&1); then echo "FAIL  $(basename "$f") accepted"; fail=1
  else echo "pass  $(basename "$f"): $(grep -m1 REJECT <<<"$out")"; fi
done
exit $fail
