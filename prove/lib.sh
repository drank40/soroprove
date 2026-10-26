# Sourced by the scripts: contract selection and the trusted file set.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
contract=${1:?usage: $0 CONTRACT ... (one of: $(ls "$here/contracts" | tr '\n' ' '))}
cdir="$here/contracts/$contract"
[ -d "$cdir" ] || { echo "no contract $contract in $here/contracts"; exit 2; }

# Everything a verdict depends on except the proof, relative to $here.
trusted() {
  echo lean-toolchain lakefile.lean lake-manifest.json Check.lean Spec/Common.lean \
    "contracts/$contract/Gen/Model.lean" "contracts/$contract/Spec/Defs.lean" \
    "contracts/$contract/Spec/Invariants.lean"
}

# Lay out a buildable workspace in $1: shared files plus this contract's model and spec.
assemble() {
  mkdir -p "$1/Gen" "$1/Spec"
  cp "$here"/{lean-toolchain,lakefile.lean,lake-manifest.json,Check.lean} "$1/"
  cp "$here/Spec/Common.lean" "$cdir/Spec/Defs.lean" "$cdir/Spec/Invariants.lean" "$1/Spec/"
  cp "$cdir/Gen/Model.lean" "$1/Gen/"
}
