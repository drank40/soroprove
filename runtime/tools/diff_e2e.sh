#!/usr/bin/env bash
# Diff the Lean model's invoke_host_function against the real host on every recorded
# end-to-end run: budget charge traces (in order) and all outputs.
set -uo pipefail
cd "$(dirname "$0")/.."
L=.lake/build/bin/sl; SET=vendor/network/mainnet_settings.xdr; T=$(mktemp -d)
ok=0; bad=0
check() {  # corpus-file trace-file tag
  local f=$1 tr=$2 t=$3
  $L e2e-trace $SET "$f" "$t" > "$T/$t"
  if diff <(grep CHARGE "$T/$t") "$tr" >/dev/null && diff <(grep "^$t output\|^$t tracker" "$f") <(grep -v CHARGE "$T/$t") >/dev/null; then
    ok=$((ok+1)); echo "$t: identical ($(grep -c CHARGE "$T/$t") charges)"
  else bad=$((bad+1)); echo "$t: DIFFERS"; fi
}
for t in call0 call1 call2; do check corpus/e2e_increment.txt difftest-trace/$t.trace $t; done
for t in mint transfer overdraft balance_a balance_b; do check corpus/e2e_token.txt corpus/token-trace/$t.trace $t; done
echo "e2e diff: $ok identical, $bad differing"
rm -rf "$T"
