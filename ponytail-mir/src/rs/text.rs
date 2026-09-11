//! Text-level helpers: constants decoded, shapes combined, templates substituted, the source-level rewrites.
use std::collections::{HashMap, HashSet};
use rustc_middle::mir::*;
use rustc_middle::ty::{self, Ty, TyCtxt};
use crate::mir::Env;

use super::*;

pub(super) fn ty_str<'tcx>(tcx: TyCtxt<'tcx>, t: Ty<'tcx>) -> String {
    match t.kind() {
        ty::Adt(def, _) => tcx.item_name(def.did()).to_string(),
        ty::RawPtr(inner, m) => format!("*{} {}", if m.is_mut() { "mut" } else { "const" }, ty_str(tcx, *inner)),
        ty::Array(e, n) => format!("[{}; {}]", ty_str(tcx, *e), n),
        ty::Tuple(ts) if ts.is_empty() => "()".into(),
        _ => t.to_string(),
    }
}

/// A `Val` constant through the prelude's constructors, so the tag and body
/// read as what they are and rustc checks the encoding.
pub(super) fn val_expr(bits: u64) -> String {
    let (tag, body) = (bits & 0xff, bits >> 8);
    match tag {
        0 => "Val::FALSE".into(),
        1 => "Val::TRUE".into(),
        2 => "Val::VOID".into(),
        3 => format!("Val::error({}, {})", body & 0xff_ffff, body >> 24),
        4 => format!("Val::u32({})", bits >> 32),
        5 => format!("Val::i32({})", (bits >> 32) as u32 as i32),
        14 => match sym_str(body) {
            Some(s) => format!("Val::sym({s:?})"),
            None => format!("Val::small(14, {body})"),
        },
        t if t < 15 => format!("Val::small({t}, {body})"),
        t if (64..79).contains(&t) => format!("Val({bits}) /* object handle, tag {t} */"),
        t => format!("Val({bits}) /* bad tag {t} */"),
    }
}

pub(super) fn sym_str(body: u64) -> Option<String> {
    let mut s = String::new();
    for i in (0..9).rev() {
        let c = ((body >> (i * 6)) & 0x3f) as u8;
        if c == 0 {
            continue;
        }
        s.push(match c {
            1 => '_',
            2..=11 => (b'0' + c - 2) as char,
            12..=37 => (b'A' + c - 12) as char,
            38..=63 => (b'a' + c - 38) as char,
            _ => return None,
        });
    }
    (!s.is_empty() && body >> 54 == 0).then_some(s)
}

/// `u64` locals that are Val payloads: every use is the operand of a `Val(..)`
/// construction, or a copy into another such local. The consumer decides the
/// type, exactly as the host ABI decides it for a call argument; a phi that
/// merges `Symbol("hello")` and `Error(..)` is then written as the Vals they
/// are rather than as two integers.
pub(super) fn val_payload_locals(body: &Body<'_>, val_def: rustc_hir::def_id::DefId) -> HashSet<Local> {
    use rustc_middle::mir::visit::{PlaceContext, Visitor};
    #[derive(Default)]
    struct Uses {
        agg: HashSet<Local>,
        copy_into: HashMap<Local, Vec<Local>>,
        other: HashSet<Local>,
    }
    struct V<'a> {
        val_def: rustc_hir::def_id::DefId,
        u: &'a mut Uses,
    }
    impl<'tcx> Visitor<'tcx> for V<'_> {
        fn visit_assign(&mut self, place: &Place<'tcx>, rv: &Rvalue<'tcx>, loc: Location) {
            match rv {
                Rvalue::Aggregate(k, fs) if matches!(**k, AggregateKind::Adt(d, ..) if d == self.val_def) => {
                    if let Some(Operand::Copy(p) | Operand::Move(p)) = fs.iter().next() {
                        if let Some(l) = p.as_local() {
                            self.u.agg.insert(l);
                            return;
                        }
                    }
                }
                Rvalue::Use(Operand::Copy(p) | Operand::Move(p)) => {
                    if let (Some(src), Some(dst)) = (p.as_local(), place.as_local()) {
                        self.u.copy_into.entry(src).or_default().push(dst);
                        return;
                    }
                }
                _ => {}
            }
            self.visit_rvalue(rv, loc);
        }
        fn visit_local(&mut self, l: Local, ctx: PlaceContext, _: Location) {
            if ctx.is_use() {
                self.u.other.insert(l);
            }
        }
    }
    let mut u = Uses::default();
    V { val_def, u: &mut u }.visit_body(body);
    let mut set: HashSet<Local> = body
        .vars_and_temps_iter()
        .filter(|l| body.local_decls[*l].ty.is_integral() && !u.other.contains(l))
        .filter(|l| u.agg.contains(l) || u.copy_into.contains_key(l))
        .collect();
    // A copy into a non-payload local is an integer use after all.
    loop {
        let keep: HashSet<Local> =
            set.iter().copied().filter(|l| u.copy_into.get(l).map_or(true, |ds| ds.iter().all(|d| set.contains(d)))).collect();
        if keep.len() == set.len() {
            break set;
        }
        set = keep;
    }
}

