#!/usr/bin/env python3
"""Proof by vibe: a Claude agent looks for a proof or a counterexample of one theorem
block, within a time budget, while every version it writes is checked by Lean.

The statement never comes from the agent. The agent edits only the body of a file
(`Proof.lean` in its workspace); the server wraps that body between the contract's
prelude and a tail it writes itself, which restates the block's statement and
accepts it only as

    theorem __vibe_goal : <target> ⊨ <stmt> := VibeProof.<name>          (proved)
    theorem __vibe_refuted : ¬ (<target> ⊨ <stmt>) := VibeProof.<name>_false   (refuted)

with nothing but the standard axioms. A refutation also names a concrete call,
`<name>_cex : Step`, with `<name>_cex_breaks : ¬ (<stmt>) <name>_cex`; the tail
evaluates it to show the counterexample.

    python3 vibe.py check WORKSPACE    (what the agent's ./check runs)
"""

import json
import os
import pathlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import uuid

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
LEAN_LOCK = threading.Lock()
ALLOWED_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}

# Things the body may not contain: anything that runs code, changes how the tail
# parses or elaborates, adds axioms, or switches off checks.
FORBIDDEN = re.compile(
    r"#eval|#exit|#print|#check_failure|run_cmd|run_tac|run_elab|run_meta|\belab\b|elab_rules|"
    r"\bmacro\b|macro_rules|\bsyntax\b|\bnotation\b|\binfixl?r?\b|\bprefix\b|\bpostfix\b|"
    r"\binitialize\b|builtin_initialize|implemented_by|\bextern\b|\bunsafe\b|\baxiom\b|\bopaque\b|"
    r"\bimport\b|\bnamespace\b|\bsection\b|\bend\b|\binstance\b|\bderiving\b|\battribute\b|"
    r"native_decide|\bdebug\.|\bIO\b|@\[(?!simp\]|answer\])")
SET_OPTION = re.compile(r"\bset_option\b(?!\s+maxHeartbeats\s+\d+\s+in\b)")


def load_vocab():
    src = (HERE / "vocab.js").read_text()
    return json.loads(src[src.index("{"):src.rindex("}") + 1])


def strip_comments(s):
    return re.sub(r"--[^\n]*", "", re.sub(r"/-.*?-/", "", s, flags=re.S))


def forbidden(body):
    code = strip_comments(body)
    m = FORBIDDEN.search(code) or SET_OPTION.search(code)
    return m.group(0) if m else None


def show_tail(C, name):
    """Lean that prints the counterexample `VibeProof.<name>_cex` as one JSON line. Values
    are read through the model's own bricks (`Term.get`, `Map.read`), as the questions do."""
    amounts = ", ".join(f'("{rust}", toString ({lean} c))' for lean, rust in C["amounts"])
    fixed = ", ".join(f'("{a}", {a})' for a, _ in C["addrs"])
    def var(v, ty):
        show = "toString" if ty == "Int" else "(fun a => \"@\" ++ toString a)"
        return (f'__vibe_arr [__vibe_str "{v}", __vibe_str ({show} ({v}.get c st.pre)), '
                f'__vibe_str ({show} ({v}.get c st.post))]')
    vars_ = ", ".join(var(v, ty) for v, ty, _ in C["vars"])
    maps = ", ".join(f'("{m}", fun s a => toString ({m}.read s a))' for m, _ in C["maps"])
    # extra addresses to show the maps at: `Who`s of the call (e.g. a token argument).
    cex_who = "".join(f" ++ [{w} c]" for w in C.get("cexWho", []))
    return f"""
def __vibe_str (s : String) : String := "\\"" ++ s ++ "\\""
def __vibe_obj (kvs : List (String × String)) : String :=
  "{{" ++ ",".intercalate (kvs.map fun (k, v) => __vibe_str k ++ ":" ++ v) ++ "}}"
def __vibe_arr (xs : List String) : String := "[" ++ ",".intercalate xs ++ "]"
def __vibe_ret : Query.Val → String
  | .none => "null" | .int i => __vibe_str (toString i) | .addr a => __vibe_str ("@" ++ toString a)
def __vibe_show (st : Step) : String :=
  let c := st.call
  let fixed : List (String × Addr) := [{fixed}]
  let addrs := ([c.caller, c.args.to] ++ c.holders ++ fixed.map (·.2){cex_who}).eraseDups
  let maps : List (String × (Storage → Addr → String)) := [{maps}]
  let amounts : List (String × String) := [{amounts}]
  __vibe_obj [
    ("fn", __vibe_str c.fn), ("caller", toString c.caller), ("to", toString c.args.to),
    ("amt", __vibe_str (toString c.args.amt)), ("holders", __vibe_arr (c.holders.map toString)),
    ("fixed", __vibe_arr (fixed.map fun (n, a) => __vibe_arr [__vibe_str n, toString a])),
    ("args", __vibe_arr (amounts.map fun (n, v) => __vibe_arr [__vibe_str n, __vibe_str v])),
    ("ret", __vibe_ret st.ret),
    ("vars", __vibe_arr [{vars_}]),
    ("maps", __vibe_arr (maps.flatMap fun (m, rd) => addrs.map fun a =>
      __vibe_arr [__vibe_str m, toString a, __vibe_str (rd st.pre a), __vibe_str (rd st.post a)]))]
#eval IO.println ("VIBE-CEX " ++ __vibe_show VibeProof.{name}_cex)
"""


