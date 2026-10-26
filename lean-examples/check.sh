#!/usr/bin/env bash
# Regenerate each model from its lifted IR, append its proofs (if any), and
# typecheck with Lean. Usage: lean-examples/check.sh   (from the repo root)
set -u
cd "$(dirname "$0")"
SLICE=../target/release/slice
LEAN=${LEAN:-$HOME/.elan/bin/lean}
tmp=$(mktemp -d)
status=0
for ll in *.ll; do
  n=${ll%.ll}
  "$SLICE" "$ll" --lean model > "$n.lean" 2>/dev/null || { echo "$n: slice failed"; status=1; continue; }
  f="$tmp/$n.lean"
  cp "$n.lean" "$f"
  [ -f "proofs/$n.lean" ] && cat "proofs/$n.lean" >> "$f"
  if out=$("$LEAN" "$f" 2>&1) && ! grep -q ': error' <<<"$out"; then
    printf "%-15s ok   (%s theorems)\n" "$n" "$(grep -c '^theorem' "$f")"
  else
    printf "%-15s FAIL\n" "$n"; grep ': error' -A3 <<<"$out" | head -12; status=1
  fi
done
exit $status
