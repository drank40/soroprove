#!/usr/bin/env python3
"""Generate the `answer` facts of a contract model.

    python3 scripts/gen_facts.py StellarLean/LiquidityPool.lean [-o StellarLean/LiquidityPoolFacts.lean]

The input is a model in the shape of TRANSPILER_SPEC.md: storage layout
(`def X : Term T := var "X"`, `def M : Map Int := ⟨"M"⟩`), argument getters
(`def f (c : Call) : Int := …`), one `Step → Prop` per entry point whose body
is a conjunction of

    st.call.fn = "f"            the name
    st.post = <chain>           a chain of `.set` over `st.pre`, possibly through
                                `Storage`-valued helpers (`xfer`, `s1 st`, …)
    st.writes = [...]           the written keys
    st.ret = <Val>              the return value
    anything else               a guard

and a `def contract : Contract where entries := [...]`.

Nothing is specific to a contract. Each fact is read off that shape:
* the name and each guard: the projection of its conjunct (`h.2.1`, …);
* a map entry after the call: the chain read backwards. Every write to the map
  at `w` adds `only w d`, where `d` is the amount added when the written value
  is `M.read s w ± d` (read-modify-write), and `new − old` otherwise;
* the sum of a map over holders: the same changes, summed;
* a variable after the call: its last write, or its old value;
* the frame: every key outside `writes` keeps its value.
"""

import argparse
import pathlib
import re
import sys

# ------------------------------------------------------------------ tokens

TOK = re.compile(r"""
  (?P<ws>\s+)
| (?P<str>"(?:[^"\\]|\\.)*")
| (?P<num>\d+)
| (?P<proj>\.\d+)
| (?P<dot>\.[A-Za-z_][\w'!?]*)
| (?P<id>[A-Za-z_α-ω][\w'!?]*(?:\.[A-Za-z_][\w'!?]*)*)
| (?P<op>:=|=>|≠|≤|≥|∧|∨|¬|→|←|\|\||&&|!=|==|\S)
""", re.X)


class T:
    __slots__ = ("kind", "text", "sp")

    def __init__(self, kind, text, sp):
        self.kind, self.text, self.sp = kind, text, sp

    def __repr__(self):
        return self.text


def tokenize(src):
    out, pos, sp = [], 0, False
    while pos < len(src):
        m = TOK.match(src, pos)
        if not m:
            raise SyntaxError(f"cannot read {src[pos:pos + 20]!r}")
        pos = m.end()
        if m.lastgroup == "ws":
            sp = True
            continue
        out.append(T(m.lastgroup, m.group(), sp))
        sp = False
    return out


def untok(toks):
    s = ""
    for i, t in enumerate(toks):
        s += (" " if t.sp and i else "") + t.text
    return s


OPEN, CLOSE = {"(": ")", "[": "]", "⟨": "⟩"}, {")", "]", "⟩"}


def top_level(toks):
    """Indices of tokens at bracket depth 0."""
    d, out = 0, []
    for i, t in enumerate(toks):
        if t.text in OPEN:
            d += 1
        elif t.text in CLOSE:
            d -= 1
        elif d == 0:
            out.append(i)
    return out


def split_top(toks, sep):
    parts, cur, d = [], [], 0
    for t in toks:
        if t.text in OPEN:
            d += 1
        elif t.text in CLOSE:
            d -= 1
        if d == 0 and t.text == sep:
            parts.append(cur)
            cur = []
        else:
            cur.append(t)
    parts.append(cur)
    return parts


# ------------------------------------------------------------------ terms
# Only applications are parsed into trees; anything with an operator at the
# top is kept as tokens (`Raw`).

class Ident:
    def __init__(self, name): self.name = name

class Lit:
    def __init__(self, text): self.text = text

class Ctor:                       # `.var`, `.entry`, `.int`, …
    def __init__(self, name): self.name = name

class Paren:
    def __init__(self, inner): self.inner = inner