def show_tail_diver(C, name):
    """Lean that prints `VibeProof.<name>_cex`, a step of a stellar-diver model, as one JSON
    line: the call, and every storage key, map entry and token balance the model names,
    before and after."""
    D = C["diver"]
    addr_vars = {v for v, ty, _ in C["vars"] if ty == "Addr"}
    def show(v, s):
        return f'("@" ++ toString ({s} {v}))' if v in addr_vars else f"(toString ({s} {v}))"
    vars_ = ", ".join(f'__vibe_arr [__vibe_str "{v}", __vibe_str {show(v, "st.pre")}, __vibe_str {show(v, "st.post")}]'
                      for v, _, _ in C["vars"])
    reads = [f'("{m}", fun (s : Storage) a => toString (getOr0 s ({m} a)))' for m in D["maps"]]
    reads += [f'("{b}", fun (s : Storage) a => toString (bal (s {t}) s a))' for b, t in D["ledgers"].items()]
    args = ", ".join(f'("{a}", toString (c.arg "{a}"))' for a, _ in C["amounts"])
    fixed = ", ".join(['("pool", c.self)'] + [f'("{a}", c.argA "{a}")' for a in D["addrArgs"]])
    return f"""
def __vibe_str (s : String) : String := "\\"" ++ s ++ "\\""
def __vibe_obj (kvs : List (String × String)) : String :=
  "{{" ++ ",".intercalate (kvs.map fun (k, v) => __vibe_str k ++ ":" ++ v) ++ "}}"
def __vibe_arr (xs : List String) : String := "[" ++ ",".intercalate xs ++ "]"
def __vibe_show (st : Step) : String :=
  let c := st.call
  let fixed : List (String × Addr) := [{fixed}]
  let addrs := ([c.caller] ++ c.signers ++ fixed.map (·.2)).eraseDups
  let reads : List (String × (Storage → Addr → String)) := [{", ".join(reads)}]
  let args : List (String × String) := [{args}]
  __vibe_obj [
    ("fn", __vibe_str c.fn), ("caller", toString c.caller), ("to", toString c.caller), ("amt", __vibe_str "0"),
    ("holders", "[]"), ("signers", __vibe_arr (c.signers.map toString)),
    ("fixed", __vibe_arr (fixed.map fun (n, a) => __vibe_arr [__vibe_str n, toString a])),
    ("args", __vibe_arr (args.map fun (n, v) => __vibe_arr [__vibe_str n, __vibe_str v])),
    ("ret", __vibe_str (toString st.ret)),
    ("vars", __vibe_arr [{vars_}]),
    ("maps", __vibe_arr (reads.flatMap fun (m, rd) => addrs.map fun a =>
      __vibe_arr [__vibe_str m, toString a, __vibe_str (rd st.pre a), __vibe_str (rd st.post a)]))]
#eval IO.println ("VIBE-CEX " ++ __vibe_show VibeProof.{name}_cex)
"""


