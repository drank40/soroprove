#!/usr/bin/env bash
# Run the Lean interpreter on the WebAssembly spec testsuite subset relevant to Soroban.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=.lake/spectest; mkdir -p $OUT
TESTS="${*:-i32 i64 int_exprs int_literals address align block br br_if br_table call call_indirect endianness fac forward func func_ptrs global if labels left-to-right load local_get local_set local_tee loop memory memory_grow memory_size memory_redundancy memory_trap nop return select stack store switch traps unreachable unwind binary-leb128 binary custom bulk memory_copy memory_fill memory_init table_copy table_init elem data start exports names skip-stack-guard-page unreached-invalid comments token const}"
tot_p=0; tot_f=0
for t in $TESTS; do
  f=vendor/wasm-testsuite/$t.wast; [ -f $f ] || { echo "missing $t"; continue; }
  d=$OUT/$t; mkdir -p $d
  nix-shell -p wabt --run "wast2json $f -o $d/$t.json" >/dev/null 2>$d/err.txt || { echo "$t: wast2json failed: $(head -c 200 $d/err.txt)"; continue; }
  r=$(.lake/build/bin/sl spectest $d $d/$t.json); echo "$r"
done
