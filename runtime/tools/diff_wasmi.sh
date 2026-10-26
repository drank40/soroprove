#!/usr/bin/env bash
# Differential test: Lean interpreter vs real soroban-wasmi 29.0.0 (Soroban config)
# on every spec testsuite invocation: outcome + cumulative fuel consumed.
set -uo pipefail
cd "$(dirname "$0")/.."
tot=0; bad=0
for d in .lake/spectest/*/; do
  t=$(basename $d); j=$d/$t.json; [ -f $j ] || continue
  r=$(difftest/target/release/spec_oracle $d $j 2>/dev/null)
  l=$(.lake/build/bin/sl spectest-fuel $d $j 2>/dev/null)
  rn="$r"; ln="$l"
  n=$(wc -l <<<"$rn"); tot=$((tot+n))
  d2=$(diff <(echo "$rn") <(echo "$ln"))
  if [ -n "$d2" ]; then c=$(grep -c '^<' <<<"$d2"); bad=$((bad+c)); echo "== $t: $c differing"; head -6 <<<"$d2"; fi
done
echo "wasmi diff: $tot invocations, $bad differing"
