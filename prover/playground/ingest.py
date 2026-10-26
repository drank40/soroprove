"""Turn an uploaded contract `.wasm` into a playground contract.

    wasm ──stellar-diver --inline──▶ LLVM IR ──slice --storage-schema──▶ storage interface
                                             ──slice --lean model──▶ StellarLean/Uploads/<Name>.lean
                                                                    (untouched, built with lake)
                                                                 ──▶ playground/uploads.json

Uploads stay out of the tracked files: the model under StellarLean/Uploads/, the inputs
under uploads/<Name>/, the contract's blocks in playground/uploads.json (merged into the
vocabulary by server.py).
"""

import json
import os
import pathlib
import re
import subprocess
import sys
import threading
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
DIVER = pathlib.Path(os.environ.get("DIVER_HOME", pathlib.Path.home() / "doc/work/stellar/stellar-diver"))
UPLOADS = HERE / "uploads.json"
MAX_WASM = 4 << 20
LOCK = threading.Lock()   # one ingestion at a time (lake, uploads.json)


def names(filename):
    """`soroban_liquidity_pool_contract.wasm` → ("SorobanLiquidityPoolContract",
    "up_soroban_liquidity_pool_contract", "soroban_liquidity_pool_contract")."""
    stem = re.sub(r"\.wasm$", "", pathlib.Path(filename or "contract").name, flags=re.I)
    words = re.findall(r"[A-Za-z0-9]+", stem) or ["contract"]
    name = "".join(w[:1].upper() + w[1:] for w in words)
    if name[0].isdigit():
        name = "C" + name
    return name[:60], "up_" + "_".join(w.lower() for w in words)[:60], stem


def ingest(filename, data):
    """Returns {key, title, steps: [{step, ok, seconds, log}]}; raises ValueError with the
    steps so far when one fails."""
    if len(data) > MAX_WASM:
        raise ValueError(f"the file is larger than {MAX_WASM >> 20} MB")
    if data[:4] != b"\0asm":
        raise ValueError("not a WebAssembly module (it does not start with \\0asm)")
    name, key, stem = names(filename)
    work = ROOT / "uploads" / name
    work.mkdir(parents=True, exist_ok=True)
    wasm, ll = work / "contract.wasm", work / "contract.ll"
    wasm.write_bytes(data)
    steps = []

    def run(step, cmd, stdout=None, timeout=300):
        t0 = time.time()
        try:
            p = subprocess.run(cmd, cwd=ROOT, capture_output=stdout is None, timeout=timeout,
                               stdout=stdout, stderr=subprocess.PIPE if stdout is not None else None, text=True)
            ok, log = p.returncode == 0, ((p.stdout or "") if stdout is None else "") + (p.stderr or "")
        except subprocess.TimeoutExpired:
            ok, log = False, f"timed out after {timeout}s"
        steps.append({"step": step, "ok": ok, "seconds": round(time.time() - t0, 1), "log": log[-4000:]})
        if not ok:
            raise IngestError(f"{step} failed", steps)

    with LOCK:
        with open(ll, "w") as out:
            run("lift the wasm to LLVM IR (stellar-diver)", [str(DIVER / "target/release/stellar-diver"), str(wasm), "--inline"], stdout=out)
        run("recover the storage interface (slice --storage-schema)", [str(DIVER / "target/release/slice"), str(ll), "--storage-schema"])
        schema = ll.with_suffix(".storage.json")
        cmd = [sys.executable, str(ROOT / "scripts/import_diver.py"), str(ll), name, key, "--dir", "Uploads",
               "--vocab", str(UPLOADS), "--title", f"{stem} (uploaded, stellar-diver model)"]
        if schema.exists():
            cmd += ["--storage", str(schema)]
        run("emit the Lean model (slice --lean model) and build it", cmd, timeout=900)
    return {"key": key, "title": f"{stem} (uploaded, stellar-diver model)", "steps": steps}


class IngestError(ValueError):
    def __init__(self, msg, steps):
        super().__init__(msg)
        self.steps = steps


def uploaded_contracts():
    try:
        return json.loads(UPLOADS.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}
