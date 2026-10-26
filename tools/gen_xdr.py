#!/usr/bin/env python3
"""Generate SorobanLean/Xdr/{Types,Codec}.lean from the pinned stellar-xdr 30.0.0
definitions (vendor/crates/stellar-xdr-30.0.0/xdr-definitions-json/xdr.json).

Codec semantics transcribe stellar-xdr 30.0.0's runtime (src/generated.rs):
* every read/write of any type is wrapped in `with_limited_depth` (:440-453):
  fails with DepthLimitExceeded when the remaining depth is 0, otherwise the
  nested reads see depth-1;
* numeric builtins consume 4/8 bytes of the length limit (:426-434, :783-880);
* bool reads a u32 and is `true` iff it equals 1 (:903-911) — any other value is false;
* Option reads a u32 flag, 0/1, otherwise Invalid (:924-940);
* fixed opaque: consume N + pad, zero padding (:984-1003);
* fixed arrays: N elements (:1017-1030);
* VecM<u8>/BytesM/StringM: u32 len, LengthExceedsMax if > MAX, consume len + pad,
  zero padding (:1523-1548, :2003-2027, :2477-2501);
* VecM<T>: u32 len, LengthExceedsMax if > MAX, then the elements (:1570-1610);
* enums read an i32 and fail with Invalid on an unknown value; unions read the
  discriminant then the arm, Invalid on an unknown case (generated/*.rs);
* typedefs of the four numeric builtins are plain aliases (no depth); every other
  typedef is a newtype whose read adds one depth level (generated/{uint32,hash}.rs).
"""
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "vendor/crates/stellar-xdr-30.0.0/xdr-definitions-json/xdr.json"
OUT_T = ROOT / "SorobanLean/Xdr/Types.lean"
OUT_C = ROOT / "SorobanLean/Xdr/Codec.lean"

KW = {"end", "fun", "let", "in", "do", "if", "then", "else", "match", "with", "at", "by", "have",
      "show", "from", "where", "open", "import", "def", "theorem", "structure", "inductive", "class",
      "instance", "namespace", "section", "variable", "universe", "for", "return", "mut", "try",
      "catch", "type", "Type", "export", "macro", "syntax", "local", "private", "protected", "partial",
      "unsafe", "notation", "infix", "prefix", "deriving", "extends", "this", "true", "false", "nomatch",
      "fix", "suffices", "calc", "obtain", "set_option", "attribute", "axiom", "abbrev", "example",
      "opaque", "mutual", "noncomputable", "omit", "include", "termination_by", "decreasing_by"}

NUMERIC = {"int": "Int32", "unsigned_int": "UInt32", "hyper": "Int64", "unsigned_hyper": "UInt64"}
U32MAX = 4294967295


def ident(n):
    return f"«{n}»" if n in KW else n


