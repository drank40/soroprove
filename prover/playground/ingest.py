"""Turn an uploaded contract `.wasm` into a playground contract.

    wasm ──stellar-diver --inline──▶ LLVM IR ──slice --storage-schema──▶ storage interface
                                             ──slice --lean model──▶ StellarLean/Uploads/<Name>.lean
                                                                    (untouched, built with lake)
                                                                 ──▶ playground/uploads.json

Uploads stay out of the tracked files: the model under StellarLean/Uploads/, the inputs
under uploads/<Name>/, the contract's blocks in playground/uploads.json (merged into the
vocabulary by server.py).
"""

import hashlib
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
# The lifter: `lifter/` next to `prover/` in the soroprove repository (or $DIVER_HOME).
DIVER = pathlib.Path(os.environ.get("DIVER_HOME", ROOT.parent / "lifter"))
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


def slice_sha256():
    return hashlib.sha256((DIVER / "target/release/slice").read_bytes()).hexdigest()


def cached(sha):
    """A contract already modelled from these exact bytes: a built-in model (shipped with the
    editor, whatever emitter it came from), or an earlier upload modelled by the current
    emitter. `None` when the wasm needs modelling."""
    src = (HERE / "vocab.js").read_text()
    builtin = json.loads(src[src.index("{"):src.rindex("}") + 1])["contracts"]
    for key, C in builtin.items():
        prov = (ROOT / C["source"]).with_suffix(".json")
        if C.get("kind") == "diver" and prov.exists() and json.loads(prov.read_text()).get("wasm_sha256") == sha:
            return {"key": key, "title": C["title"], "steps": [], "cached": "built-in"}
    current = slice_sha256()
    for key, C in uploaded_contracts().items():
        p = C.get("provenance", {})
        if p.get("wasm_sha256") == sha and p.get("slice_sha256") == current and (ROOT / C["source"]).exists():
            return {"key": key, "title": C["title"], "steps": [], "cached": "upload"}
    return None


def ingest(filename, data, fresh=False):
    """Returns {key, title, steps: [{step, ok, seconds, log}], cached?}; raises ValueError with
    the steps so far when one fails. The same bytes are modelled once (see `cached`), unless
    `fresh`."""
    if len(data) > MAX_WASM:
        raise ValueError(f"the file is larger than {MAX_WASM >> 20} MB")
    if data[:4] != b"\0asm":
        raise ValueError("not a WebAssembly module (it does not start with \\0asm)")
    sha = hashlib.sha256(data).hexdigest()
    if not fresh and (hit := cached(sha)):
        return hit
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
        if not fresh and (hit := cached(sha)):   # modelled while we waited for the lock
            return hit
        with open(ll, "w") as out:
            run("lift the wasm to LLVM IR (stellar-diver)", [str(DIVER / "target/release/stellar-diver"), str(wasm), "--inline"], stdout=out)
        run("recover the storage interface (slice --storage-schema)", [str(DIVER / "target/release/slice"), str(ll), "--storage-schema"])
        schema = ll.with_suffix(".storage.json")
        cmd = [sys.executable, str(ROOT / "scripts/import_diver.py"), str(ll), name, key, "--dir", "Uploads",
               "--vocab", str(UPLOADS), "--title", f"{stem} (uploaded, stellar-diver model)", "--wasm", str(wasm)]
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