def assemble(C, th, body):
    """The checked file, and the line where the body starts (1-based)."""
    name, target, stmt = th["name"], th["target"], th["stmt"]
    code = strip_comments(body)
    lines = list(C["prelude"]) + ["", "namespace VibeProof", ""]
    start = len(lines) + 1
    lines += body.split("\n")
    lines += ["", "end VibeProof", "", "-- Trusted tail, written by the server."]
    if C.get("kind") == "diver":
        if re.search(rf"\btheorem\s+{re.escape(name)}\s*:", code):
            lines += [f"theorem __vibe_goal : {stmt} := VibeProof.{name}", "#print axioms __vibe_goal"]
        if re.search(rf"\btheorem\s+{re.escape(name)}_false\s*:", code):
            lines += [f"theorem __vibe_refuted : ¬ ({stmt}) := VibeProof.{name}_false", "#print axioms __vibe_refuted"]
            if th.get("pred") and re.search(rf"\b(def|abbrev)\s+{re.escape(name)}_cex\b", code) and \
               re.search(rf"\btheorem\s+{re.escape(name)}_cex_breaks\s*:", code):
                lines += [f"theorem __vibe_cex_breaks : (∃ e ∈ entries, e VibeProof.{name}_cex) ∧ "
                          f"¬ (({th['pred']}) VibeProof.{name}_cex) := VibeProof.{name}_cex_breaks"]
                lines += show_tail_diver(C, name).split("\n")
        lines += list(C["epilogue"]) + [""]
        return "\n".join(lines), start
    if re.search(rf"\btheorem\s+{re.escape(name)}\s*:", code):
        lines += [f"theorem __vibe_goal : {target} ⊨ {stmt} := VibeProof.{name}", "#print axioms __vibe_goal"]
    if re.search(rf"\btheorem\s+{re.escape(name)}_false\s*:", code):
        lines += [f"theorem __vibe_refuted : ¬ ({target} ⊨ {stmt}) := VibeProof.{name}_false",
                  "#print axioms __vibe_refuted"]
        if re.search(rf"\b(def|abbrev)\s+{re.escape(name)}_cex\b", code) and \
           re.search(rf"\btheorem\s+{re.escape(name)}_cex_breaks\s*:", code):
            lines += [f"theorem __vibe_cex_breaks : ¬ ({stmt}) VibeProof.{name}_cex := VibeProof.{name}_cex_breaks"]
            lines += show_tail(C, name).split("\n")
    lines += list(C["epilogue"]) + [""]
    return "\n".join(lines), start


MSG = re.compile(r"^(?:.*?):(\d+):(\d+): (error|warning|info): ?(.*)$")
AXIOMS = re.compile(r"'(?:[\w.]*\.)?(__vibe_goal|__vibe_refuted)' (?:depends on axioms: \[([^\]]*)\]|does not depend on any axioms)")


def check(C, th, body, timeout=180):
    """Check one version of the body. Returns
    {verdict: proved|refuted|error|incomplete, messages: [{line, severity, text}], cex, elapsed}
    with body-relative line numbers (0 = outside the body)."""
    bad = forbidden(body)
    if bad:
        return {"verdict": "error", "messages": [{"line": 0, "severity": "error",
                "text": f"not allowed in the proof: `{bad}` (the statement and checks are the server's)"}],
                "cex": None, "elapsed": 0}
    text, start = assemble(C, th, body)
    n_body = body.count("\n") + 1
    with tempfile.TemporaryDirectory(prefix="vibe-check-") as tmp:
        path = pathlib.Path(tmp) / "Vibe.lean"
        path.write_text(text)
        t0 = time.time()
        with LEAN_LOCK:
            try:
                proc = subprocess.run(["lake", "env", "lean", str(path)], cwd=ROOT, capture_output=True,
                                      text=True, timeout=timeout)
                out = proc.stdout + proc.stderr
            except subprocess.TimeoutExpired:
                out = f"{path}:0:0: error: Lean took longer than {timeout}s"
        elapsed = round(time.time() - t0, 1)
    msgs, cex, axioms = [], None, {}
    for raw in out.splitlines():
        # `#eval` and `#print axioms` output may come bare or as `file:l:c: info: …`.
        if "VIBE-CEX " in raw:
            try: cex = json.loads(raw.split("VIBE-CEX ", 1)[1])
            except json.JSONDecodeError: pass
            continue
        ax = AXIOMS.search(raw)
        if ax:
            axioms[ax[1]] = {a.strip() for a in (ax[2] or "").split(",") if a.strip()}
            continue
        m = MSG.match(raw)
        if m:
            line = int(m[1]) - start + 1
            msgs.append({"line": line if 1 <= line <= n_body else 0, "severity": m[3], "text": m[4]})
        elif msgs and raw.strip():
            msgs[-1]["text"] += "\n" + raw
    ok = {}
    for k, axs in axioms.items():
        ok[k] = axs <= ALLOWED_AXIOMS
        if not ok[k]:
            note = "still has a `sorry`" if "sorryAx" in axs else "uses axioms " + ", ".join(sorted(axs - ALLOWED_AXIOMS))
            msgs.append({"line": 0, "severity": "error", "text": f"{k.removeprefix('__vibe_')}: {note}"})
    msgs = [m for m in msgs if not re.match(r"declaration uses ['`]sorry", m["text"])]
    if any(m["severity"] == "error" for m in msgs):
        verdict = "error"
    elif ok.get("__vibe_goal"):
        verdict = "proved"
    elif ok.get("__vibe_refuted"):
        verdict = "refuted"
    else:
        verdict = "incomplete"
    return {"verdict": verdict, "messages": msgs, "cex": cex if verdict == "refuted" else None, "elapsed": elapsed}


