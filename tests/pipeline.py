#!/usr/bin/env python3
"""End to end, through the editor's server, the way the browser drives it:

  1. upload a contract .wasm: lifted, modelled (`slice --lean model`), built;
  2. `answer` proves a per-call property and a cross-transaction invariant of the uploaded
     contract, and refuses a false claim;
  3. the agent sandbox: every way of cheating a proof is rejected by the server's check;
  4. with --vibe, a live Claude agent (the server owner's subscription) refutes a false claim
     about the contract and the server renders the counterexample.

    python3 tests/pipeline.py [--vibe] [--wasm examples/liquidity_pool.wasm]
"""

import argparse
import json
import pathlib
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

TOP = pathlib.Path(__file__).resolve().parent.parent
PLAYGROUND = TOP / "prover/playground"


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def call(base, path, body=None, ctype="application/json", timeout=1200):
    data = body if isinstance(body, bytes) or body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data, {"Content-Type": ctype} if data is not None else {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


# Statements as the editor prints them from blocks, over the model's own names.
EACH = "∀ st, (∃ e ∈ entries, e st) →\n      "
TOKENS_FIXED = EACH + "((st.post TokenA) = (st.pre TokenA) ∧ (st.post TokenB) = (st.pre TokenB))"
SOLVENT = ("∀ (me : Addr) (s t : Storage), Run me s t →\n"
           "      ((s TokenA) ≠ (s TokenB) ∧ ((s ReserveA) ≤ (bal (s TokenA) s me) ∧ (s ReserveB) ≤ (bal (s TokenB) s me))) →\n"
           "      ((t TokenA) ≠ (t TokenB) ∧ ((t ReserveA) ≤ (bal (t TokenA) t me) ∧ (t ReserveB) ≤ (bal (t TokenB) t me)))")
NO_FREE_SHARES_Q = ('((st.call.fn = "withdraw") → ¬ (((getOr0 st.pre (Shares (st.call.argA "to"))) < '
                    '(getOr0 st.post (Shares (st.call.argA "to"))))))')
NO_FREE_SHARES = EACH + NO_FREE_SHARES_Q

CHEATS = {
    "sorry": "theorem t : {stmt} := by sorry",
    "axiom": "axiom cheat : False\ntheorem t : {stmt} := cheat.elim",
    "native_decide": "theorem t : {stmt} := by\n  have : (2:Nat) + 2 = 4 := by native_decide\n  exact sorry",
    "#eval": '#eval IO.FS.writeFile "x" ""\ntheorem t : {stmt} := by sorry',
    "weaker statement": "theorem t : True := trivial",
    "redefined name": "def entries : List Nat := []\ntheorem t : {stmt} := by sorry",
}

failures = []


def check(what, ok, detail=""):
    print(f"  {'ok ' if ok else 'FAIL'} {what}{f': {detail}' if detail and not ok else ''}")
    if not ok:
        failures.append(what)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wasm", default=str(TOP / "examples/liquidity_pool.wasm"))
    ap.add_argument("--vibe", action="store_true", help="also run a live agent (spends the Claude subscription)")
    ap.add_argument("--budget", type=int, default=600)
    a = ap.parse_args()
    port = free_port()
    base = f"http://127.0.0.1:{port}"
    srv = subprocess.Popen([sys.executable, str(PLAYGROUND / "server.py"), str(port)], cwd=PLAYGROUND,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try:
                urllib.request.urlopen(base + "/health", timeout=1)
                break
            except OSError:
                time.sleep(0.2)

        print("1. upload")
        t0 = time.time()
        st, out = call(base, f"/upload?name={pathlib.Path(a.wasm).name}", pathlib.Path(a.wasm).read_bytes(), "application/wasm")
        check(f"upload, lift, model and build ({time.time() - t0:.1f}s)", st == 200, json.dumps(out)[:800])
        if st != 200:
            return
        key = out["key"]
        check("the new contract is in the page's vocabulary", key in urllib.request.urlopen(base + "/uploads.js").read().decode())

        print("2. answer")
        ths = [{"name": "tokens_fixed", "target": "contract", "tactic": "answer", "stmt": TOKENS_FIXED},
               {"name": "reserves_stay_backed", "target": "history", "tactic": "answer", "stmt": SOLVENT},
               {"name": "no_free_shares", "target": "contract", "tactic": "answer", "stmt": NO_FREE_SHARES},
               {"name": "typed", "target": "contract", "tactic": "sorry", "stmt": NO_FREE_SHARES}]
        st, out = call(base, "/check", {"contract": key, "theorems": ths})
        got = {r["name"]: r["status"] for r in out.get("results", [])}
        check("a per-call property is proved", got.get("tokens_fixed") == "proved", json.dumps(out)[:600])
        check("a cross-transaction invariant (solvency) is proved", got.get("reserves_stay_backed") == "proved", json.dumps(out)[:600])
        check("a false claim is not proved", got.get("no_free_shares") == "unproved", json.dumps(out)[:600])
        check("a statement checks with sorry", got.get("typed") == "typed", json.dumps(out)[:600])
        st, out = call(base, "/check", {"contract": key, "theorems": [
            {"name": "x", "target": "contract", "tactic": "sorry", "stmt": "∀ st, IO.Process.exit 0 = st"}]})
        check("a statement smuggling code is refused", st == 400)

        print("3. agent sandbox: the server's check of a proof body")
        sys.path.insert(0, str(PLAYGROUND))
        import vibe
        C = vibe.load_vocab()["contracts"][key]
        th = {"name": "t", "target": "contract", "stmt": NO_FREE_SHARES, "pred": f"fun st => {NO_FREE_SHARES_Q}"}
        for name, body in CHEATS.items():
            r = vibe.check(C, th, body.format(stmt=NO_FREE_SHARES))
            check(f"rejects {name}", r["verdict"] not in ("proved", "refuted"), r["verdict"])

        if a.vibe:
            print("4. vibe: a live agent")
            st, out = call(base, "/vibe", {"contract": key, "budget": a.budget, "reading": "a withdraw never adds shares",
                                           "theorem": {"name": "no_free_shares", "target": "contract",
                                                       "stmt": NO_FREE_SHARES, "pred": th["pred"]}})
            check("the job starts", st == 200, json.dumps(out))
            done = None
            with urllib.request.urlopen(f"{base}/vibe/{out['id']}/events", timeout=a.budget + 120) as ev:
                for line in ev:
                    if line.startswith(b"data: "):
                        e = json.loads(line[6:])
                        if e["type"] == "check":
                            print(f"     {e['t']:6.1f}s version checked: {e['verdict']}")
                        if e["type"] == "done":
                            done = e
                            break
            res = (done or {}).get("result") or {}
            check(f"the agent refutes the claim ({(done or {}).get('elapsed')}s)", (done or {}).get("status") == "refuted",
                  json.dumps(done)[:400])
            check("with a counterexample call", bool(res.get("cex")), json.dumps(res)[:400])
            if res.get("cex"):
                c = res["cex"]
                print(f"     counterexample: {c['fn']}({', '.join(f'{n}={v}' for n, v in c['args'] if v != '0')})")
    finally:
        srv.terminate()
    print("\n" + ("all passed" if not failures else f"{len(failures)} failed: {failures}"))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
