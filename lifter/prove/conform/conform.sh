#!/usr/bin/env bash
# conform.sh CONTRACT ORACLE_OUTPUT: check that every real call recorded by an oracle
# run is a step the contract's emitted model admits (see Conform.lean).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
c=${1:?usage: conform.sh CONTRACT ORACLE_OUTPUT}; data=$(realpath "${2:?}")
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Gen"
cp "$here/../contracts/$c/Gen/Model.lean" "$work/Gen/"
cp "$here/Conform.lean" "$here/../lean-toolchain" "$work/"
cat > "$work/lakefile.lean" <<'LAKE'
import Lake
open Lake DSL
package conform
lean_lib Gen where globs := #[.submodules `Gen]
lean_exe conform where
  root := `Conform
  supportInterpreter := true
LAKE
cd "$work" && lake build -q conform 2>&1 | grep -E 'error' -A5 && exit 1
lake exe conform "$data"
