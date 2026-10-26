#!/usr/bin/env bash
# Diff the Lean decoder against wasmparser-nostd 0.100.2 on every corpus module.
set -uo pipefail
cd "$(dirname "$0")/.."
O=difftest/target/release/decode_oracle; L=.lake/build/bin/sl
ok=0; bad=0; rej=0
files=("$@"); [ ${#files[@]} -eq 0 ] && files=(corpus/*.wasm)
for f in "${files[@]}"; do
  r=$($O "$f"); l=$($L decode-dump "$f")
  rv=$(head -1 <<<"$r"); lv=$(head -1 <<<"$l")
  if [[ $rv == INVALID* ]]; then
    # invalid modules: Lean must reject at decode or later validation
    [[ $lv == DECODE-ERROR* ]] && { rej=$((rej+1)); continue; }
  fi
  rb=$(tail -n +2 <<<"$r" | grep -v '^custom ' ); lb=$(tail -n +2 <<<"$l" | grep -v '^custom ')
  rc=$(grep '^custom ' <<<"$r" | sort); lc=$(grep '^custom ' <<<"$l" | sort)
  if [[ "$rb" == "$lb" && "$rc" == "$lc" && $lv == DECODED ]]; then ok=$((ok+1)); else
    bad=$((bad+1)); echo "MISMATCH $f ($rv / $lv)"; diff <(echo "$rb") <(echo "$lb") | head -6; fi
done
echo "decode diff: $ok match, $bad mismatch, $rej invalid-rejected"
