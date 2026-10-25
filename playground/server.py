#!/usr/bin/env python3
"""Serve the playground and check theorems with Lean.

    python3 playground/server.py [port]

GET  /          the playground (files of this folder)
GET  /health    {"lean": true} when `lake` is on the PATH
POST /check     {"contract": key, "theorems": [{"name", "target", "stmt", "tactic"}]}
                -> {"results": [{"name", "status", "messages"}], "elapsed"}

Lean runs whatever a file asks, so /check never takes Lean source: it takes
statements and accepts only the tokens the blocks can produce (vocabulary of
the contract, glue, numbers), then writes the file itself. It also listens on
localhost only and refuses requests from other origins.
"""

import http.server
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
LOCK = threading.Lock()


def load_vocab():
    src = (HERE / "vocab.js").read_text()
    return json.loads(src[src.index("{"):src.rindex("}") + 1])


TOKEN = re.compile(r'\s+|"[a-z_]+"|\d+|∀ₛ|∧ₛ|∨ₛ|=>|\.[A-Za-z_]+|[A-Za-z_][A-Za-z0-9_\']*|[()\[\],·+\-*]')
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_']*$")
KEYWORDS = {"theorem", "def", "by", "do", "at", "in", "let", "have", "show", "from", "where", "open",
            "namespace", "end", "import", "macro", "syntax", "elab", "set_option", "attribute"}


def allowed(vocab, C):
    names = set(vocab["generic"])
    for group in ("vars", "maps", "addrs", "amounts", "conds", "addrPreds", "invariants"):
        names |= {row[0] for row in C[group]}
    names |= set(C["who"])
    if "beforeAfter" in C["features"]:
        names |= {"before", "after"}
    return names


def validate(vocab, C, th):
    """Raise ValueError unless `th` is a statement the blocks could produce."""
    name, target, stmt, tactic = th.get("name"), th.get("target"), th.get("stmt"), th.get("tactic")
    if not isinstance(name, str) or not IDENT.match(name) or name in KEYWORDS or len(name) > 80:
        raise ValueError("bad theorem name")
    if target not in [t for t, _ in C["targets"]]:
        raise ValueError("unknown target")
    if tactic not in C["tactics"]:
        raise ValueError("unknown tactic")
    if not isinstance(stmt, str) or len(stmt) > 4000:
        raise ValueError("bad statement")
    names = allowed(vocab, C)
    toks, pos = [], 0
    while pos < len(stmt):
        m = TOKEN.match(stmt, pos)
        if not m:
            raise ValueError(f"unexpected character {stmt[pos]!r}")
        pos = m.end()
        if not m.group().isspace():
            toks.append(m.group())
    bound = {toks[i + 1] for i, t in enumerate(toks[:-1]) if t == "∀ₛ"}
    for t in toks:
        if t.startswith('"'):
            if t[1:-1] not in C["entries"]:
                raise ValueError(f"unknown entry point {t}")
        elif t.startswith("."):
            if t not in (".given", ".except", ".total"):
                raise ValueError(f"unexpected {t}")
        elif IDENT.match(t) and t not in names and t not in bound:
            raise ValueError(f"unknown name {t}")
        if t in bound and (t in KEYWORDS or not re.match(r"^[a-z][A-Za-z0-9_]*$", t)):
            raise ValueError(f"bad variable name {t}")


MSG = re.compile(r"^(?:.*?):(\d+):(\d+): (error|warning|info): ?(.*)$")


def check(vocab, req):
    C = vocab["contracts"].get(req.get("contract"))
    if C is None:
        raise ValueError("unknown contract")
    ths = req.get("theorems")
    if not isinstance(ths, list) or not 1 <= len(ths) <= 30:
        raise ValueError("send 1 to 30 theorems")
    for th in ths:
        validate(vocab, C, th)

    lines = list(C["prelude"]) + [""]
    spans = []
    for k, th in enumerate(ths):
        start = len(lines) + 1
        lines += [f"theorem {th['name']} :", f"    {th['target']} ⊨ {th['stmt']} := by", f"  {th['tactic']}", ""]
        spans.append((start, len(lines)))
    lines += list(C["epilogue"]) + [""]

    with tempfile.TemporaryDirectory(prefix="playground-") as tmp:
        path = pathlib.Path(tmp) / "Playground.lean"
        path.write_text("\n".join(lines))
        t0 = time.time()
        with LOCK:
            proc = subprocess.run(["lake", "env", "lean", str(path)], cwd=ROOT, capture_output=True,
                                  text=True, timeout=300)
        elapsed = time.time() - t0

    # Group the output into messages, each belonging to the theorem whose lines contain it.
    msgs = []
    for raw in (proc.stdout + proc.stderr).splitlines():
        m = MSG.match(raw)
        if m:
            msgs.append({"line": int(m[1]), "severity": m[3], "text": m[4]})
        elif msgs:
            msgs[-1]["text"] += "\n" + raw
        elif raw.strip():
            msgs.append({"line": 0, "severity": "error", "text": raw})

    results, general = [], []
    owned = set()
    for (a, b), th in zip(spans, ths):
        mine = [m for m in msgs if a <= m["line"] < b]
        owned |= {id(m) for m in mine}
        errors = [m for m in mine if m["severity"] == "error"]
        if errors:
            status = "error" if th["tactic"] == "sorry" or not any(m["text"].startswith("answer:") for m in errors) else "unproved"
        elif th["tactic"] == "sorry":
            status = "typed"
        else:
            status = "proved"
        results.append({"name": th["name"], "status": status,
                        "messages": [m["text"] for m in mine if not m["text"].startswith("declaration uses")]})
    general = [m["text"] for m in msgs if id(m) not in owned and m["severity"] == "error"]
    if general:
        for r in results:
            if r["status"] in ("proved", "typed"):
                r["status"] = "error"
    return {"results": results, "general": general, "elapsed": round(elapsed, 1)}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(HERE), **kw)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def reply(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            return self.reply(200, {"lean": shutil.which("lake") is not None})
        return super().do_GET()

    def do_POST(self):
        if self.path != "/check":
            return self.reply(404, {"error": "not found"})
        origin = self.headers.get("Origin")
        if origin and origin != f"http://{self.headers.get('Host')}":
            return self.reply(403, {"error": "other origins may not ask for checks"})
        if not self.headers.get("Content-Type", "").startswith("application/json"):
            return self.reply(415, {"error": "send JSON"})
        try:
            n = int(self.headers.get("Content-Length", "0"))
            req = json.loads(self.rfile.read(min(n, 200_000)))
            return self.reply(200, check(load_vocab(), req))
        except ValueError as e:
            return self.reply(400, {"error": str(e)})
        except subprocess.TimeoutExpired:
            return self.reply(504, {"error": "Lean took longer than 5 minutes"})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Theorem blocks: http://localhost:{port}/", flush=True)
    srv.serve_forever()