/// How often each local is defined and read, counted the way rustc's own
/// visitor sees places: a store to a plain local is a definition, everything
/// else that is a use (including the base of `arr[1] = ..`) a read.
/// Debuginfo mentions are not uses.
pub(super) fn def_use_counts(body: &Body<'_>) -> (HashMap<Local, usize>, HashMap<Local, usize>) {
    use rustc_middle::mir::visit::{MutatingUseContext, PlaceContext, Visitor};
    #[derive(Default)]
    struct C {
        defs: HashMap<Local, usize>,
        uses: HashMap<Local, usize>,
    }
    impl<'tcx> Visitor<'tcx> for C {
        fn visit_local(&mut self, l: Local, ctx: PlaceContext, _: Location) {
            match ctx {
                PlaceContext::MutatingUse(MutatingUseContext::Store | MutatingUseContext::Call | MutatingUseContext::Yield | MutatingUseContext::AsmOutput) => {
                    *self.defs.entry(l).or_default() += 1
                }
                c if c.is_use() => *self.uses.entry(l).or_default() += 1,
                _ => {}
            }
        }
    }
    let mut c = C::default();
    c.visit_body(body);
    (c.defs, c.uses)
}

/// The locals a statement or terminator mentions, in any role.
pub(super) fn mentions<'tcx>(body: &Body<'tcx>, bb: BasicBlock, si: usize) -> Vec<Local> {
    use rustc_middle::mir::visit::{PlaceContext, Visitor};
    struct M(Vec<Local>);
    impl<'tcx> Visitor<'tcx> for M {
        fn visit_local(&mut self, l: Local, ctx: PlaceContext, _: Location) {
            if ctx.is_use() {
                self.0.push(l);
            }
        }
    }
    let mut m = M(Vec::new());
    let data = &body.basic_blocks[bb];
    let loc = Location { block: bb, statement_index: si };
    match data.statements.get(si) {
        Some(st) => m.visit_statement(st, loc),
        None => {
            if let Some(t) = &data.terminator {
                m.visit_terminator(t, loc);
            }
        }
    }
    m.0
}

/// `Val` tag names, as `soroban-env-common` numbers them (protocol 25).
pub(super) fn tag_name(n: u64) -> Option<&'static str> {
    const TAGS: [(u64, &str); 34] = [
        (0, "False"), (1, "True"), (2, "Void"), (3, "Error"), (4, "U32Val"), (5, "I32Val"), (6, "U64Small"),
        (7, "I64Small"), (8, "TimepointSmall"), (9, "DurationSmall"), (10, "U128Small"), (11, "I128Small"),
        (12, "U256Small"), (13, "I256Small"), (14, "SymbolSmall"), (15, "SmallCodeUpperBound"),
        (63, "ObjectCodeLowerBound"), (64, "U64Object"), (65, "I64Object"), (66, "TimepointObject"),
        (67, "DurationObject"), (68, "U128Object"), (69, "I128Object"), (70, "U256Object"), (71, "I256Object"),
        (72, "BytesObject"), (73, "StringObject"), (74, "SymbolObject"), (75, "VecObject"), (76, "MapObject"),
        (77, "AddressObject"), (78, "MuxedAddressObject"), (79, "ObjectCodeUpperBound"), (127, "Bad"),
    ];
    TAGS.iter().find(|(k, _)| *k == n).map(|(_, s)| *s)
}

