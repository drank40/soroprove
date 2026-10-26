#!/usr/bin/env bash
# tests/run.sh [CONTRACT...]: per contract, the reference proof must settle every locked
# theorem (proved, or disproved by a counterexample), and every cheat must be rejected for
# the expected reason. Cheats are derived from the contract's locked spec.
cd "$(dirname "$0")/.." || exit 1
[ $# -gt 0 ] && set -- "$@" || set -- $(ls contracts)
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
fail=0

cheat() { # name, expected REJECT substring; file content on stdin
  cat > "$d/$1.lean"; printf '%s\n' "$2" > "$d/$1.expect"; }

for c in "$@"; do
  echo "== $c"
  rm -f "$d"/*
  spec=contracts/$c/Spec/Invariants.lean defs=$(sed '/^import/d' "contracts/$c/Spec/Defs.lean")
  cheat sorry "uses axiom sorryAx" < "$spec"
  perl -pe 's/:= sorry/:= by\n  have : (2:Nat) + 2 = 4 := by native_decide\n  exact sorry/' "$spec" | cheat native_decide "native_decide"
  perl -0pe 's/theorem (\S+) :.*?:= sorry/theorem $1 : True := trivial/s' "$spec" | cheat weaker "statement differs from the locked one"
  # Restate the spec's own definitions (Common and Defs) instead of importing them; only
  # meaningful when the locked statements use one.
  names=$(grep -hoE '^(def|inductive) [A-Za-z_]+' Spec/Common.lean "contracts/$c/Spec/Defs.lean" | awk '{print $2}' | paste -sd'|')
  if [ -n "$names" ] && perl -0pe 's{/-.*?-/}{}gs' "$spec" | grep -qwE "$names"; then
    { echo "import Gen.Model"; sed '/^import/d' Spec/Common.lean; echo "$defs"; sed '/^import/d' "$spec"; } \
      | cheat redefine "which the solution redefines"
  fi
  sed 's/^import Spec.Defs$/import Spec.Invariants/' "$spec" | cheat import_spec "may import only"
  perl -0pe 's/(namespace Locked\n).*(end Locked)/$1$2/s' "$spec" | cheat missing ": missing"
  sed 's/^namespace Locked$/#eval IO.FS.writeFile "Spec\/Invariants.lean" ""\nnamespace Locked/' "$spec" | cheat io_tamper "forbidden command"
  sed 's/^namespace Locked$/set_option debug.skipKernelTC true\nnamespace Locked/' "$spec" | cheat skip_kernel "forbidden command"
  sed 's/^namespace Locked$/axiom cheat : False\nnamespace Locked/; s/:= sorry/:= cheat.elim/' "$spec" | cheat axiom "forbidden command"

  ref=contracts/$c/reference/Solution.lean
  if [ ! -f "$ref" ]; then echo "skip  reference (none yet: run ./agent.sh $c)"
  elif out=$(./verify.sh "$c" "$ref" 2>&1); grep -q REJECT <<<"$out"; then
    echo "FAIL  reference: $(grep -m1 REJECT <<<"$out")"; fail=1
  else echo "pass  reference: $(tail -1 <<<"$out")$(grep -c DISPROVED <<<"$out" | sed 's/^0$//; s/.\+/, & disproved/')"; fi
  for f in "$d"/*.lean; do
    n=$(basename "$f" .lean) want=$(cat "$d/$n.expect")
    if out=$(./verify.sh "$c" "$f" 2>&1); then echo "FAIL  $n accepted"; fail=1
    elif grep -q "REJECT.*$want" <<<"$out"; then echo "pass  $n"
    else echo "FAIL  $n rejected for the wrong reason: $(grep -m1 REJECT <<<"$out")"; fail=1; fi
  done
done
exit $fail