class Method:                     # `(e).set`
    def __init__(self, recv, name): self.recv, self.name = recv, name

class App:
    def __init__(self, fn, args): self.fn, self.args = fn, args

class Raw:
    def __init__(self, toks): self.toks = toks


def parse(toks):
    toks = list(toks)
    if any(toks[i].kind == "op" and toks[i].text not in OPEN and toks[i].text not in CLOSE
           for i in top_level(toks)):
        return Raw(toks)
    atoms, i = [], 0
    while i < len(toks):
        t = toks[i]
        if t.text in OPEN:
            d, j = 0, i
            while True:
                if toks[j].text in OPEN: d += 1
                elif toks[j].text in CLOSE: d -= 1
                if d == 0: break
                j += 1
            node = Paren(parse(toks[i + 1:j])) if t.text == "(" else Raw(toks[i:j + 1])
            i = j + 1
        elif t.kind == "dot" and not t.sp and atoms:
            atoms[-1] = Method(atoms[-1], t.text[1:])
            i += 1
            continue
        elif t.kind == "dot":
            node, i = Ctor(t.text), i + 1
        elif t.kind == "id":
            *pre, last = t.text.split(".")
            node = Method(Ident(".".join(pre)), last) if pre and last == "set" else Ident(t.text)
            i += 1
        else:
            node, i = Lit(t.text), i + 1
        atoms.append(node)
    if not atoms:
        return Raw([])
    return atoms[0] if len(atoms) == 1 else App(atoms[0], atoms[1:])


def strip(n):
    while isinstance(n, Paren):
        n = n.inner
    return n


def show(n):
    n0 = n
    if isinstance(n, Ident): return n.name
    if isinstance(n, Lit): return n.text
    if isinstance(n, Ctor): return n.name
    if isinstance(n, Paren): return show(n.inner) if simple(n.inner) else f"({show(n.inner)})"
    if isinstance(n, Method): return f"{show_atom(n.recv)}.{n.name}"
    if isinstance(n, App):
        fn = show(n.fn) if isinstance(n.fn, Method) else show_atom(n.fn)
        return " ".join([fn] + [show_atom(a) for a in n.args])
    if isinstance(n, Raw): return untok(n.toks)
    raise TypeError(n0)


def simple(n):
    n = strip(n)
    return isinstance(n, (Ident, Lit, Ctor)) or (isinstance(n, Raw) and n.toks and n.toks[0].text in OPEN
                                                 and len(top_level(n.toks)) == 0) or \
        (isinstance(n, Method) and simple(n.recv))


def show_atom(n):
    return show(n) if simple(n) else f"({show(strip(n))})"


def norm(n):
    """Text for comparing terms: no spaces, no parentheses."""
    return re.sub(r"[\s()]", "", show(n))


# ------------------------------------------------------------------ substitution

def subst(n, env):
    """Replace identifiers (and the head of dotted ones: `m.read`) by `env`."""
    if isinstance(n, Ident):
        head, _, rest = n.name.partition(".")
        if head not in env:
            return n
        v = env[head]
        if not rest:
            return v
        return Ident(f"{v.name}.{rest}") if isinstance(strip(v), Ident) and isinstance(v, Ident) \
            else Method(v, rest)
    if isinstance(n, Paren): return Paren(subst(n.inner, env))
    if isinstance(n, Method): return Method(subst(n.recv, env), n.name)
    if isinstance(n, App): return App(subst(n.fn, env), [subst(a, env) for a in n.args])
    if isinstance(n, Raw):
        out = []
        for t in n.toks:
            head, _, rest = t.text.partition(".")
            if t.kind == "id" and head in env:
                txt = show_atom(env[head]) + (f".{rest}" if rest else "")
                out.extend(retok(txt, t.sp))
            else:
                out.append(t)
        return Raw(out)
    return n


def retok(txt, sp):
    ts = tokenize(txt)
    if ts:
        ts[0].sp = sp
    return ts