# --------------------------------------------------------------------- the agent

TASK = """You are proving or refuting one statement about a Soroban smart contract, modelled in Lean 4
(core Lean + the StellarLean library in {root}/StellarLean, no Mathlib). Time budget: {budget} seconds.
The user watches every version of your proof being checked live, so save early and often.

The statement (`{name}`), as Lean:

    {target} ⊨ {stmt}

In words: {reading}

Read first: {root}/StellarLean/Query.lean (what `⊨` and every brick mean),
{source} (the contract model and its facts; paths relative to {root}), and {root}/StellarLean/Answer.lean
(the `answer` tactic: an automatic prover over the contract's facts; try it first).

Write ONLY `Proof.lean` in this directory. It holds Lean declarations (no imports, no namespace,
no `end`); the server places it after the contract's prelude, which already opens `Query` and
the contract's namespace. Run `./check` after every edit: it prints Lean's errors (line numbers
are lines of Proof.lean) and a VERDICT. Then do exactly one of:

PROVE it:
    theorem {name} : {target} ⊨ {stmt} := by
      ...

or REFUTE it, with a concrete call that breaks it:
    def {name}_cex : Step := {{ call := {{ caller := 4, args := ⟨5, 0⟩, holders := [4, 5], fn := "...",
                                     arg := fun n => if n = "..." then 1 else 0 }},
                             pre := fun k => ..., post := fun k => ..., writes := [...] }}
    theorem {name}_cex_breaks : ¬ ({stmt}) {name}_cex := by ...
    theorem {name}_false : ¬ ({target} ⊨ {stmt}) := by ...   -- e.g. using {name}_cex

Keep the statement exactly as given (the server restates it and checks your theorem against
its own copy). Not allowed: sorry, axiom, native_decide, #eval, macros, notation, instances,
attributes other than @[simp]/@[answer], set_option (except `set_option maxHeartbeats N in`).
Only the standard axioms are accepted. You may add helper lemmas and defs.
Stop as soon as ./check says VERDICT: proved or VERDICT: refuted.
"""


TASK_DIVER = """You are proving or refuting one statement about a Soroban smart contract. The contract's
model was generated from its bytecode by stellar-diver: {root}/{source} (core Lean 4, namespace
`Contract`, which is opened for you; read it first: each entry point is a `Spec` structure whose
fields are the conditions for the call to succeed and its effect on storage). Time budget: {budget}
seconds. The user watches every version of your proof being checked live, so save early and often.

The statement (`{name}`):

    {stmt}

In words: {reading}

Write ONLY `Proof.lean` in this directory: Lean declarations (no imports, no namespace, no `end`).
Run `./check` after every edit: it prints Lean's errors (line numbers are lines of Proof.lean) and a
VERDICT. Then do exactly one of:

PROVE it:
    theorem {name} : {stmt} := by
      ...

or REFUTE it:
    theorem {name}_false : ¬ ({stmt}) := by ...
{cex}
Keep the statement exactly as given (the server restates it and checks your theorem against its own
copy). Not allowed: sorry, axiom, native_decide, #eval, macros, notation, instances, attributes other
than @[simp], set_option (except `set_option maxHeartbeats N in`). Only the standard axioms are
accepted. You may add helper lemmas and defs. Stop as soon as ./check says VERDICT: proved or
VERDICT: refuted.
"""

