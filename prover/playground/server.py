#!/usr/bin/env python3
"""Serve the playground and check theorems with Lean.

    python3 playground/server.py [port] [host]    (host defaults to 127.0.0.1)

GET  /          the playground (files of this folder)
GET  /health    {"lean": true} when `lake` is on the PATH, {"vibe": …} when `claude` is
POST /check     {"contract": key, "theorems": [{"name", "target", "stmt", "tactic"}]}
                -> {"results": [{"name", "status", "messages"}], "elapsed"}
POST /upload?name=F.wasm[&fresh=1]   the wasm as the body: lift it, emit its Lean model,
                build it, and add the contract (ingest.py) -> {"key", "title", "steps", "cached"?};
                bytes already modelled return that contract at once, unless fresh=1
GET  /uploads.js   adds the uploaded contracts to the page's vocabulary
POST /vibe      {"contract", "theorem": {"name", "target", "stmt"}, "reading", "budget"}
                -> {"id"}: a Claude agent looks for a proof or a counterexample (vibe.py)
GET  /vibe/ID/events   the job's events, as server-sent events
POST /vibe/ID/stop

Uploads run tools on the uploaded file, and vibe jobs run on the Claude subscription of
whoever runs the server, so both need
the token in $VIBE_TOKEN (header X-Vibe-Token or ?token=), or, when it is unset, a
direct request from this machine (not through a proxy such as ngrok).

Lean runs whatever a file asks, so /check never takes Lean source: it takes
statements and accepts only the tokens the blocks can produce (vocabulary of
the contract, glue, numbers), then writes the file itself. It listens on
localhost by default and accepts requests from any origin (CORS is open).
"""

import http.server
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse

import ingest
import vibe

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
LOCK = vibe.LEAN_LOCK   # one Lean at a time, shared with the vibe checker


def load_vocab():
    src = (HERE / "vocab.js").read_text()
    V = json.loads(src[src.index("{"):src.rindex("}") + 1])
    V["contracts"].update(ingest.uploaded_contracts())   # contracts made from uploaded wasm
    return V


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


# Statements about a stellar-diver model are printed straight to Lean over the model's
# names; these are the only other words they use.
DIVER_GLUE = {"st", "pre", "post", "call", "caller", "fn", "arg", "argA", "signers", "ret", "entries", "e",
              "getOr0", "bal", "pool", "Run", "me", "s", "t", "Addr", "Storage"}
DIVER_TOKEN = re.compile(r'\s+|"[A-Za-z_][\w.]*"|\d+|[A-Za-z_][A-Za-z0-9_\']*(?:\.[A-Za-z_][A-Za-z0-9_\']*)*'
                         r'|=>|[()\[\],:+\-*]|∀|∃|∈|→|¬|∧|∨|=|≤|<|≠')


def validate_diver(C, th):
    name, stmt = th.get("name"), th.get("stmt")
    if not isinstance(name, str) or not IDENT.match(name) or name in KEYWORDS or len(name) > 80:
        raise ValueError("bad theorem name")
    if th.get("tactic") not in C["tactics"]:
        raise ValueError("unknown tactic")
    D = C["diver"]
    names = DIVER_GLUE | {v for v, _, _ in C["vars"]} | set(D["maps"]) | set(D.get("fields", [])) \
        | set(D["derived"]) | set(C["entries"])
    strings = {a for a, _ in C["amounts"]} | set(D["addrArgs"]) | set(C["entries"])
    for field in ("stmt", "pred"):
        text = th.get(field)
        if text is None and field == "pred":
            continue
        if not isinstance(text, str) or len(text) > 6000:
            raise ValueError(f"bad {field}")
        pos, bound = 0, set()
        toks = []
        while pos < len(text):
            m = DIVER_TOKEN.match(text, pos)
            if not m:
                raise ValueError(f"unexpected character {text[pos]!r}")
            pos = m.end()
            if not m.group().isspace():
                toks.append(m.group())
        bound = {toks[i + 1] for i, t in enumerate(toks[:-1])
                 if (t in ("∀", "fun") or (t == "(" and i + 2 < len(toks) and toks[i + 2] == ":"))
                 and IDENT.match(toks[i + 1])}
        known = names | bound | {"fun"}
        for t in toks:
            if t.startswith('"'):
                if t[1:-1] not in strings:
                    raise ValueError(f"unknown argument {t}")
            elif IDENT.match(t.split(".")[0]) and t not in known:
                # `st.pre`, `st.call.argA`: a known name, then fields of the model's structures.
                head, *rest = t.split(".")
                if head not in known or not rest or any(p not in DIVER_GLUE for p in rest):
                    raise ValueError(f"unknown name {t}")
        for v in bound:
            if v in KEYWORDS or not re.match(r"^[a-z][A-Za-z0-9_]*$", v):
                raise ValueError(f"bad variable name {v}")