# ------------------------------------------------------------------ the model

CMD = re.compile(r"^(?:@\[[^\]]*\]\s*)?(def|abbrev|opaque|theorem|structure|inductive|instance|"
                 r"namespace|end|open|variable|section|import|attribute)\b")


def strip_comments(src):
    out, i, depth = [], 0, 0
    while i < len(src):
        if src.startswith("/-", i):
            depth += 1; i += 2
        elif depth and src.startswith("-/", i):
            depth -= 1; i += 2
        elif depth:
            i += 1
        elif src.startswith("--", i):
            j = src.find("\n", i)
            i = len(src) if j < 0 else j
        elif src[i] == '"':
            j = i + 1
            while src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            out.append(src[i:j + 1]); i = j + 1
        else:
            out.append(src[i]); i += 1
    return "".join(out)


class Def:
    def __init__(self, name, ns, params, ty, body, opens):
        self.name, self.ns, self.params, self.ty, self.body, self.opens = name, ns, params, ty, body, opens


class Model:
    def __init__(self, path):
        self.path = pathlib.Path(path)
        src = strip_comments(self.path.read_text())
        self.defs = {}           # name relative to the contract namespace → Def
        self.order = []
        self.contract_ns = None
        self.entries = []
        ns, variables, pending_opens = [], [], []
        cmds, cur = [], None
        for line in src.splitlines():
            if CMD.match(line):
                if cur: cmds.append(cur)
                cur = line
            elif cur is not None and (line.startswith((" ", "\t")) or not line.strip()):
                cur += "\n" + line
            elif line.strip():
                if cur: cmds.append(cur)
                cur = line
        if cur: cmds.append(cur)

        for c in cmds:
            c = c.strip()
            c = re.sub(r"^@\[[^\]]*\]\s*", "", c)
            m = re.match(r"open\s+([\w.\s]+?)\s+in\b(.*)$", c, re.S)
            opens = list(pending_opens)
            if m:
                opens += m.group(1).split()
                c = m.group(2).strip()
            pending_opens = []
            if not c:                        # `open X in` on its own line: for the next command
                pending_opens = opens
                continue
            kw = c.split()[0]
            if kw == "namespace":
                name = c.split()[1]
                if self.contract_ns is None:
                    self.contract_ns = name
                else:
                    ns.append(name)
                variables.append([])
            elif kw == "end":
                if ns:
                    ns.pop()
                if variables:
                    variables.pop()
            elif kw == "variable":
                for b in re.findall(r"\(([^()]*)\)", c):
                    names, _, ty = b.partition(":")
                    variables[-1].extend((n, ty.strip()) for n in names.split())
            elif kw in ("def", "abbrev", "opaque"):
                self.add_def(c, kw, ".".join(ns), [v for vs in variables for v in vs], opens)

    def add_def(self, c, kw, ns, variables, opens):
        m = re.match(r"(?:def|abbrev|opaque)\s+(\S+)\s*(.*)$", c, re.S)
        name, rest = m.group(1), m.group(2)
        params = []
        while True:
            b = re.match(r"\s*[({\[]([^(){}\[\]]*)[)}\]]\s*", rest)
            if not b:
                break
            names, _, _ = b.group(1).partition(":")
            params += names.split()
            rest = rest[b.end():]
        ty, body = rest, ""
        found = [(k, sep) for sep in (":=", "where") if (k := top_split_text(rest, sep)) is not None]
        if found:
            k, sep = min(found)
            ty, body = rest[:k], rest[k + len(sep):]
            if sep == "where":
                body = "where " + body
        ty = ty.strip().lstrip(":").strip()
        body = body.strip()
        # Section variables used in the body come first, as Lean adds them.
        used = [v for v, _ in variables if re.search(rf"(?<![\w.]){re.escape(v)}(?![\w'])", body)]
        full = f"{ns}.{name}" if ns else name
        d = Def(full, ns, used + params, ty, body, opens)
        self.defs[full] = d
        self.order.append(full)
        if full == "contract":
            m = re.search(r"entries\s*:=\s*\[([^\]]*)\]", body)
            self.entries = [e.strip() for e in m.group(1).split(",") if e.strip()]

    def resolve(self, name, opens, ns=""):
        cands = []
        parts = ns.split(".") if ns else []
        for k in range(len(parts), -1, -1):
            pre = ".".join(parts[:k])
            cands.append(f"{pre}.{name}" if pre else name)
        cands += [f"{o}.{name}" for o in opens]
        for c in cands:
            if c in self.defs:
                return c
        return None

    def qualify(self, n, opens, ns=""):
        """Write every identifier naming a def of the model in full."""
        def q(name):
            parts = name.split(".")
            for k in range(len(parts), 0, -1):
                r = self.resolve(".".join(parts[:k]), opens, ns)
                if r:
                    return ".".join([r] + parts[k:])
            return name
        if isinstance(n, Ident): return Ident(q(n.name))
        if isinstance(n, Paren): return Paren(self.qualify(n.inner, opens, ns))
        if isinstance(n, Method): return Method(self.qualify(n.recv, opens, ns), n.name)
        if isinstance(n, App): return App(self.qualify(n.fn, opens, ns), [self.qualify(a, opens, ns) for a in n.args])
        if isinstance(n, Raw):
            out = []
            for t in n.toks:
                if t.kind == "id":
                    out.append(T("id", q(t.text), t.sp))
                else:
                    out.append(t)
            return Raw(out)
        return n

    # -- what the model declares

    def maps(self):
        """Lean name → storage name, for `Map Int`."""
        out = {}
        for k in self.order:
            d = self.defs[k]
            m = re.fullmatch(r'⟨"([^"]+)"⟩', d.body)
            if d.ty == "Map Int" and m:
                out[k] = m.group(1)
        return out

    def vars(self):
        """Lean name → (storage name, type)."""
        out = {}
        for k in self.order:
            d = self.defs[k]
            m = re.fullmatch(r'Term\s+(\w+)', d.ty)
            v = re.fullmatch(r'var\s+"([^"]+)"', d.body)
            if m and v:
                out[k] = (v.group(1), m.group(1))
        return out

    def args(self):
        return [k for k in self.order
                if self.defs[k].ty == "Int" and len(self.defs[k].params) == 1
                and re.search(r'\.arg\s+"', self.defs[k].body)]

    def storage_defs(self):
        return [k for k in self.order if self.defs[k].ty == "Storage"]