CEX_DIVER = """  and, when it is false, give the call that breaks it, so the user can see it:
    def {name}_cex : Step := {{ call := {{ fn := "...", caller := 1, self := 2, arg := fun n => if n = "..." then 5 else 0,
                                     argA := fun _ => 1, signers := [1], env := fun _ => 0 }},
                             pre := fun k => ..., post := fun k => ..., writes := [...], ret := 0 }}
    theorem {name}_cex_breaks : (∃ e ∈ entries, e {name}_cex) ∧ ¬ (({pred}) {name}_cex) := ...
"""


class Job:
    def __init__(self, contract, C, th, reading, budget, model=None):
        self.id = uuid.uuid4().hex[:12]
        self.contract, self.C, self.th, self.budget = contract, C, th, budget
        self.events, self.cond = [], threading.Condition()
        self.status = "running"
        self.started = time.time()
        self.proc = None
        self.ws = pathlib.Path(tempfile.mkdtemp(prefix=f"vibe-{th['name']}-"))
        (self.ws / "job.json").write_text(json.dumps({"contract": contract, "theorem": th}))
        # The library the agent may read: everything but the files of answered questions,
        # which would hand it the proofs.
        lib = self.ws / "StellarLean"
        lib.mkdir()
        for f in (ROOT / "StellarLean").rglob("*.lean"):
            if not re.search(r"Answers|Questions", f.name):
                (lib / f.relative_to(ROOT / "StellarLean")).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(f, lib / f.relative_to(ROOT / "StellarLean"))
        (self.ws / "Proof.lean").write_text(f"-- {th['name']}: prove or refute (see TASK.md), then run ./check\n")
        check_sh = self.ws / "check"
        check_sh.write_text(f"#!/bin/sh\nexec {sys.executable} {HERE / 'vibe.py'} check \"$(dirname \"$0\")\"\n")
        check_sh.chmod(0o755)
        src = pathlib.Path(C["source"]).name
        files = [f"StellarLean/{n}" for n in dict.fromkeys([src.replace("Answers", "Facts"), src.replace("Questions", "")])
                 if (lib / n).exists()]
        if C.get("kind") == "diver":
            cex = CEX_DIVER.format(name=th["name"], pred=th["pred"]) if th.get("pred") else ""
            task = TASK_DIVER.format(root=self.ws, budget=budget, name=th["name"], stmt=th["stmt"],
                                     reading=reading or "(none)", source=C["source"], cex=cex)
        else:
            task = TASK.format(root=self.ws, budget=budget, name=th["name"], target=th["target"], stmt=th["stmt"],
                               reading=reading or "(none)", source=" and ".join(files) or "StellarLean/")
        (self.ws / "TASK.md").write_text(task)
        self.model = model
        self.last_body = None
        self.result = None

    def emit(self, kind, **data):
        with self.cond:
            self.events.append({"type": kind, "t": round(time.time() - self.started, 1), **data})
            self.cond.notify_all()

    def snapshot(self):
        return {"id": self.id, "status": self.status, "budget": self.budget, "events": self.events}

    def start(self):
        threading.Thread(target=self._run_agent, daemon=True).start()
        threading.Thread(target=self._watch, daemon=True).start()

    def stop(self, why="stopped"):
        if self.status == "running":
            self._finish(why)

    # The agent: `claude -p`, on the user's Claude subscription (the API key is
    # removed from its environment so it can't fall back to API billing).
    def _run_agent(self):
        env = {k: v for k, v in os.environ.items() if k not in ("ANTHROPIC_API_KEY", "CLAUDECODE")}
        env.update(GLIBC_TUNABLES="", LD_LIBRARY_PATH="")
        cmd = [shutil.which("claude") or "claude", "-p", (self.ws / "TASK.md").read_text(),
               "--output-format", "stream-json", "--verbose", "--permission-mode", "acceptEdits",
               # No user settings, memory, hooks, plugins or MCP servers (no access to the
               # user's connectors), and file tools confined to the workspace + --add-dir.
               "--safe-mode", "--strict-mcp-config",
               "--allowedTools", "Read,Edit,Write,Glob,Grep,Bash(./check)",
               "--disallowedTools", "WebFetch,WebSearch",
               "--max-turns", "400"]
        if self.model:
            cmd += ["--model", self.model]
        self.emit("log", text="agent started")
        try:
            self.proc = subprocess.Popen(cmd, cwd=self.ws, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                         stderr=subprocess.STDOUT, text=True, start_new_session=True)
        except OSError as e:
            self.emit("log", text=f"could not start claude: {e}")
            return self._finish("undecided")
        assert self.proc.stdout is not None
        for line in self.proc.stdout:
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                if line.strip():
                    self.emit("log", text=line.strip()[:500])
                continue
            if ev.get("type") == "assistant":
                for part in ev.get("message", {}).get("content", []):
                    if part.get("type") == "text" and part["text"].strip():
                        self.emit("log", text=part["text"].strip()[:2000])
                    elif part.get("type") == "tool_use":
                        inp = part.get("input", {})
                        what = inp.get("command") or inp.get("file_path") or inp.get("pattern") or ""
                        self.emit("log", text=f"{part['name']} {pathlib.Path(what).name if '/' in str(what) else what}"[:300], tool=True)
            elif ev.get("type") == "result":
                self.emit("log", text=f"agent finished ({ev.get('subtype', '')})")
        self.proc.wait()

    # The watcher: check every new version of Proof.lean; settle on proved/refuted,
    # or when the budget runs out.
    def _watch(self):
        proof = self.ws / "Proof.lean"
        deadline = self.started + self.budget
        while self.status == "running":
            body = proof.read_text()
            if body != self.last_body:
                self.last_body = body
                self.emit("proof", text=body)
                self.emit("checking")
                r = check(self.C, self.th, body)
                if self.status != "running":
                    break
                self.emit("check", **r)
                if r["verdict"] in ("proved", "refuted"):
                    self.result = r
                    return self._finish(r["verdict"])
                continue
            if time.time() > deadline:
                return self._finish("undecided")
            agent_done = self.proc is not None and self.proc.poll() is not None
            if agent_done:
                return self._finish("undecided")
            time.sleep(0.5)

    def _finish(self, status):
        if self.status != "running":
            return
        self.status = status
        if self.proc and self.proc.poll() is None:
            try:
                os.killpg(self.proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        self.emit("done", status=status, elapsed=round(time.time() - self.started, 1),
                  proof=self.last_body, result=self.result)


JOBS = {}


def start_job(vocab, req, validate, words):
    C = vocab["contracts"].get(req.get("contract"))
    if C is None:
        raise ValueError("unknown contract")
    th = req.get("theorem") or {}
    th = {"name": th.get("name"), "target": th.get("target"), "stmt": th.get("stmt"), "tactic": "sorry",
          "pred": th.get("pred")}
    validate(vocab, C, th)
    budget = int(req.get("budget", 120))
    if not 10 <= budget <= 1800:
        raise ValueError("budget must be 10-1800 seconds")
    job = Job(req["contract"], C, th, words, budget, os.environ.get("VIBE_MODEL"))
    JOBS[job.id] = job
    job.start()
    return job


if __name__ == "__main__" and len(sys.argv) == 3 and sys.argv[1] == "check":
    ws = pathlib.Path(sys.argv[2])
    job = json.loads((ws / "job.json").read_text())
    C = load_vocab()["contracts"][job["contract"]]
    r = check(C, job["theorem"], (ws / "Proof.lean").read_text())
    for m in r["messages"]:
        where = f"Proof.lean:{m['line']}" if m["line"] else "(server's check)"
        print(f"{where}: {m['severity']}: {m['text']}")
    if r["cex"]:
        print("counterexample:", json.dumps(r["cex"]))
    print(f"VERDICT: {r['verdict']}  ({r['elapsed']}s)")
    sys.exit(0 if r["verdict"] in ("proved", "refuted") else 1)