/// Several shapes one value may have -- a local assigned in several arms, a
/// helper with several returns -- written as one: the shape itself when there
/// is one, `Union::{A, B}` when all are cases of one union, `A | B` otherwise.
/// Never just one of them: which arm ran is not known here.
pub(super) fn alternatives(shapes: Vec<String>) -> String {
    // A member that is itself a set of cases contributes each of them.
    let mut shapes: Vec<String> = shapes
        .into_iter()
        .flat_map(|s| match s.find("::{") {
            Some(i) if s.ends_with('}') => {
                let u = s[..i].to_string();
                split_top(&s[i + 3..s.len() - 1], ',').into_iter().map(|c| format!("{u}::{c}")).collect::<Vec<_>>()
            }
            _ => vec![s],
        })
        .collect();
    shapes.sort();
    shapes.dedup();
    if shapes.len() == 1 {
        return shapes.remove(0);
    }
    let union = shapes.first().and_then(|s| s.split("::").next()).filter(|u| !u.is_empty()).map(str::to_string);
    if let Some(u) = union.filter(|u| shapes.iter().all(|s| s.starts_with(&format!("{u}::")))) {
        let mut cases: Vec<&str> = shapes.iter().map(|s| s[u.len() + 2..].split('(').next().unwrap_or("")).collect();
        cases.dedup();
        return format!("{u}::{{{}}}", cases.join(", "));
    }
    shapes.join(" | ")
}

/// The local an rvalue passes on unchanged: a copy, or `Val(x)` / `Val(x.0)`.
pub(super) fn ret_source<'tcx>(env: &Env<'tcx>, rv: &Rvalue<'tcx>) -> Option<Local> {
    match rv {
        Rvalue::Use(Operand::Copy(p) | Operand::Move(p)) => p.as_local(),
        Rvalue::Aggregate(k, fs) if matches!(**k, AggregateKind::Adt(d, ..) if d == env.val_def) => match fs.iter().next() {
            Some(Operand::Copy(p) | Operand::Move(p)) => Some(p.local),
            _ => None,
        },
        _ => None,
    }
}

/// `panic!()`, `unreachable!()`, `panic_with_error!(..)`: a line after which nothing runs.
pub(super) fn is_diverging(l: &str) -> bool {
    l == "panic!();" || l == "unreachable!();" || l.starts_with("panic_with_error!(")
}

/// Source-level tidying: a trap right after a return or a panic is the guard
/// the SDK's dispatch had, gone; a trailing bare `return;` is the end.
pub(super) fn tidy(lines: &mut Vec<(usize, String)>) {
    let mut i = 1;
    while i < lines.len() {
        let prev_ends = lines[i - 1].1.starts_with("return") || is_diverging(&lines[i - 1].1);
        if (lines[i].1 == "panic!();" || lines[i].1 == "unreachable!();") && lines[i - 1].0 == lines[i].0 && prev_ends {
            lines.remove(i);
        } else {
            i += 1;
        }
    }
    if lines.last().is_some_and(|(d, l)| *d == 2 && l == "return;") {
        lines.pop();
    }
    if let Some((2, l)) = lines.last_mut() {
        if let Some(e) = l.strip_prefix("return ").and_then(|e| e.strip_suffix(';')) {
            *l = e.to_string();
        }
    }
}

/// Where the expression ending at the end of `head` begins: back over
/// balanced brackets to a separator.
pub(super) fn expr_start(head: &str) -> usize {
    let mut depth = 0i32;
    for (i, c) in head.char_indices().rev() {
        match c {
            ')' | ']' | '}' => depth += 1,
            '(' | '[' | '{' => {
                if depth == 0 {
                    return i + 1;
                }
                depth -= 1;
            }
            ',' | ' ' if depth == 0 => return i + 1,
            _ => {}
        }
    }
    0
}

