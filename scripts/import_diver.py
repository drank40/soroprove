#!/usr/bin/env python3
"""Import a contract model emitted by stellar-diver (`slice X.ll --lean model`) into the
playground, untouched, and derive its block vocabulary from the model itself.

    python3 scripts/import_diver.py CONTRACT.ll Name key [--slice PATH] [--storage X.storage.json]

writes StellarLean/Diver/<Name>.lean (byte for byte what `slice` printed, with the
provenance in StellarLean/Diver/<Name>.json), builds it, and adds or replaces the
contract `key` in playground/vocab.js.
"""

import argparse
import hashlib
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIVER = pathlib.Path.home() / "doc/work/stellar/stellar-diver"


def vocabulary(src, name, key, storage):
    """Blocks for everything the model names: storage keys, maps, token ledgers, entry
    points, arguments, and the values each entry point derives."""
    vars_ = re.findall(r'^@\[simp\] def (\w+) : Key := \.var "(\w+)"', src, re.M)
    maps = re.findall(r'^@\[simp\] def (\w+) \(k1 : Addr\) : Key := \.entry "(\w+)" k1', src, re.M)
    found = re.search(r"^def entries : List \(Step → Prop\) := \[([^\]]*)\]", src, re.M)
    assert found, "no `entries` in the model"
    entries = found.group(1)
    entries = [e.strip() for e in entries.split(",") if e.strip()]
    # A storage variable holding a token address: the ledger of that token, `bal (s X) s a`.
    tokens = [v for v, _ in vars_ if re.search(rf"(?:bal|xfer) \(st\.pre {v}\)", src)]
    ledger = {f"Balance{t[5:]}" if t.startswith("Token") else f"{t}Balance": t for t in tokens}
    # Arguments, by kind, and derived values (`@[simp] def entry.v (st : Step) : Int := …`).
    args, addr_args, derived = {}, {}, []
    # `namespace <entry> … end <entry>` blocks (inside `namespace Contract`) hold the
    # entry point's arguments and derived values, unqualified.
    defs, ns, lines = [], None, src.split("\n")
    for i, line in enumerate(lines):
        if m := re.match(r"^namespace (\w+)$", line):
            ns = m[1] if m[1] != "Contract" else None
        elif re.match(r"^end \w+$", line):
            ns = None
        elif ns and (m := re.match(r"^@\[simp\] def (\w+) \(st : Step\) : (Int|Addr) :=\s*(.*)$", line)):
            body = m[3] or (lines[i + 1].strip() if i + 1 < len(lines) else "")
            defs.append((ns, m[1], m[2], body))
    for entry, nm, ty, body in defs:
        m = re.match(r'st\.call\.(arg|argA) "([\w.]+)"$', body.strip())
        if m:
            (args if m[1] == "arg" else addr_args)[m[2]] = ty
        elif ty == "Int" and entry in entries:
            derived.append(f"{entry}.{nm}")
    words = lambda n: re.sub(r"(?<=[a-z])(?=[A-Z])", " ", n).lower()
    var_rows = [[v, "Addr" if v in tokens else "Int", words(v)] for v, _ in vars_]
    map_rows = [[m, f"{words(m)} of"] for m, _ in maps] + [[b, f"the {words(t)} balance of"] for b, t in ledger.items()]
    C = {
        "title": f"{name} (stellar-diver model, untouched)",
        "kind": "diver",
        "source": f"StellarLean/Diver/{name}.lean",
        "namespace": "Contract",
        "prelude": [f"import StellarLean.Diver.{name}", "", f"namespace Diver.{name}.Playground", "", "open Contract"],
        "epilogue": [f"end Diver.{name}.Playground"],
        "header": [f"import StellarLean.Diver.{name}", "", "open Contract"],
        "footer": [],
        "targets": [["contract", "each call"], ["history", "every history"]],
        "tactics": ["vibe", "sorry"],
        "vars": var_rows,
        "maps": map_rows,
        "who": ["caller"],
        "addrs": [["pool", "the contract"]] + [[a, f"the `{a}` argument"] for a in addr_args],
        "amounts": [[a, a] for a in args],
        "entries": entries,
        "conds": [],
        "addrPreds": [],
        "invariants": [],
        "features": ["calls", "compare"],
        "diver": {"ledgers": ledger, "maps": [m for m, _ in maps], "addrArgs": list(addr_args),
                  "derived": derived},
        "examples": [],
    }
    if storage:
        C["storage"] = storage
    return C


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ll"); ap.add_argument("name"); ap.add_argument("key")
    ap.add_argument("--slice", default=str(DIVER / "target/release/slice"))
    ap.add_argument("--storage")
    a = ap.parse_args()
    out = subprocess.run([a.slice, a.ll, "--lean", "model"], capture_output=True, text=True, check=True).stdout
    dst = ROOT / "StellarLean/Diver" / f"{a.name}.lean"
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(out)
    rev = subprocess.run(["git", "-C", str(DIVER), "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    (dst.with_suffix(".json")).write_text(json.dumps({
        "source": str(pathlib.Path(a.ll).resolve()), "slice": rev,
        "sha256": hashlib.sha256(out.encode()).hexdigest()}, indent=2) + "\n")
    subprocess.run(["lake", "build", f"StellarLean.Diver.{a.name}"], cwd=ROOT, check=True)
    storage = None
    if a.storage:
        storage = {}
        for sl in json.load(open(a.storage))["slots"]:
            ty = sl["value_type"] if not sl["key_params"] else f'{", ".join(sl["key_params"])} → {sl["value_type"]}'
            storage[sl["key"]] = [sl["durability"], ty]
    C = vocabulary(out, a.name, a.key, storage)
    if storage:
        for b in C["diver"]["ledgers"]:
            storage[b] = [f"{C['diver']['ledgers'][b]} ledger (SEP-41)", "Address → i128"]
    vp = ROOT / "playground/vocab.js"
    text = vp.read_text()
    V = json.loads(text[text.index("{"):text.rindex("}") + 1])
    V["contracts"][a.key] = C
    # Keep the file's layout: rewrite only this contract's entry.
    blob = json.dumps(C, ensure_ascii=False)
    pat = re.compile(rf'\n    "{re.escape(a.key)}": \{{.*?\n    \}}(?=,\n    "|\n  \}}\n\}};)', re.S)
    entry = f'\n    "{a.key}": {blob}'
    if pat.search(text):
        text = pat.sub(lambda _: entry, text)
    else:
        i = text.rindex("\n  }\n};")
        text = text[:i] + "," + entry + text[i:]
    vp.write_text(text)
    print(f"{dst} ({len(out)} bytes, slice {rev}); vocab.js: {a.key}")


if __name__ == "__main__":
    main()
