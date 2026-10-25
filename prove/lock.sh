#!/usr/bin/env bash
# Re-lock the trusted tree after a reviewed change to the model, spec or checker.
cd "$(dirname "$0")" && sha256sum lean-toolchain lakefile.lean Check.lean Gen/*.lean Spec/*.lean > spec.lock