/// Every `pat<args>)` in `s` rewritten by `f(args)`, innermost args first.
pub(super) fn rewrite_calls(s: &str, pat: &str, f: &dyn Fn(&str) -> String) -> String {
    let mut out = String::new();
    let mut rest = s;
    while let Some(i) = rest.find(pat) {
        // not a longer name ending in `pat`
        if i > 0 && rest.as_bytes()[i - 1].is_ascii_alphanumeric() || (i > 0 && rest.as_bytes()[i - 1] == b':' && !pat.starts_with("Val::")) {
            out.push_str(&rest[..i + pat.len()]);
            rest = &rest[i + pat.len()..];
            continue;
        }
        let open = i + pat.len() - 1;
        let mut depth = 0i32;
        let mut close = None;
        for (j, c) in rest[open..].char_indices() {
            match c {
                '(' | '[' => depth += 1,
                ')' | ']' => {
                    depth -= 1;
                    if depth == 0 {
                        close = Some(open + j);
                        break;
                    }
                }
                _ => {}
            }
        }
        let Some(close) = close else { break };
        let inner = rewrite_calls(&rest[open + 1..close], pat, f);
        out.push_str(&rest[..i]);
        out.push_str(&f(&inner));
        rest = &rest[close + 1..];
    }
    out.push_str(rest);
    out
}

/// `S { a, b }` -> `S { a: a, b: b }`, so the values can then be cloned.
pub(super) fn expand_shorthand(s: &str) -> String {
    let Some(open) = s.find('{') else { return s.to_string() };
    let mut depth = 0i32;
    let mut close = s.len();
    for (j, c) in s[open..].char_indices() {
        match c {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    close = open + j;
                    break;
                }
            }
            _ => {}
        }
    }
    let items: Vec<String> = split_top(&s[open + 1..close], ',')
        .iter()
        .map(|it| {
            let it = it.trim();
            if !it.is_empty() && it.chars().all(|c| c.is_alphanumeric() || c == '_') {
                format!("{it}: {it}")
            } else if let Some((k, v)) = it.split_once(": ") {
                format!("{k}: {}", expand_shorthand(v))
            } else {
                expand_shorthand(it)
            }
        })
        .collect();
    format!("{}{{ {} }}{}", &s[..open], items.join(", "), expand_shorthand(s.get(close + 1..).unwrap_or("")))
}

/// `fn name(a: T) -> R` from the spec -> `pub fn name(env: Env, a: T) -> R {`.
pub(super) fn sdk_header(sig: &str) -> R<String> {
    let rest = sig.strip_prefix("fn ").unwrap_or(sig);
    let (name_params, ret) = rest.split_once(" -> ").map(|(a, b)| (a, format!(" -> {b}"))).unwrap_or((rest, String::new()));
    let (name, params) = name_params.split_once('(').ok_or("spec signature")?;
    let params = params.trim_end_matches(')');
    Ok(format!("pub fn {name}(env: Env{}{params}){ret} {{", if params.is_empty() { "" } else { ", " }))
}

/// A spec type as the `#[contracttype]` item that declared it.
pub(super) fn type_item(l: &str) -> String {
    let (kw, rest) = l.split_once(' ').unwrap_or((l, ""));
    let name = rest.split(|c| c == ' ' || c == '{').next().unwrap_or("");
    let inner = l.find('{').map(|i| &l[i + 1..l.rfind('}').unwrap_or(l.len())]).unwrap_or("");
    let items: Vec<String> = split_top(inner, ',').iter().map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect();
    let body = |items: &[String]| items.iter().map(|i| format!("    {i},\n")).collect::<String>();
    match kw {
        "struct" if items.first().is_some_and(|f| f.starts_with("0:")) => {
            let tys: Vec<String> = items.iter().filter_map(|f| f.split_once(": ").map(|(_, t)| format!("pub {t}"))).collect();
            format!("#[contracttype]\n#[derive(Clone)]\npub struct {name}({});\n\n", tys.join(", "))
        }
        "struct" => format!("#[contracttype]\n#[derive(Clone)]\npub struct {name} {{\n{}}}\n\n", body(&items.iter().map(|f| format!("pub {f}")).collect::<Vec<_>>())),
        "union" => format!("#[contracttype]\n#[derive(Clone)]\npub enum {name} {{\n{}}}\n\n", body(&items)),
        "enum" => format!("#[contracttype]\n#[derive(Clone, Copy, PartialEq, Eq)]\npub enum {name} {{\n{}}}\n\n", body(&items)),
        "error" => format!("#[contracterror]\n#[derive(Clone, Copy, PartialEq, Eq)]\npub enum {name} {{\n{}}}\n\n", body(&items)),
        "event" => format!("// event {name}: a #[contractevent] type, not reconstructed.\n\n"),
        _ => String::new(),
    }
}