def top_split_text(s, sep):
    toks = tokenize(s)
    idx = top_level(toks)
    pos = 0
    offs = []
    for t in toks:
        j = s.index(t.text, pos)
        offs.append(j)
        pos = j + len(t.text)
    for i in idx:
        if toks[i].text == sep:
            return offs[i]
    return None


# ------------------------------------------------------------------ one entry point

class Write:
    def __init__(self, key, val, recv):
        self.key, self.val, self.recv = key, val, recv


class Entry:
    def __init__(self, model, name):
        self.model, self.name = model, name
        d = model.defs[name]
        body = d.body
        m = re.match(r"fun\s+st\s*=>\s*(.*)$", body, re.S)
        if not m:
            raise SyntaxError(f"{name}: expected `fun st => …`")
        body = m.group(1)
        env = {}
        while True:
            lm = re.match(r"\s*let\s+(\w+)\s*:=\s*([^\n]*)\n", body)
            if not lm:
                break
            env[lm.group(1)] = model.qualify(parse(tokenize(lm.group(2))), d.opens, d.ns)
            body = body[lm.end():]
        toks = tokenize(body)
        self.conj = []
        for part in split_top(toks, "∧"):
            n = model.qualify(subst(parse(part), env), d.opens, d.ns)
            self.conj.append(n)
        self.fn = self.post = self.writes = self.ret = None
        self.guards = []
        for i, c in enumerate(self.conj):
            t = untok(c.toks) if isinstance(c, Raw) else show(c)
            lhs = re.match(r"st\.(call\.fn|post|writes|ret)\s*=\s*", t)
            field = lhs.group(1) if lhs else None
            rhs = None
            if field:
                rhs = parse(split_top(c.toks, "=")[1]) if isinstance(c, Raw) else None
            if field == "call.fn": self.fn = (i, t)
            elif field == "post": self.post = (i, rhs)
            elif field == "writes": self.writes = (i, rhs)
            elif field == "ret": self.ret = (i, t)
            else: self.guards.append((i, t))
        if self.post is None or self.writes is None:
            raise SyntaxError(f"{name}: no `st.post =` or `st.writes =`")
        self.chain = self.walk(self.post[1])

    def proj(self, i):
        n = len(self.conj)
        return "h" + ".2" * i + (".1" if i < n - 1 else "")

    def walk(self, n):
        """The writes of a storage term over `st.pre`, in order."""
        M = self.model
        n = strip(n)
        if isinstance(n, App) and isinstance(n.fn, Method) and n.fn.name == "set" and len(n.args) == 2:
            ws = self.walk(n.fn.recv)
            return ws + [Write(self.key(n.args[0]), self.val(n.args[1]), n.fn.recv)]
        if isinstance(n, Ident) and n.name == "st.pre":
            return []
        if isinstance(n, Raw) and untok(n.toks) == "st.pre":
            return []
        head, args = (n.fn, n.args) if isinstance(n, App) else (n, [])
        if isinstance(head, Ident) and head.name in M.defs and M.defs[head.name].ty == "Storage":
            d = M.defs[head.name]
            body = M.qualify(parse(tokenize(d.body)), d.opens, d.ns)
            env = dict(zip(d.params, args))
            if len(args) < len(d.params):
                raise SyntaxError(f"{self.name}: {head.name} partly applied")
            return self.walk(subst(body, env))
        raise SyntaxError(f"{self.name}: cannot read the storage term `{show(n)}`")

    def key(self, n):
        n = strip(n)
        if isinstance(n, App) and isinstance(n.fn, Ctor):
            if n.fn.name == ".var":
                return ("var", strip(n.args[0]).text.strip('"'), None)
            if n.fn.name == ".entry":
                m = strip(n.args[0])
                if isinstance(m, Lit):
                    name = m.text.strip('"')
                elif isinstance(m, Ident) and m.name.endswith(".name"):
                    name = self.model.maps()[m.name[:-5]]
                else:
                    raise SyntaxError(f"{self.name}: map of `{show(n)}`")
                return ("entry", name, n.args[1])
        raise SyntaxError(f"{self.name}: cannot read the key `{show(n)}`")

    @staticmethod
    def val(n):
        n = strip(n)
        if isinstance(n, Ctor) and n.name == ".none":
            return ("none", None)
        if isinstance(n, App) and isinstance(n.fn, Ctor) and n.fn.name in (".int", ".addr"):
            return (n.fn.name[1:], n.args[0])
        raise SyntaxError(f"cannot read the value `{show(n)}`")

    # -- what each map entry gains

    def changes(self, mapname, lean):
        """[(address, sign, amount)]: the map at `a` after the call is the map
        before plus `sign * amount` for each write at an address equal to `a`."""
        out = []
        for i, w in enumerate(self.chain):
            if w.key[0] != "entry" or w.key[1] != mapname:
                continue
            addr = strip(w.key[2])
            kind, v = w.val
            if kind != "int":
                raise SyntaxError(f"{self.name}: non-number written to {mapname}")
            rmw = self.read_modify_write(v, lean, addr, w.recv)
            if rmw:
                out.append((show(addr), *rmw))
                continue
            earlier = any(x.key[0] == "entry" and x.key[1] == mapname for x in self.chain[:i])
            old = show_atom(w.recv) if earlier else "st.pre"
            out.append((show(addr), "+", f"{show(strip(v))} - {lean}.read {old} {show_atom(addr)}"))
        return out

    @staticmethod
    def read_modify_write(v, lean, addr, recv):
        v = strip(v)
        if not isinstance(v, Raw):
            return None
        ops = [i for i in top_level(v.toks) if v.toks[i].text in ("+", "-")]
        if len(ops) != 1:
            return None
        k = ops[0]
        lhs = strip(parse(v.toks[:k]))
        if not (isinstance(lhs, App) and isinstance(lhs.fn, Ident) and lhs.fn.name == f"{lean}.read"
                and len(lhs.args) == 2):
            return None
        if norm(lhs.args[0]) != norm(recv) or norm(lhs.args[1]) != norm(addr):
            return None
        return (v.toks[k].text, show(strip(parse(v.toks[k + 1:]))))


