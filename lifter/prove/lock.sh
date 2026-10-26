#!/usr/bin/env bash
# lock.sh CONTRACT: re-lock after a reviewed change to the model, spec or checker.
source "$(dirname "$0")/lib.sh"
cd "$here" && sha256sum $(trusted) > "$cdir/spec.lock"