pub(super) const CONTRACT_HEAD: &str = "#![no_std]
//! Reconstructed by ponytail-mir --contract: the contract as soroban-sdk source.
//! An export that could not be said at this level is a `todo!()` naming why.
#![allow(unused_imports, unused_mut, unused_variables, unreachable_code, unused_parens, non_snake_case, clippy::all)]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, panic_with_error, symbol_short, vec, Address, Bytes, BytesN, Duration, Env, I256,
    Map, MuxedAddress, String, Symbol, Timepoint, U256, Val, Vec,
};

";

/// `a0@8` left in a template -- a word the caller did not write here -- is
/// unknown: `_`.
pub(super) fn blank_words(t: &str) -> String {
    let b = t.as_bytes();
    let mut out = String::new();
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'@' && b.get(i + 1).is_some_and(u8::is_ascii_digit) && out.ends_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
            while out.ends_with(|c: char| c.is_ascii_alphanumeric() || c == '_') {
                out.pop();
            }
            out.push('_');
            i += 1;
            while i < b.len() && b[i].is_ascii_digit() {
                i += 1;
            }
            continue;
        }
        out.push(b[i] as char);
        i += 1;
    }
    out
}

/// A helper's returned shape with its parameter names replaced, whole word,
/// by the shapes of the arguments at a call.
pub(super) fn substitute(template: &str, params: &[String], args: &[String]) -> String {
    let mut out = String::new();
    let mut word = String::new();
    let flush = |word: &mut String, out: &mut String| {
        if let Some(i) = params.iter().position(|p| p == word) {
            out.push_str(args.get(i).map(String::as_str).unwrap_or(word));
        } else {
            out.push_str(word);
        }
        word.clear();
    };
    for c in template.chars() {
        if c.is_ascii_alphanumeric() || c == '_' {
            word.push(c);
        } else {
            flush(&mut word, &mut out);
            out.push(c);
        }
    }
    flush(&mut word, &mut out);
    out
}

/// `(e)` -> `e` when the parentheses enclose the whole expression.
pub(super) fn strip_parens(s: String) -> String {
    if !(s.starts_with('(') && s.ends_with(')')) {
        return s;
    }
    let mut depth = 0i32;
    for (i, c) in s.char_indices() {
        depth += match c {
            '(' => 1,
            ')' => -1,
            _ => 0,
        };
        if depth == 0 && i + 1 < s.len() {
            return s; // the first paren closes before the end
        }
    }
    s[1..s.len() - 1].to_string()
}

/// An rvalue that can be evaluated at its use instead of where it is written:
/// no memory read, no call. Arithmetic and casts only.
pub(super) fn pure(rv: &Rvalue<'_>) -> bool {
    fn plain(o: &Operand<'_>) -> bool {
        match o {
            Operand::Copy(p) | Operand::Move(p) => !p.projection.iter().any(|e| matches!(e, PlaceElem::Deref)),
            Operand::Constant(_) => true,
            _ => false,
        }
    }
    match rv {
        Rvalue::Use(o) | Rvalue::UnaryOp(_, o) | Rvalue::Cast(_, o, _) => plain(o),
        Rvalue::BinaryOp(_, ab) => plain(&ab.0) && plain(&ab.1),
        Rvalue::Aggregate(_, fs) => fs.iter().all(plain),
        Rvalue::Discriminant(p) | Rvalue::RawPtr(_, p) => !p.projection.iter().any(|e| matches!(e, PlaceElem::Deref)),
        _ => false,
    }
}
