#!/usr/bin/env python3
"""Every editor permalink in a markdown file opens and checks.

For each link `…#c=<contract>&w=<blocks>`: the contract exists, every block exists for it, the
editor's own printer (prover/playground/lean.js) turns the blocks into a theorem without
problems, and the server checks that theorem: with its tactic when that is `answer` (it must
be proved), as a statement (`sorry`) otherwise.

    python3 tests/permalinks.py [README.md]
"""

import base64
import json
import pathlib
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

TOP = pathlib.Path(__file__).resolve().parent.parent
PLAYGROUND = TOP / "prover/playground"

PRINT = r"""
global.window = {};
require(process.argv[1] + '/vocab.js');
const L = require(process.argv[1] + '/lean.js');
const [key, blocks] = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const C = window.VOCAB.contracts[key];
if (!C) { console.log(JSON.stringify({ error: `no contract ${key}` })); process.exit(0); }
const S = L.buildSpecs(key, C);
const missing = new Set();
const walk = (b) => { if (!S[b.type]) missing.add(b.type); for (const v of Object.values(b.inputs || {})) walk(v.block); };
blocks.forEach(walk);
const out = blocks.map((b) => { const t = L.genTheorem(S, b);
  return { name: t.name, target: t.target, tactic: t.tactic, stmt: L.plain(t.stmt), problems: t.problems }; });
console.log(JSON.stringify({ missing: [...missing], theorems: out }));
"""


def main():
    md = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else TOP / "README.md").read_text()
    links = re.findall(r"#c=(\w+)&w=([A-Za-z0-9_-]+)", md)
    print(f"{len(links)} permalink(s)")
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    srv = subprocess.Popen([sys.executable, str(PLAYGROUND / "server.py"), str(port)], cwd=PLAYGROUND,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    bad = 0
    try:
        for _ in range(50):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=1)
                break
            except OSError:
                time.sleep(0.2)
        for key, raw in links:
            blocks = json.loads(base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)))
            p = subprocess.run(["node", "-e", PRINT, str(PLAYGROUND)], input=json.dumps([key, blocks]),
                               capture_output=True, text=True, check=True)
            res = json.loads(p.stdout)
            if res.get("error") or res["missing"]:
                print(f"  FAIL {key}: {res.get('error') or 'missing blocks ' + str(res['missing'])}")
                bad += 1
                continue
            for t in res["theorems"]:
                if t["problems"]:
                    print(f"  FAIL {key}/{t['name']}: {t['problems']}")
                    bad += 1
                    continue
                tactic = "answer" if t["tactic"] == "answer" else "sorry"
                req = {"contract": key, "theorems": [{**t, "tactic": tactic}]}
                try:
                    with urllib.request.urlopen(urllib.request.Request(
                            f"http://127.0.0.1:{port}/check", json.dumps(req).encode(),
                            {"Content-Type": "application/json"}), timeout=600) as r:
                        st = json.load(r)["results"][0]["status"]
                except urllib.error.HTTPError as e:
                    st = f"refused: {e.read().decode()}"
                want = "proved" if tactic == "answer" else "typed"
                ok = st == want
                bad += not ok
                print(f"  {'ok  ' if ok else 'FAIL'} {key}/{t['name']} (by {t['tactic']}): {st}")
    finally:
        srv.terminate()
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