# ------------------------------------------------------------------ output

def facts(model, module):
    M = model
    maps, vars_ = M.maps(), M.vars()
    sdefs = M.storage_defs()
    entries, skipped = [], []
    for name in M.entries:
        try:
            entries.append(Entry(M, name))
        except SyntaxError as err:
            print(f"warning: no effect facts for `{name}`: {err}", file=sys.stderr)
            skipped.append(name)

    def nm(x):
        """A fact's name, kept apart from the model's own names."""
        return x + "_fact" if x in M.defs else x
    L = []
    w = L.append
    w(f"import {module}")
    w("import StellarLean.Answer")
    w("")
    w("/-")
    w(f"  Facts about `{M.path.name}` for the `answer` tactic.")
    w("")
    w(f"  GENERATED by `scripts/gen_facts.py {M.path.as_posix()}`: do not edit, rerun it.")
    w("  Each fact is read off the shape of an entry point (see the script).")
    w("-/")
    w("")
    w("-- Each proof unfolds every storage helper of the model, used or not.")
    w("set_option linter.unusedSimpArgs false")
    w("")
    w(f"namespace {M.contract_ns}")
    w("")
    w("open Query")
    w("open Spec (Addr)")
    w("")

    # Entry points
    w("/-! ## Entry points -/")
    w("")
    alts = " ∨ ".join(f"{e} st" for e in M.entries)
    pats = " | ".join("rfl" for _ in M.entries)
    w("@[answer →] theorem step_of_contract {st : Step} (h : contract.Steps st) :")
    w(f"    {alts} := by")
    w("  obtain ⟨e, he, hst⟩ := h")
    w("  simp only [contract, List.mem_cons, List.not_mem_nil, or_false] at he")
    w(f"  rcases he with {pats} <;> simp_all")
    w("")

    # Storage layout
    w("/-! ## Storage layout -/")
    w("")
    for lean, (name, ty) in vars_.items():
        w(f"@[answer =] theorem get_{lean} (c : Call) (s : Storage) :")
        w(f"    {lean}.get c s = (read s \"{name}\" : {ty}) := rfl")
    w("")
    w("/-- A variable is a storage slot. -/")
    w("@[answer =] theorem read_var [Stored α] (s : Storage) (n : String) :")
    w("    (read s n : α) = Stored.ofVal (s (.var n)) := rfl")
    w("")

    # Arguments
    w("/-! ## Arguments -/")
    w("")
    if M.args():
        w(f"attribute [answer] {' '.join(M.args())}")
        w("")

    # Effects
    w("/-! ## Each entry point -/")
    w("")
    for name in skipped:
        w(f"-- `{name}`: not in the shape the generator reads; its facts are left out.")
    if skipped:
        w("")
    for e in entries:
        written_keys = []
        for t in split_top(e.writes[1].toks[1:-1], ",") if isinstance(e.writes[1], Raw) else []:
            if t:
                k = untok(t).strip()
                if k not in written_keys:
                    written_keys.append(k)
        w(f"section {e.name}")
        w(f"variable {{st : Step}} (h : {e.name} st)")
        w("include h")
        w("")
        if e.fn:
            w(f"@[answer →] theorem {nm(e.name + '_fn')} : {e.fn[1]} := {e.proj(e.fn[0])}")
        for k, (i, t) in enumerate(e.guards, 1):
            w(f"@[answer →] theorem {nm(f'{e.name}_guard{k}')} : {t} := {e.proj(i)}")
        if e.ret:
            w(f"@[answer →] theorem {nm(e.name + '_ret')} : {e.ret[1]} := {e.proj(e.ret[0])}")
        w("")
        post = nm(e.name + "_post")
        w(f"theorem {post} : st.post = {show(e.post[1])} := {e.proj(e.post[0])}")
        w("")
        # Unfold to `Storage.set` over map names that are string literals.
        unfold = ", ".join([f"{post} h"] + sdefs + list(maps))
        keys = "Key.entry.injEq, Key.var.injEq, reduceCtorEq, false_and, and_false, ite_false"
        # Maps
        for lean, name in maps.items():
            ch = e.changes(name, lean)
            rhs = f"{lean}.read st.pre a" + "".join(
                f" {sign} (if a = {addr} then {amt} else 0)" for addr, sign, amt in ch)
            after = nm(f"{e.name}_{lean}")
            w(f"@[answer =] theorem {after} (a : Addr) :")
            w(f"    {lean}.read st.post a = {rhs} := by")
            w(f"  (simp only [{unfold}, Map.read, Storage.set, {keys}]) <;> grind [ofVal_int]")
            srhs = f"(hs.map ({lean}.read st.pre)).sum" + "".join(
                f" {sign} (hs.map (only {_atom(addr)} ({amt}))).sum" for addr, sign, amt in ch)
            w(f"@[answer =] theorem {nm(f'{e.name}_{lean}_sum')} (hs : List Addr) :")
            w(f"    (hs.map ({lean}.read st.post)).sum = {srhs} := by")
            w(f"  induction hs <;> grind [only, {after}]")
        # Variables
        last = {}
        for wr in e.chain:
            if wr.key[0] == "var":
                last[wr.key[1]] = wr.val
        names = [n for n, _ in vars_.values()] + [n for n in last if n not in [v for v, _ in vars_.values()]]
        for n in names:
            if n in last:
                kind, v = last[n]
                rhs = ".none" if kind == "none" else f".{kind} {show_atom(v)}"
            else:
                rhs = f"st.pre (.var \"{n}\")"
            w(f"@[answer =] theorem {nm(f'{e.name}_var_{n}')} : st.post (.var \"{n}\") = {rhs} := by")
            w(f"  simp [{unfold}, Storage.set]")
        # Frame
        hyps = " ".join(f"(h{k} : k ≠ {key})" for k, key in enumerate(written_keys, 1))
        w(f"@[answer =] theorem {nm(e.name + '_frame')} (k : Key) {hyps} :".replace("  ", " "))
        w("    st.post k = st.pre k :=")
        w(f"  contract.framed _ (by simp [contract]) st h k (by")
        w(f"    rw [{e.proj(e.writes[0])}]; simp [{', '.join(f'h{k}' for k in range(1, len(written_keys) + 1))}])"
          .replace("simp []", "simp"))
        w("")
        w(f"end {e.name}")
        w("")
    w(f"end {M.contract_ns}")
    return "\n".join(L) + "\n"


def _atom(t):
    return t if re.fullmatch(r"[\w.']+", t) else f"({t})"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("model")
    ap.add_argument("-o", "--out")
    a = ap.parse_args()
    model = Model(a.model)
    p = pathlib.Path(a.model)
    module = ".".join(p.with_suffix("").parts[-2:])
    text = facts(model, module)
    if a.out:
        pathlib.Path(a.out).write_text(text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