def validate(vocab, C, th):
    """Raise ValueError unless `th` is a statement the blocks could produce."""
    if C.get("kind") == "diver":
        return validate_diver(C, th)
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
        if th["tactic"] == "vibe":
            raise ValueError("vibe theorems go to /vibe")
    lines = list(C["prelude"]) + [""]
    spans = []
    for k, th in enumerate(ths):
        start = len(lines) + 1
        if C.get("kind") == "diver":   # the statement spans several lines
            lines += f"theorem {th['name']} :\n    {th['stmt']} := by\n  {th['tactic']}\n".split("\n")
        else:
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
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def reply(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def vibe_ok(self):
        url = urllib.parse.urlparse(self.path)
        token = self.headers.get("X-Vibe-Token") or urllib.parse.parse_qs(url.query).get("token", [None])[0]
        if os.environ.get("VIBE_OPEN") == "1":   # a public demo: anyone may upload and run vibe
            return True
        want = os.environ.get("VIBE_TOKEN")
        if want:
            return token == want
        proxied = any(self.headers.get(h) for h in ("X-Forwarded-For", "X-Forwarded-Host", "Forwarded"))
        return self.client_address[0] in ("127.0.0.1", "::1") and not proxied

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        if url.path == "/health":
            return self.reply(200, {"lean": shutil.which("lake") is not None,
                                    "vibe": {"available": shutil.which("claude") is not None,
                                             "token": bool(os.environ.get("VIBE_TOKEN")),
                                             "allowed": self.vibe_ok()}})
        if url.path == "/uploads.js":
            body = ("window.VOCAB && Object.assign(window.VOCAB.contracts, "
                    + json.dumps(ingest.uploaded_contracts(), ensure_ascii=False) + ");\n").encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/javascript; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            return self.wfile.write(body)
        m = re.fullmatch(r"/vibe/([0-9a-f]{12})/events", url.path)
        if m:
            if not self.vibe_ok():
                return self.reply(403, {"error": "vibe needs the token"})
            job = vibe.JOBS.get(m[1])
            if job is None:
                return self.reply(404, {"error": "no such job"})
            return self.stream(job)
        return super().do_GET()

    def stream(self, job):
        """Server-sent events: every event of the job so far, then new ones until it is done."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()
        sent = 0
        try:
            while True:
                with job.cond:
                    if sent >= len(job.events):
                        job.cond.wait(timeout=15)
                    new = job.events[sent:]
                sent += len(new)
                for ev in new:
                    self.wfile.write(f"data: {json.dumps(ev)}\n\n".encode())
                if not new:
                    self.wfile.write(b": keep-alive\n\n")
                self.wfile.flush()
                if any(ev["type"] == "done" for ev in new):
                    return
        except (BrokenPipeError, ConnectionResetError):
            return

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        if url.path == "/upload":
            if not self.vibe_ok():
                return self.reply(403, {"error": "uploads need the token"})
            n = int(self.headers.get("Content-Length", "0"))
            if n > ingest.MAX_WASM:
                return self.reply(413, {"error": "the file is too large"})
            data = self.rfile.read(n)
            q = urllib.parse.parse_qs(url.query)
            name = q.get("name", ["contract.wasm"])[0]
            try:
                return self.reply(200, ingest.ingest(name, data, fresh=q.get("fresh", ["0"])[0] == "1"))
            except ingest.IngestError as e:
                return self.reply(422, {"error": str(e), "steps": e.steps})
            except ValueError as e:
                return self.reply(400, {"error": str(e)})
        m = re.fullmatch(r"/vibe/([0-9a-f]{12})/stop", url.path)
        if url.path == "/vibe" or m:
            if not self.vibe_ok():
                return self.reply(403, {"error": "vibe needs the token"})
            if m:
                job = vibe.JOBS.get(m[1])
                if job:
                    job.stop("undecided")
                return self.reply(200, {"ok": bool(job)})
            try:
                n = int(self.headers.get("Content-Length", "0"))
                req = json.loads(self.rfile.read(min(n, 200_000)))
                job = vibe.start_job(load_vocab(), req, validate, req.get("reading"))
                return self.reply(200, {"id": job.id, "budget": job.budget})
            except ValueError as e:
                return self.reply(400, {"error": str(e)})
        if self.path != "/check":
            return self.reply(404, {"error": "not found"})
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
    host = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
    srv = http.server.ThreadingHTTPServer((host, port), Handler)
    print(f"Theorem blocks: http://{'localhost' if host in ('127.0.0.1', '0.0.0.0') else host}:{port}/"
          f" (listening on {host})", flush=True)
    srv.serve_forever()