def main():
    j = json.loads(SRC.read_text())
    defs = {d["name"]: d for d in j["definitions"]}
    order = [d["name"] for d in j["definitions"]]
    consts = {d["name"]: d for d in j["definitions"] if d["kind"] == "const"}
    tydefs = [n for n in order if defs[n]["kind"] != "const"]

    def const_val(v):
        if isinstance(v, dict):  # {"kind":"const_ref","name":...} or literal
            if "name" in v and v["name"] in consts:
                return const_val(consts[v["name"]]["value"])
            if "value" in v:
                return const_val(v["value"])
        return v

    # --- dependency graph -------------------------------------------------
    def refs(t, acc):
        if isinstance(t, dict):
            if t.get("kind") == "ref":
                acc.add(t["name"])
            for v in t.values():
                refs(v, acc)
        elif isinstance(t, list):
            for v in t:
                refs(v, acc)
        return acc

    deps = {}
    for n in tydefs:
        d = defs[n]
        acc = set()
        for k in ("type", "fields", "arms", "discriminant"):
            refs(d.get(k), acc)
        deps[n] = {x for x in acc if x in defs and defs[x]["kind"] != "const"}

    # Tarjan SCC
    index = {}
    low = {}
    stack = []
    onst = set()
    sccs = []
    counter = [0]
    sys.setrecursionlimit(10000)

    def strong(v):
        index[v] = low[v] = counter[0]
        counter[0] += 1
        stack.append(v)
        onst.add(v)
        for w in sorted(deps[v]):
            if w not in index:
                strong(w)
                low[v] = min(low[v], low[w])
            elif w in onst:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            comp = []
            while True:
                w = stack.pop()
                onst.discard(w)
                comp.append(w)
                if w == v:
                    break
            sccs.append(sorted(comp, key=order.index))

    for n in tydefs:
        if n not in index:
            strong(n)
    # sccs come out in reverse topological order of the condensation: dependencies first
    scc_of = {}
    for i, c in enumerate(sccs):
        for n in c:
            scc_of[n] = i
    recursive = {n for c in sccs for n in c if len(c) > 1 or n in deps[n]}

    # --- Lean type expressions -------------------------------------------
    def texpr(t, inline_in=None):
        k = t["kind"]
        if k in NUMERIC:
            return NUMERIC[k]
        if k == "bool":
            return "Bool"
        if k in ("opaque_fixed", "opaque_var", "string"):
            return "ByteArray"
        if k in ("var_array", "array"):
            return f"(Array {texpr(t['element'], inline_in)})"
        if k == "optional":
            return f"(Option {texpr(t['element'] if 'element' in t else t['type'], inline_in)})"
        if k == "ref":
            n = t["name"]
            d = defs[n]
            if inline_in is not None and d["kind"] == "typedef" and scc_of.get(n) == inline_in:
                return texpr(d["type"], inline_in)
            return ident(n)
        raise ValueError(f"unknown type kind {k}")

    def disc_values(d):
        """(case value, constructor name, arm) for each union case."""
        dt = d["discriminant"]["type"]
        out = []
        for arm in d["arms"]:
            for c in arm["cases"]:
                cname = c.get("name") or f"v{c['value']}"
                out.append((c["value"], cname, arm))
        return out

    # ---------------------------------------------------------------------
    T = []
    w = T.append
    w("-- GENERATED by tools/gen_xdr.py from stellar-xdr 30.0.0 xdr-definitions-json/xdr.json. DO NOT EDIT.")
    w("-- xdr files: " + ", ".join(f"{f['name']}@{f['sha256'][:12]}" for f in j["files"]))
    w("set_option maxHeartbeats 4000000")
    w("namespace Xdr")
    w("")
    for n, c in consts.items():
        w(f"def {ident(n)} : Nat := {const_val(c['value'])}")
    w("")

    def emit_def(n, inline_in=None, in_mutual=False):
        d = defs[n]
        k = d["kind"]
        if k == "typedef":
            w(f"abbrev {ident(n)} := {texpr(d['type'])}")
        elif k == "enum":
            w(f"inductive {ident(n)} where")
            for m in d["members"]:
                w(f"  | {ident(m['name'])}")
            w("  deriving DecidableEq, Repr, Inhabited")
        elif k == "struct":
            w(f"structure {ident(n)} where")
            for f in d["fields"]:
                w(f"  {ident(f['name'])} : {texpr(f['type'], inline_in)}")
            if not in_mutual:
                w("  deriving Inhabited")
        elif k == "union":
            w(f"inductive {ident(n)} where")
            for v, cname, arm in disc_values(d):
                if arm.get("type") is None:
                    w(f"  | {ident(cname)}")
                else:
                    fname = arm.get("name") or "val"
                    w(f"  | {ident(cname)} ({ident(fname)} : {texpr(arm['type'], inline_in)})")
            if not in_mutual:
                w("  deriving Inhabited")
        w("")

    deferred_abbrevs = []
    for ci, comp in enumerate(sccs):
        if len(comp) == 1 and comp[0] not in recursive:
            emit_def(comp[0])
            continue
        members = [n for n in comp if defs[n]["kind"] != "typedef"]
        tds = [n for n in comp if defs[n]["kind"] == "typedef"]
        w("mutual")
        for n in members:
            emit_def(n, inline_in=ci, in_mutual=True)
        w("end")
        w("")
        for n in members:
            d = defs[n]
            # Inhabited: first constructor whose fields are all non-recursive, else first void arm
            if d["kind"] == "union":
                cands = disc_values(d)
                pick = None
                for v, cname, arm in cands:
                    if arm.get("type") is None:
                        pick = f".{ident(cname)}"
                        break
                if pick is None:
                    for v, cname, arm in cands:
                        t = arm["type"]
                        if t["kind"] in ("var_array", "optional") or (t["kind"] in NUMERIC) or t["kind"] in ("bool", "opaque_var", "opaque_fixed", "string"):
                            pick = f"(.{ident(cname)} default)"
                            break
                if pick is None:
                    v, cname, arm = cands[0]
                    pick = f"(.{ident(cname)} default)"
                deferred_abbrevs.append(f"instance : Inhabited {ident(n)} := ⟨{pick}⟩")
        for n in tds:
            deferred_abbrevs.append(f"abbrev {ident(n)} := {texpr(defs[n]['type'])}")
        # struct Inhabited after unions are inhabited
        for n in members:
            if defs[n]["kind"] == "struct":
                flds = ", ".join("default" for _ in defs[n]["fields"])
                deferred_abbrevs.append(f"instance : Inhabited {ident(n)} := ⟨{{ {flds} }}⟩" if False else f"instance : Inhabited {ident(n)} := ⟨⟨{flds}⟩⟩")
        for a in deferred_abbrevs:
            w(a)
        w("")
        deferred_abbrevs = []

    # enum helpers
    for n in tydefs:
        d = defs[n]
        if d["kind"] != "enum":
            continue
        w(f"def {ident(n)}.toI32 : {ident(n)} → Int32")
        for m in d["members"]:
            w(f"  | .{ident(m['name'])} => {m['value']}")
        w(f"def {ident(n)}.ofI32? (i : Int32) : Option {ident(n)} :=")
        w("  match i.toInt with")
        for m in d["members"]:
            w(f"  | {m['value']} => some .{ident(m['name'])}")
        w("  | _ => none")
        w("")
    w("end Xdr")
    OUT_T.write_text("\n".join(T) + "\n")

    # ---------------------------------------------------------------------
    # Codec. Every reader/writer takes (fu : fuel, d : remaining depth). Fuel strictly
    # decreases on every call (termination only; exhausting it is a Lean-side error
    # that never corresponds to stellar-xdr behaviour). Depth follows `with_limited_depth`.
    C = []
    w = C.append
    w("-- GENERATED by tools/gen_xdr.py. DO NOT EDIT. See the generator header for semantics.")
    w("import SorobanLean.Xdr.Types")
    w("import SorobanLean.Xdr.Runtime")
    w("set_option maxHeartbeats 4000000")
    w("set_option maxRecDepth 8192")
    w("namespace Xdr")
    w("open Xdr.Rt")
    w("")

    def maxsz(t):
        m = t.get("max_size", t.get("max_count"))
        if m is None:
            return U32MAX
        return const_val(m)

    helpers = []  # (name, kind, t) generated per composite occurrence within the current block
    hcount = [0]

    def newh(kind, t):
        hcount[0] += 1
        nm = f"h{hcount[0]}"
        helpers.append((nm, kind, t))
        return nm

    def rd(t):
        """Reader expression (a function Nat → Nat → R τ) for type t."""
        k = t["kind"]
        if k == "int": return "rdI32"
        if k == "unsigned_int": return "rdU32"
        if k == "hyper": return "rdI64"
        if k == "unsigned_hyper": return "rdU64"
        if k == "bool": return "rdBool"
        if k == "opaque_fixed": return f"(rdOpaqueFixed {const_val(t['size'])})"
        if k in ("opaque_var", "string"): return f"(rdOpaqueVar {maxsz(t)})"
        if k in ("var_array", "array", "optional"): return "rd_" + newh(k, t)
        if k == "ref": return f"rd_{t['name']}"
        raise ValueError(k)

    def wr(t):
        k = t["kind"]
        if k == "int": return "wrI32"
        if k == "unsigned_int": return "wrU32"
        if k == "hyper": return "wrI64"
        if k == "unsigned_hyper": return "wrU64"
        if k == "bool": return "wrBool"
        if k == "opaque_fixed": return f"(wrOpaqueFixed {const_val(t['size'])})"
        if k in ("opaque_var", "string"): return f"(wrOpaqueVar {maxsz(t)})"
        if k in ("var_array", "array", "optional"): return "wr_" + newh(k, t)
        if k == "ref": return f"wr_{t['name']}"
        raise ValueError(k)

    def emit_helpers(prefix, out):
        i = 0
        while i < len(helpers):
            nm, k, t = helpers[i]
            i += 1
            el = t.get("element") or t.get("type")
            ty = texpr(t)
            if k == "var_array":
                er = rd(el); ew = wr(el); ety = texpr(el); mx = maxsz(t)
                out.append(f"def rd_{nm} : Nat → Nat → R {ty}")
                out.append(f"  | 0, _ => fuelOut | _, 0 => depthExceeded")
                out.append(f"  | fu + 1, d + 1 => do")
                out.append(f"    let n ← rdU32 fu d")
                out.append(f"    if n.toNat > {mx} then lengthExceedsMax else rdl_{nm} fu d n.toNat #[]")
                out.append(f"def rdl_{nm} : Nat → Nat → Nat → Array {ety} → R {ty}")
                out.append(f"  | 0, _, _, _ => fuelOut")
                out.append(f"  | _ + 1, _, 0, acc => pure acc")
                out.append(f"  | fu + 1, d, n + 1, acc => do let e ← {er} fu d; rdl_{nm} fu d n (acc.push e)")
                out.append(f"def wr_{nm} : Nat → Nat → {ty} → W")
                out.append(f"  | 0, _, _ => wFuelOut | _, 0, _ => wDepthExceeded")
                out.append(f"  | fu + 1, d + 1, x => if x.size > {mx} then wLengthExceedsMax else wSeq [wrU32 fu d x.size.toUInt32, wrl_{nm} fu d x.toList]")
                out.append(f"def wrl_{nm} : Nat → Nat → List {ety} → W")
                out.append(f"  | 0, _, _ => wFuelOut")
                out.append(f"  | _ + 1, _, [] => wNil")
                out.append(f"  | fu + 1, d, e :: es => wSeq [{ew} fu d e, wrl_{nm} fu d es]")
            elif k == "array":
                er = rd(el); ew = wr(el); ety = texpr(el); cnt = const_val(t["count"])
                out.append(f"def rd_{nm} : Nat → Nat → R {ty}")
                out.append(f"  | 0, _ => fuelOut | _, 0 => depthExceeded")
                out.append(f"  | fu + 1, d + 1 => rdl_{nm} fu d {cnt} #[]")
                out.append(f"def rdl_{nm} : Nat → Nat → Nat → Array {ety} → R {ty}")
                out.append(f"  | 0, _, _, _ => fuelOut")
                out.append(f"  | _ + 1, _, 0, acc => pure acc")
                out.append(f"  | fu + 1, d, n + 1, acc => do let e ← {er} fu d; rdl_{nm} fu d n (acc.push e)")
                out.append(f"def wr_{nm} : Nat → Nat → {ty} → W")
                out.append(f"  | 0, _, _ => wFuelOut | _, 0, _ => wDepthExceeded")
                out.append(f"  | fu + 1, d + 1, x => if x.size != {cnt} then wInvalid else wrl_{nm} fu d x.toList")
                out.append(f"def wrl_{nm} : Nat → Nat → List {ety} → W")
                out.append(f"  | 0, _, _ => wFuelOut")
                out.append(f"  | _ + 1, _, [] => wNil")
                out.append(f"  | fu + 1, d, e :: es => wSeq [{ew} fu d e, wrl_{nm} fu d es]")
            elif k == "optional":
                er = rd(el); ew = wr(el)
                out.append(f"def rd_{nm} : Nat → Nat → R {ty}")
                out.append(f"  | 0, _ => fuelOut | _, 0 => depthExceeded")
                out.append(f"  | fu + 1, d + 1 => do")
                out.append(f"    let flag ← rdU32 fu d")
                out.append(f"    if flag == 0 then pure none else if flag == 1 then (do let e ← {er} fu d; pure (some e)) else invalid")
                out.append(f"def wr_{nm} : Nat → Nat → {ty} → W")
                out.append(f"  | 0, _, _ => wFuelOut | _, 0, _ => wDepthExceeded")
                out.append(f"  | fu + 1, d + 1, none => wrU32 fu d 0")
                out.append(f"  | fu + 1, d + 1, some e => wSeq [wrU32 fu d 1, {ew} fu d e]")

    def emit_codec(n, out):
        d = defs[n]
        k = d["kind"]
        N = ident(n)
        hdrR = [f"def rd_{n} : Nat → Nat → R {N}", "  | 0, _ => fuelOut | _, 0 => depthExceeded"]
        hdrW = [f"def wr_{n} : Nat → Nat → {N} → W", "  | 0, _, _ => wFuelOut | _, 0, _ => wDepthExceeded"]
        if k == "typedef":
            if d["type"]["kind"] in NUMERIC:
                out.append(f"def rd_{n} : Nat → Nat → R {N} := {rd(d['type'])}")
                out.append(f"def wr_{n} : Nat → Nat → {N} → W := {wr(d['type'])}")
            else:
                out += hdrR + [f"  | fu + 1, d + 1 => {rd(d['type'])} fu d"]
                out += hdrW + [f"  | fu + 1, d + 1, x => {wr(d['type'])} fu d x"]
        elif k == "enum":
            out += hdrR + [f"  | fu + 1, d + 1 => do",
                           f"    let i ← rdI32 fu d",
                           f"    match {N}.ofI32? i with | some e => pure e | none => invalid"]
            out += hdrW + [f"  | fu + 1, d + 1, x => wrI32 fu d x.toI32"]
        elif k == "struct":
            if not d["fields"]:
                out += hdrR + ["  | _ + 1, _ + 1 => pure {}"]
                out += hdrW + ["  | _ + 1, _ + 1, _ => wNil"]
            else:
                out += hdrR + ["  | fu + 1, d + 1 => do"]
                for f in d["fields"]:
                    out.append(f"    let {ident('f_' + f['name'])} ← {rd(f['type'])} fu d")
                fl = ", ".join(f"{ident(f['name'])} := {ident('f_' + f['name'])}" for f in d["fields"])
                out.append(f"    pure {{ {fl} }}")
                out += hdrW + ["  | fu + 1, d + 1, x => wSeq [" + ", ".join(f"{wr(f['type'])} fu d x.{ident(f['name'])}" for f in d["fields"]) + "]"]
        elif k == "union":
            dt = d["discriminant"]["type"]
            byref = dt["kind"] == "ref" and defs[dt["name"]]["kind"] == "enum"
            if byref:
                rdisc = f"rd_{dt['name']}"
            elif dt["kind"] == "ref":
                rdisc = f"rd_{dt['name']}"
            else:
                rdisc = {"int": "rdI32", "unsigned_int": "rdU32"}[dt["kind"]]
            out += hdrR + [f"  | fu + 1, d + 1 => do", f"    let disc ← {rdisc} fu d", "    match disc with"]
            for v, cname, arm in disc_values(d):
                pat = f".{ident(cname)}" if byref else f"{v}"
                if arm.get("type") is None:
                    out.append(f"    | {pat} => pure .{ident(cname)}")
                else:
                    out.append(f"    | {pat} => do let a ← {rd(arm['type'])} fu d; pure (.{ident(cname)} a)")
            covered = {c for _, c, _ in disc_values(d)}
            if not byref or covered != {m["name"] for m in defs[dt["name"]]["members"]}:
                out.append("    | _ => invalid")
            out += hdrW
            for v, cname, arm in disc_values(d):
                if byref:
                    dw = f"wr_{dt['name']} fu d .{ident(cname)}"
                elif dt["kind"] == "ref":
                    dw = f"wr_{dt['name']} fu d {v}"
                else:
                    dw = {"int": "wrI32", "unsigned_int": "wrU32"}[dt["kind"]] + f" fu d {v}"
                if arm.get("type") is None:
                    out.append(f"  | fu + 1, d + 1, .{ident(cname)} => {dw}")
                else:
                    out.append(f"  | fu + 1, d + 1, .{ident(cname)} a => wSeq [{dw}, {wr(arm['type'])} fu d a]")
        out.append("")

    for ci, comp in enumerate(sccs):
        helpers.clear()
        block = []
        for n in comp:
            emit_codec(n, block)
        hb = []
        emit_helpers("", hb)
        need_mutual = len(comp) > 1 or comp[0] in recursive or hb
        if need_mutual:
            w("mutual")
        for l in hb + [""] + block:
            w(l)
        if need_mutual:
            w("end")
            w("")

    # by-name round trip (decode to end, re-encode) used by the differential test
    w("def roundTripTable : Array (String × (ByteArray → Except Err ByteArray)) := #[")
    w(",\n".join(f"  ({json.dumps(n)}, fun b => (decodeToEnd rd_{n} b).bind (encode wr_{n}))" for n in tydefs))
    w("]")
    w("")
    w("def roundTripByName (name : String) (b : ByteArray) : Option (Except Err ByteArray) :=")
    w("  (roundTripTable.find? (·.1 == name)).map fun (_, f) => f b")
    w("")
    w("def allTypeNames : Array String := #[" + ", ".join(json.dumps(n) for n in tydefs) + "]")
    w("")
    # Rust `#[derive(Ord)]` comparisons for non-recursive types: enum/union variants in
    # declaration order, struct fields lexicographically, Option None < Some,
    # Vec/arrays/bytes lexicographic, integers numerically (signed where signed).
    w("namespace Ord")
    w("def lexBytes (a b : ByteArray) : Ordering := compare a.toList b.toList")
    w("def lexArr {α} (c : α → α → Ordering) : List α → List α → Ordering")
    w("  | [], [] => .eq | [], _ => .lt | _, [] => .gt")
    w("  | x :: xs, y :: ys => match c x y with | .eq => lexArr c xs ys | o => o")
    w("def thenCmp (a : Ordering) (b : Unit → Ordering) : Ordering := match a with | .eq => b () | o => o")
    def oc(t, a, b):
        k = t["kind"]
        if k in ("int", "hyper"): return f"(compare {a}.toInt {b}.toInt)"
        if k in ("unsigned_int", "unsigned_hyper"): return f"(compare {a}.toNat {b}.toNat)"
        if k == "bool": return f"(compare {a} {b})"
        if k in ("opaque_fixed", "opaque_var", "string"): return f"(lexBytes {a} {b})"
        if k in ("var_array", "array"):
            return f"(lexArr (fun x y => {oc(t['element'], 'x', 'y')}) {a}.toList {b}.toList)"
        if k == "optional":
            inner = oc(t.get('element') or t['type'], 'x', 'y')
            return f"(match {a}, {b} with | none, none => .eq | none, some _ => .lt | some _, none => .gt | some x, some y => {inner})"
        if k == "ref": return f"(cmp_{t['name']} {a} {b})"
        raise ValueError(k)
    # types that (transitively) reference a recursive SCC have no derived-Ord here;
    # the host compares those with its own metered `Compare` impls.
    tainted = set(recursive)
    for comp in sccs:  # dependencies come first
        for n in comp:
            if any(x in tainted for x in deps[n]):
                tainted.add(n)
    for comp in sccs:
        if len(comp) > 1 or comp[0] in tainted:
            continue
        n = comp[0]; d = defs[n]; N = ident(n); k = d["kind"]
        if k == "typedef":
            w(f"def cmp_{n} (a b : {N}) : Ordering := {oc(d['type'], 'a', 'b')}")
        elif k == "enum":
            w(f"def cmp_{n} (a b : {N}) : Ordering := compare a.toI32.toInt b.toI32.toInt")
        elif k == "struct":
            if not d["fields"]:
                w(f"def cmp_{n} (_ _ : {N}) : Ordering := .eq")
            else:
                body = "(.eq : Ordering)"
                for f in reversed(d["fields"]):
                    fn = ident(f["name"])
                    body = f"(thenCmp {oc(f['type'], 'a.' + fn, 'b.' + fn)} fun _ => {body})"
                w(f"def cmp_{n} (a b : {N}) : Ordering := {body}")
        elif k == "union":
            cases = disc_values(d)
            w(f"def idx_{n} : {N} → Nat")
            for i, (v, cname, arm) in enumerate(cases):
                pat = f".{ident(cname)}" if arm.get("type") is None else f".{ident(cname)} _"
                w(f"  | {pat} => {i}")
            w(f"def cmp_{n} (a b : {N}) : Ordering :=")
            w("  match a, b with")
            for i, (v, cname, arm) in enumerate(cases):
                if arm.get("type") is None:
                    w(f"  | .{ident(cname)}, .{ident(cname)} => .eq")
                else:
                    w(f"  | .{ident(cname)} x, .{ident(cname)} y => {oc(arm['type'], 'x', 'y')}")
            if len(cases) > 1:
                w(f"  | x, y => compare (idx_{n} x) (idx_{n} y)")
    w("end Ord")
    w("")
    w("end Xdr")
    OUT_C.write_text("\n".join(C) + "\n")
    nrec = sum(1 for c in sccs if len(c) > 1 or c[0] in recursive)
    print(f"wrote {len(tydefs)} types ({nrec} recursive SCCs), {len(consts)} consts")


if __name__ == "__main__":
    main()
