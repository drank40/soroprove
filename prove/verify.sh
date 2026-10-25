#!/usr/bin/env bash
# verify.sh SOLUTION.lean: check an untrusted proof file against the locked spec.
# Only the given file is taken from the prover; everything else comes from this directory,
# which must match spec.lock. The build runs in a fresh temporary copy.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
sol=$(realpath "$1")

(cd "$here" && sha256sum --quiet -c spec.lock) || { echo "REJECT trusted tree does not match spec.lock"; exit 1; }

# Elaborating a Lean file runs code, so refuse files that can do anything but state and prove.
src=$(perl -0pe 's{/-.*?-/}{}gs; s{--[^\n]*}{}g' "$sol")
if grep -nE '#eval|#exit|run_cmd|run_tac|run_elab|run_meta|\belab\b|elab_rules|\bmacro\b|macro_rules|\bsyntax\b|initialize|implemented_by|\bextern\b|\bunsafe\b|\baxiom\b|debug\.|skipKernel|IO\.' <<<"$src"; then
  echo "REJECT forbidden command in solution"; exit 1
fi
if grep -E '^\s*import\b' <<<"$src" | grep -vqE '^\s*import\s+(Gen\.Model|Spec\.Defs)\s*$'; then
  echo "REJECT solution may import only Gen.Model and Spec.Defs"; exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -r "$here"/{lean-toolchain,lakefile.lean,Check.lean,Gen,Spec} "$work"/
cd "$work"
lake build -q Spec check >/dev/null 2>&1 || { echo "REJECT trusted build failed"; exit 1; }
before=$(find .lake/build -type f | sort | xargs sha256sum)
cp "$sol" Solution.lean
if ! out=$(lake build Solution 2>&1); then echo "$out" | grep -E 'error' | head -20; echo "REJECT solution does not build"; exit 1; fi
[ "$before" = "$(find .lake/build -type f ! -path '*Solution*' | sort | xargs sha256sum)" ] \
  || { echo "REJECT solution build modified trusted artifacts"; exit 1; }
lake exe check
