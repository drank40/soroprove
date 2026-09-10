//! optimized MIR -> Rust, structured.
//!
//! The control flow comes from rustc's own analyses over the body: reverse
//! postorder, dominators, predecessors. A block that two edges reach is
//! placed after its immediate dominator inside a labelled block, so a jump
//! to it is `break 'b`; a loop header is `'l: loop { .. }` and its back edges
//! `continue 'l`; every other block has one predecessor and is written inline
//! where that predecessor branches. A jump that is the last thing before its
//! target falls through instead, and a label nothing jumps to is not written.
//! This is the Ramsey algorithm for reducible graphs, which is what inlined
//! wasm gives; anything else falls back to a state machine and says so.
//!
//! Every local is declared once and assigned where MIR assigns it; rustc's
//! definite-initialisation check on the output then confirms what MIR's
//! borrow check already established.
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::fmt::Write as _;

use rustc_middle::mir::interpret::{GlobalAlloc, Scalar};
use rustc_middle::mir::*;
use rustc_middle::ty::{self, Ty, TyCtxt};
use rustc_span::Spanned;

use crate::mir::Env;

type R<T> = Result<T, String>;

/// One storage access: durability, key shape, operation (with the value for
/// a put), function.
type Access = (String, String, String, String);

/// What one function's emission tells the others: what a helper returns, in
/// terms of its parameters; which parameters a helper uses as storage keys;
/// who is called at all. Filled by one pass, read by the next.
/// A switch arm a value was made under: the word read through a pointer
/// parameter (`a0@0`), the arm's values, and whether this is the arm for
/// every other value.
type Cond = (String, Vec<u64>, bool);

#[derive(Default)]
struct Inter {
    /// fn -> (shape of a returned value, the fn's parameter names to
    /// substitute, the arms it was returned under).
    ret_shapes: HashMap<String, Vec<(String, Vec<String>, Vec<Cond>)>>,
    /// fn -> the spec types it unpacks from the host (a struct's fields, a
    /// union's cases): what a `try_from_val` derive does.
    unpacks: HashMap<String, Vec<String>>,
    /// fn -> (identifier, doc) for helpers recognised as `#[contracttype]`
    /// derives. Filled once the summaries are final.
    renames: HashMap<String, (String, String)>,
    /// fn -> the error it hands the host: a `panic_with_error!` wrapper.
    fails: HashMap<String, String>,
    /// fns with no return: every path traps.
    diverges: HashSet<String>,
    /// fn -> (parameter index used as key, operation, durability).
    param_accesses: HashMap<String, Vec<(usize, String, String)>>,
    called: HashSet<String>,
    schema: Vec<Access>,
    /// fn -> (pointer parameter it writes through, itself or by a call; how
    /// far past the pointer, when every write is at a constant offset).
    /// Every emitted fn has an entry.
    param_writes: HashMap<String, Vec<(usize, Option<u64>)>>,
    /// fn -> (text position param, length param, "Symbol" | "String"): a
    /// helper that is the SDK's `Symbol::new` / `String::from_str`. Read off
    /// the final summaries.
    text_helpers: HashMap<String, (usize, usize, &'static str)>,
}

/// `Symbol(@Val::u32(a0 as u32), Val::u32(a1 as u32))`, every return of the
/// helper: it builds its result from the text at two of its parameters.
fn text_params(template: &str, params: &[String]) -> Option<(usize, usize, &'static str)> {
    let kind = if template.starts_with("Symbol(@") { "Symbol" } else if template.starts_with("String(@") { "String" } else { return None };
    let mut idx = template.split("Val::u32(").skip(1).map(|r| {
        let w: String = r.chars().take_while(|c| c.is_ascii_alphanumeric() || *c == '_').collect();
        params.iter().position(|p| *p == w)
    });
    let (Some(Some(i)), Some(Some(j)), None) = (idx.next(), idx.next(), idx.next()) else { return None };
    (i != j).then_some((i, j, kind))
}

/// Every function's summaries, iterated to a fixpoint, then what is read off
/// them: the text helpers, the derive renames, the functions that never return.
fn summaries<'tcx>(tcx: TyCtxt<'tcx>, env: &Env<'tcx>, bodies: &[&Body<'tcx>], spec: &Spec) -> R<Inter> {
    // Helpers' return shapes and key parameters are known to their callers
    // only once every body has been seen, and a helper's own summary
    // sharpens once its callees' are known: each pass reads the previous
    // pass's summaries and writes fresh ones, until they stop changing; the
    // last pass emits with the complete set.
    let mut prev = Inter::default();
    for _ in 0..8 {
        // ponytail: a summary chain deeper than 8 calls stays partly unresolved (shown as `_`).
        let cur = RefCell::new(Inter::default());
        for body in bodies {
            Fn_::new(tcx, env, body, spec, &prev, &cur, false).emit()?;
        }
        let cur = cur.into_inner();
        let stable = cur.ret_shapes == prev.ret_shapes && cur.param_accesses == prev.param_accesses && cur.called == prev.called && cur.unpacks == prev.unpacks && cur.param_writes == prev.param_writes && cur.fails == prev.fails;
        prev = cur;
        if stable {
            break;
        }
    }
    prev.text_helpers = prev
        .ret_shapes
        .iter()
        .filter_map(|(f, ts)| {
            let mut ps = ts.iter().map(|(t, params, _)| text_params(t, params));
            let first = ps.next()??;
            ps.all(|p| p == Some(first)).then(|| (f.clone(), first))
        })
        .collect();
    // Helpers that are `#[contracttype]` derives: every return one case of
    // one union or one struct's map is its `into_val`; unpacking one type's
    // fields or cases is its `try_from_val`.
    let is_helper = |f: &str| {
        f.strip_prefix('f').is_some_and(|d| !d.is_empty() && d.chars().all(|c| c.is_ascii_digit()))
            && !prev.schema.iter().any(|(_, _, _, who)| who == f || who.starts_with(&format!("{f} via ")))
    };
    let owner = |s: &str| -> Option<String> {
        let s = s.rsplit_once(" /* ").map(|(_, c)| c.trim_end_matches(" */")).unwrap_or(s);
        if let Some((u, _)) = s.split_once("::") {
            if spec.union_cases.iter().any(|(n, _)| n == u) {
                return Some(u.to_string());
            }
        }
        s.split_once(" {").map(|(st, _)| st).filter(|st| spec.struct_fields.contains_key(*st)).map(str::to_string)
    };
    let mut renames = HashMap::new();
    for (f, shapes) in &prev.ret_shapes {
        let owners: Vec<Option<String>> = shapes.iter().map(|(s, ..)| owner(s)).collect();
        if let Some(Some(t)) = owners.first().filter(|_| is_helper(f)) {
            if owners.iter().all(|o| o.as_deref() == Some(t.as_str())) {
                renames.insert(f.clone(), (format!("{t}_into_val"), format!("/// The `#[contracttype]` derive `<{t} as IntoVal<Env, Val>>::into_val`.\n")));
            }
        }
    }
    for (f, types) in &prev.unpacks {
        if let Some(t) = types.first().filter(|_| is_helper(f) && !renames.contains_key(f)) {
            if types.iter().all(|x| x == t) {
                renames.insert(f.clone(), (format!("{t}_try_from_val"), format!("/// The `#[contracttype]` derive `<{t} as TryFromVal<Env, Val>>::try_from_val`.\n")));
            }
        }
    }
    prev.renames = renames;
    prev.diverges = bodies
        .iter()
        .filter(|b| !b.basic_blocks.iter().any(|bb| matches!(bb.terminator().kind, TerminatorKind::Return)))
        .map(|b| tcx.item_name(b.source.def_id()).to_string())
        .collect();
    Ok(prev)
}

pub fn emit<'tcx>(tcx: TyCtxt<'tcx>, env: &Env<'tcx>, header: &str, bodies: &[&Body<'tcx>], spec: &Spec) -> R<String> {
    let prev = summaries(tcx, env, bodies, spec)?;
    let inter = RefCell::new(Inter::default());
    let mut fns = String::new();
    for body in bodies {
        fns.push('\n');
        fns.push_str(&Fn_::new(tcx, env, body, spec, &prev, &inter, true).emit()?);
    }
    // The storage schema: every key the contract hands the host, by
    // durability, with the operations and functions that use it. The uses
    // give the roles and the bare keys; the spec gave the names.
    let mut out = String::from(header);
    let schema = std::mem::take(&mut inter.borrow_mut().schema);
    if !schema.is_empty() {
        let mut groups: Vec<((String, String), Vec<String>)> = Vec::new();
        for (dur, key, op, f) in schema {
            let use_ = format!("{op}: {f}");
            match groups.iter_mut().find(|(k, _)| *k == (dur.clone(), key.clone())) {
                Some((_, uses)) => {
                    if !uses.contains(&use_) {
                        uses.push(use_);
                    }
                }
                None => groups.push(((dur, key), vec![use_])),
            }
        }
        groups.sort();
        out.push_str("\n// storage, from every put/get/has/del/extend_ttl call: durability, key, uses.\n");
        for ((dur, key), uses) in groups {
            let _ = writeln!(out, "//   {dur:<11} {key}   [{}]", uses.join(", "));
        }
    }
    out.push_str(&fns);
    Ok(out)
}

/// What `contractspecv0` declares, recovered from the lines ponytail-wasm
/// rendered: enough to name error codes, enum discriminants, union cases and
/// export signatures. The shapes are ScVal shapes, not memory layout.
#[derive(Default)]
pub struct Spec {
    /// `fn name(..) -> ..` lines, by function name.
    sigs: HashMap<String, String>,
    /// Function -> the declared type of each parameter.
    params: HashMap<String, Vec<String>>,
    /// Integer enum -> (case, value).
    enums: HashMap<String, Vec<(String, u32)>>,
    /// (error enum, case, value).
    errors: Vec<(String, String, u32)>,
    /// (union, case name).
    union_cases: Vec<(String, String)>,
    /// Struct -> field names, in declaration order.
    struct_fields: HashMap<String, Vec<String>>,
    /// Map key names by their rodata position (`soroban.keys`).
    keys: HashMap<u64, Vec<String>>,
    /// Symbol and string texts by their rodata position (`soroban.strings`).
    strings: HashMap<u64, String>,
    /// The read-only data segments (`soroban.rodata`), base and bytes.
    rodata: Vec<(u64, Vec<u8>)>,
    /// Function -> the SDK function its fingerprint says it is (`sdk.name`).
    sdk: HashMap<String, String>,
}

/// Split on `sep` outside any brackets.
fn split_top(s: &str, sep: char) -> Vec<String> {
    let (mut depth, mut cur, mut out) = (0i32, String::new(), Vec::new());
    for c in s.chars() {
        match c {
            '(' | '<' | '{' => depth += 1,
            ')' | '>' | '}' => depth -= 1,
            _ => {}
        }
        if c == sep && depth == 0 {
            out.push(cur.trim().to_string());
            cur.clear();
        } else {
            cur.push(c);
        }
    }
    if !cur.trim().is_empty() {
        out.push(cur.trim().to_string());
    }
    out
}

impl Spec {
    pub fn parse(lines: Vec<String>, key_lines: Vec<String>, string_lines: Vec<String>, rodata_lines: Vec<String>, sdk_lines: Vec<String>) -> Spec {
        let mut s = Spec::default();
        s.sdk = sdk_lines.iter().filter_map(|l| l.split_once(' ')).map(|(f, n)| (f.to_string(), n.to_string())).collect();
        for l in rodata_lines {
            if let Some((base, hex)) = l.split_once(' ') {
                let bytes: Vec<u8> = (0..hex.len() / 2).filter_map(|i| u8::from_str_radix(&hex[2 * i..2 * i + 2], 16).ok()).collect();
                if let Ok(base) = base.parse() {
                    s.rodata.push((base, bytes));
                }
            }
        }
        for l in key_lines {
            let mut it = l.split(' ');
            if let Some(pos) = it.next().and_then(|p| p.parse().ok()) {
                s.keys.insert(pos, it.map(str::to_string).collect());
            }
        }
        for l in string_lines {
            if let Some((pos, text)) = l.split_once(' ') {
                if let Ok(pos) = pos.parse() {
                    s.strings.insert(pos, text.to_string());
                }
            }
        }
        let body = |l: &str| -> (String, Vec<String>) {
            let name = l.split_whitespace().nth(1).unwrap_or("").trim_end_matches('{').to_string();
            let inner = l.find('{').map(|i| &l[i + 1..l.rfind('}').unwrap_or(l.len())]).unwrap_or("");
            (name, split_top(inner, ','))
        };
        let cases = |items: &[String]| -> Vec<(String, u32)> {
            items.iter().filter_map(|c| {
                let (n, v) = c.split_once('=')?;
                Some((n.trim().to_string(), v.trim().parse().ok()?))
            }).collect()
        };
        for l in lines {
            if let Some(rest) = l.strip_prefix("fn ") {
                let name = rest.split('(').next().unwrap_or("").to_string();
                // The parameter list: up to the paren matching the first one,
                // not the last paren of the line (the return type has its own).
                let inner = rest.find('(').map(|i| {
                    let (mut depth, mut end) = (0i32, rest.len());
                    for (j, c) in rest[i..].char_indices() {
                        depth += match c {
                            '(' => 1,
                            ')' => -1,
                            _ => 0,
                        };
                        if depth == 0 {
                            end = i + j;
                            break;
                        }
                    }
                    &rest[i + 1..end]
                }).unwrap_or("");
                let types = split_top(inner, ',').iter().map(|p| p.split_once(": ").map(|(_, t)| t.to_string()).unwrap_or_default()).collect();
                s.params.insert(name.clone(), types);
                s.sigs.insert(name, l.clone());
            } else if l.starts_with("enum ") {
                let (name, items) = body(&l);
                s.enums.insert(name, cases(&items));
            } else if l.starts_with("error ") {
                let (name, items) = body(&l);
                s.errors.extend(cases(&items).into_iter().map(|(c, v)| (name.clone(), c, v)));
            } else if l.starts_with("union ") {
                let (name, items) = body(&l);
                s.union_cases.extend(items.iter().map(|c| (name.clone(), c.split('(').next().unwrap_or(c).to_string())));
            } else if l.starts_with("struct ") {
                let (name, items) = body(&l);
                s.struct_fields.insert(name, items.iter().map(|f| f.split(':').next().unwrap_or(f).trim().to_string()).collect());
            }
        }
        s
    }

    /// The struct whose field set is exactly these keys, if there is one.
    /// The union whose cases are exactly these names, if there is one.
    fn union_for_cases(&self, names: &[String]) -> Option<&str> {
        let mut want: Vec<&str> = names.iter().map(String::as_str).collect();
        want.sort();
        let mut unions: Vec<&str> = self.union_cases.iter().map(|(u, _)| u.as_str()).collect();
        unions.dedup();
        let mut it = unions.into_iter().filter(|u| {
            let mut have: Vec<&str> = self.union_cases.iter().filter(|(n, _)| n == u).map(|(_, c)| c.as_str()).collect();
            have.sort();
            have == want
        });
        match (it.next(), it.next()) {
            (Some(u), None) => Some(u),
            _ => None,
        }
    }

    fn struct_for_keys(&self, keys: &[String]) -> Option<&str> {
        let mut want: Vec<&str> = keys.iter().map(String::as_str).collect();
        want.sort();
        let mut it = self.struct_fields.iter().filter(|(_, fs)| {
            let mut have: Vec<&str> = fs.iter().map(String::as_str).collect();
            have.sort();
            have == want
        });
        match (it.next(), it.next()) {
            (Some((n, _)), None) => Some(n.as_str()),
            _ => None,
        }
    }

    /// The text at a read-only data position, when the data is there.
    fn text_at(&self, pos: u64, len: u64) -> Option<String> {
        self.rodata.iter().find_map(|(base, d)| {
            let off = pos.checked_sub(*base)? as usize;
            let bytes = d.get(off..off.checked_add(len as usize)?)?;
            Some(String::from_utf8_lossy(bytes).into_owned())
        })
    }

    /// `Error::AnError` for a contract error code, when exactly one case has it.
    fn error_name(&self, code: u64) -> Option<String> {
        let mut it = self.errors.iter().filter(|(_, _, v)| *v as u64 == code);
        match (it.next(), it.next()) {
            (Some((e, c, _)), None) => Some(format!("{e}::{c}")),
            _ => None,
        }
    }

    /// `DataKey::Pair` for a symbol that is exactly one union's case name.
    fn union_case(&self, sym: &str) -> Option<String> {
        let mut it = self.union_cases.iter().filter(|(_, c)| c == sym);
        match (it.next(), it.next()) {
            (Some((u, c)), None) => Some(format!("{u}::{c}")),
            _ => None,
        }
    }

    /// The enum a function's parameter is declared as, if it is an integer enum.
    fn param_enum(&self, f: &str, i: usize) -> Option<&str> {
        let t = self.params.get(f)?.get(i)?;
        self.enums.contains_key(t).then_some(t.as_str())
    }

    fn enum_case(&self, e: &str, v: u64) -> Option<&str> {
        self.enums.get(e)?.iter().find(|(_, x)| *x as u64 == v).map(|(c, _)| c.as_str())
    }
}

fn ty_str<'tcx>(tcx: TyCtxt<'tcx>, t: Ty<'tcx>) -> String {
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
fn val_expr(bits: u64) -> String {
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

fn sym_str(body: u64) -> Option<String> {
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
fn val_payload_locals(body: &Body<'_>, val_def: rustc_hir::def_id::DefId) -> HashSet<Local> {
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
fn def_use_counts(body: &Body<'_>) -> (HashMap<Local, usize>, HashMap<Local, usize>) {
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
fn mentions<'tcx>(body: &Body<'tcx>, bb: BasicBlock, si: usize) -> Vec<Local> {
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
fn tag_name(n: u64) -> Option<&'static str> {
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
fn alternatives(shapes: Vec<String>) -> String {
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
fn ret_source<'tcx>(env: &Env<'tcx>, rv: &Rvalue<'tcx>) -> Option<Local> {
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
fn is_diverging(l: &str) -> bool {
    l == "panic!();" || l == "unreachable!();" || l.starts_with("panic_with_error!(")
}

/// Source-level tidying: a trap right after a return or a panic is the guard
/// the SDK's dispatch had, gone; a trailing bare `return;` is the end.
fn tidy(lines: &mut Vec<(usize, String)>) {
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
fn expr_start(head: &str) -> usize {
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
fn rewrite_calls(s: &str, pat: &str, f: &dyn Fn(&str) -> String) -> String {
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
fn expand_shorthand(s: &str) -> String {
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
fn sdk_header(sig: &str) -> R<String> {
    let rest = sig.strip_prefix("fn ").unwrap_or(sig);
    let (name_params, ret) = rest.split_once(" -> ").map(|(a, b)| (a, format!(" -> {b}"))).unwrap_or((rest, String::new()));
    let (name, params) = name_params.split_once('(').ok_or("spec signature")?;
    let params = params.trim_end_matches(')');
    Ok(format!("pub fn {name}(env: Env{}{params}){ret} {{", if params.is_empty() { "" } else { ", " }))
}

/// A spec type as the `#[contracttype]` item that declared it.
fn type_item(l: &str) -> String {
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

const CONTRACT_HEAD: &str = "#![no_std]
//! Reconstructed by ponytail-mir --contract: the contract as soroban-sdk source.
//! An export that could not be said at this level is a `todo!()` naming why.
#![allow(unused_imports, unused_mut, unused_variables, unreachable_code, unused_parens, non_snake_case, clippy::all)]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, panic_with_error, symbol_short, vec, Address, Bytes, BytesN, Duration, Env, I256,
    Map, MuxedAddress, String, Symbol, Timepoint, U256, Val, Vec,
};

";

/// The contract as soroban-sdk source: its types from the spec, its exports
/// from the shapes. An export the source level cannot say is a `todo!()`
/// that names the first thing it could not.
pub fn emit_contract<'tcx>(tcx: TyCtxt<'tcx>, env: &Env<'tcx>, bodies: &[&Body<'tcx>], spec: &Spec, lines: &[String]) -> R<String> {
    let prev = summaries(tcx, env, bodies, spec)?;
    let inter = RefCell::new(Inter::default());
    let mut out = String::from(CONTRACT_HEAD);
    for l in lines {
        out.push_str(&type_item(l));
    }
    out.push_str("#[contract]\npub struct Contract;\n\n#[contractimpl]\nimpl Contract {\n");
    for body in bodies {
        let def_id = body.source.def_id();
        let name = tcx.item_name(def_id).to_string();
        if !tcx.visibility(def_id).is_public() || name == "_" {
            continue;
        }
        let Some(sig) = spec.sigs.get(&name).cloned() else {
            out.push_str(&format!("    // {name}: exported, not in the spec.\n\n"));
            continue;
        };
        match Fn_::new(tcx, env, body, spec, &prev, &inter, true).emit_sdk() {
            Ok(s) => out.push_str(&s),
            Err(why) => out.push_str(&format!("    {}\n        // not reconstructed: {why}\n        todo!()\n    }}\n", sdk_header(&sig)?)),
        }
        out.push('\n');
    }
    let trimmed = out.trim_end().to_string();
    Ok(format!("{trimmed}\n}}\n"))
}

/// `a0@8` left in a template -- a word the caller did not write here -- is
/// unknown: `_`.
fn blank_words(t: &str) -> String {
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
fn substitute(template: &str, params: &[String], args: &[String]) -> String {
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
fn strip_parens(s: String) -> String {
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
fn pure(rv: &Rvalue<'_>) -> bool {
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

struct Fn_<'a, 'tcx> {
    tcx: TyCtxt<'tcx>,
    env: &'a Env<'tcx>,
    body: &'a Body<'tcx>,
    spec: &'a Spec,
    fname: String,
    names: HashMap<Local, String>,
    payloads: HashSet<Local>,
    rpo: HashMap<BasicBlock, usize>,
    defs: HashMap<Local, usize>,
    uses: HashMap<Local, usize>,
    /// The one rvalue assigned to a local that is assigned exactly once.
    single_def: HashMap<Local, Rvalue<'tcx>>,
    /// Frame arrays whose address goes to the host as a position it reads
    /// Vals from (`vec_new_from_linear_memory`, the values of `map_new_..`),
    /// with their length: their slots hold Vals.
    val_arrays: HashMap<Local, u64>,
    /// Val arrays written whole, once, right before the one call that takes
    /// them: written as an array literal at that call instead.
    literal: HashSet<Local>,
    /// The address plumbing of literal arrays (`&raw mut`, casts, the packed
    /// position): every use of it is the consuming call, so it is not written.
    addr_locals: HashSet<Local>,
    /// The literal's elements as they are collected: expression, and the
    /// local it came from when it was a plain copy.
    array_lits: HashMap<Local, Vec<Option<(String, Option<Local>)>>>,
    /// Call results: callee and arguments, by destination local.
    call_def: HashMap<Local, (String, Vec<Operand<'tcx>>)>,
    /// What a vec or map built from linear memory is, once its call has been
    /// written: `DataKey::Pair(pair_key)`, `PairKey { a: .., b: .. }`. Every
    /// shape a local takes, each with the switch arms it was made under.
    shapes: HashMap<Local, Vec<(Vec<Cond>, String)>>,
    /// The block being emitted, for those arms.
    cur_bb: BasicBlock,
    /// Source level: SDK calls and spec types, no Vals.
    sdk: bool,
    /// Locals bound by name in SDK output; results inlined at their one use.
    declared: HashSet<Local>,
    inlined: HashMap<Local, String>,
    /// Locals whose value flows to the return unchanged; whether `_0` is
    /// always assigned right before a `return`.
    ret_locals: HashSet<Local>,
    ret_inline: bool,
    ret_expr: Option<String>,
    /// The previous pass's summaries, read; this pass's, written.
    prev: &'a Inter,
    inter: &'a RefCell<Inter>,
    /// The last pass, whose summaries are complete.
    final_pass: bool,
    /// Single-use temporaries written into their one use instead of on a
    /// line of their own: the expression, and the rvalue it came from so a
    /// consumer can still see its shape.
    folded: HashMap<Local, (String, Rvalue<'tcx>)>,
    /// Output lines with their nesting depth; indentation is applied at the end.
    out: Vec<(usize, String)>,
    depth: usize,
    /// Labels whose region is being emitted. A jump to a label not here means
    /// the CFG is not reducible; the function then falls back.
    open: Vec<BasicBlock>,
    /// Labels some `break`/`continue` names; the others are not written.
    used: HashSet<BasicBlock>,
}

impl<'a, 'tcx> Fn_<'a, 'tcx> {
    fn new(tcx: TyCtxt<'tcx>, env: &'a Env<'tcx>, body: &'a Body<'tcx>, spec: &'a Spec, prev: &'a Inter, inter: &'a RefCell<Inter>, final_pass: bool) -> Self {
        let fname = tcx.item_name(body.source.def_id()).to_string();
        let mut names = HashMap::new();
        // A local must not shadow a function or static it might share a name
        // with: LLVM named the result of put_contract_data after its callee.
        let mut used: HashSet<String> = env.fns.keys().chain(env.statics.keys()).cloned().collect();
        used.extend(["Val", "StorageType", "trap", "unknown", "unknown_i64"].iter().map(|s| s.to_string()));
        for d in &body.var_debug_info {
            if let VarDebugInfoContents::Place(p) = d.value {
                if !p.projection.is_empty() || names.contains_key(&p.local) {
                    continue;
                }
                // An LLVM name (`cmp2.not`) as a Rust identifier, unique here.
                let mut n = crate::rs_name(&d.name.to_string().replace('.', "_"));
                if !used.insert(n.clone()) {
                    n = format!("{n}_{}", p.local.as_usize());
                    used.insert(n.clone());
                }
                names.insert(p.local, n);
            }
        }
        let rpo = body.basic_blocks.reverse_postorder().iter().enumerate().map(|(n, b)| (*b, n)).collect();
        let payloads = val_payload_locals(body, env.val_def);
        let (defs, uses) = def_use_counts(body);
        let single_def = body
            .basic_blocks
            .iter()
            .flat_map(|b| &b.statements)
            .filter_map(|st| match &st.kind {
                StatementKind::Assign(a) => a.0.as_local().filter(|l| defs.get(l) == Some(&1)).map(|l| (l, a.1.clone())),
                _ => None,
            })
            .collect();
        let call_def = body
            .basic_blocks
            .iter()
            .filter_map(|b| match &b.terminator {
                Some(Terminator { kind: TerminatorKind::Call { func, args, destination, .. }, .. }) => {
                    let Operand::Constant(c) = func else { return None };
                    let ty::FnDef(d, _) = c.const_.ty().kind() else { return None };
                    Some((destination.as_local()?, (tcx.item_name(*d).to_string(), args.iter().map(|a| a.node.clone()).collect())))
                }
                _ => None,
            })
            .collect();
        let mut me = Fn_ {
            tcx,
            env,
            body,
            spec,
            fname,
            names,
            payloads,
            rpo,
            defs,
            uses,
            single_def,
            val_arrays: HashMap::new(),
            literal: HashSet::new(),
            addr_locals: HashSet::new(),
            array_lits: HashMap::new(),
            call_def,
            shapes: HashMap::new(),
            cur_bb: START_BLOCK,
            sdk: false,
            declared: HashSet::new(),
            inlined: HashMap::new(),
            ret_locals: HashSet::new(),
            ret_inline: false,
            ret_expr: None,
            prev,
            inter,
            final_pass,
            folded: HashMap::new(),
            out: Vec::new(),
            depth: 0,
            open: Vec::new(),
            used: HashSet::new(),
        };
        me.val_arrays = me.find_val_arrays();
        me.name_fields();
        let (literal, addr_locals) = me.find_literal_arrays();
        me.literal = literal;
        me.addr_locals = addr_locals;
        me
    }

    /// Everything computed from `&raw mut arr`: casts, the exposed address,
    /// the packed `Val::u32` position. Single-definition locals only.
    fn derived_from(&self, arr: Local) -> HashSet<Local> {
        let mut set: HashSet<Local> = self
            .single_def
            .iter()
            .filter(|(_, rv)| matches!(rv, Rvalue::RawPtr(_, p) if p.as_local() == Some(arr)))
            .map(|(l, _)| *l)
            .collect();
        loop {
            let before = set.len();
            for (l, rv) in &self.single_def {
                let from = |o: &Operand<'tcx>| match o {
                    Operand::Copy(p) | Operand::Move(p) => p.as_local().is_some_and(|x| set.contains(&x)),
                    _ => false,
                };
                let derived = match rv {
                    Rvalue::Use(o) | Rvalue::Cast(_, o, _) => from(o),
                    // Packing the address, and pointers into the array.
                    Rvalue::BinaryOp(BinOp::BitOr | BinOp::Shl | BinOp::Offset | BinOp::Add, ab) => from(&ab.0),
                    Rvalue::Aggregate(_, fs) => fs.iter().any(from),
                    _ => false,
                };
                if derived {
                    set.insert(*l);
                }
            }
            if set.len() == before {
                return set;
            }
        }
    }

    /// The position argument of a host call that reads Vals from memory.
    fn val_position(callee: &str) -> Option<usize> {
        Some(match callee {
            "vec_new_from_linear_memory" => 0,
            "map_new_from_linear_memory" | "vec_unpack_to_linear_memory" => 1,
            "map_unpack_to_linear_memory" => 2,
            _ => return None,
        })
    }

    /// The keys-position argument of a host call that reads map keys.
    fn keys_position(callee: &str) -> Option<usize> {
        Some(match callee {
            "map_new_from_linear_memory" => 0,
            "map_unpack_to_linear_memory" | "symbol_index_in_linear_memory" => 1,
            _ => return None,
        })
    }

    /// Arrays handed to the host at a Val-reading position, with their
    /// length. The position is `Val::u32(frame as u32)`: walk that back to
    /// the `&raw mut` it came from.
    fn find_val_arrays(&self) -> HashMap<Local, u64> {
        let mut set = HashMap::new();
        for (_, (callee, args)) in &self.call_def {
            let Some(pos) = Self::val_position(callee) else { continue };
            let Some(arg) = args.get(pos) else { continue };
            // The whole frame is Vals only when the call covers all of it.
            if let Some(arr) = self.array_behind(arg, 0) {
                if let ty::Array(_, n) = self.body.local_decls[arr].ty.kind() {
                    if let Some(n) = n.try_to_target_usize(self.tcx) {
                        if self.len_arg(callee, args) == Some(n) {
                            set.insert(arr, n);
                        }
                    }
                }
            }
        }
        set
    }

    /// Val arrays that can be written as one literal: every slot stored
    /// exactly once, all in the block of the one call that consumes the
    /// array, nothing else touching it, no operand of a stored value
    /// reassigned between its store and the call, and every pointer derived
    /// from the array flowing into that call and nowhere else -- so the call
    /// sees exactly the slots written. Returns the arrays and their plumbing.
    fn find_literal_arrays(&self) -> (HashSet<Local>, HashSet<Local>) {
        let mut plumbing = HashSet::new();
        let arrays = self.find_literal_arrays_inner(&mut plumbing);
        (arrays, plumbing)
    }

    fn find_literal_arrays_inner(&self, plumbing: &mut HashSet<Local>) -> HashSet<Local> {
        use rustc_middle::mir::visit::{PlaceContext, Visitor};
        struct Touch<'a>(Local, &'a mut bool);
        impl<'tcx> Visitor<'tcx> for Touch<'_> {
            fn visit_local(&mut self, l: Local, ctx: PlaceContext, _: Location) {
                if l == self.0 && ctx.is_use() {
                    *self.1 = true;
                }
            }
        }
        let mut out = HashSet::new();
        'arrays: for (&arr, &len) in &self.val_arrays {
            // The one consuming call, and its block.
            let mut consumers = self.call_def.iter().filter(|(_, (callee, args))| {
                Self::val_position(callee).and_then(|p| args.get(p)).and_then(|a| self.array_behind(a, 0)) == Some(arr)
            });
            let (Some((&dest, (_, call_args))), None) = (consumers.next(), consumers.next()) else { continue };
            // Every derived pointer's uses: other derived locals' definitions,
            // or the consuming call's arguments. Anything else could write
            // the array behind our back.
            let derived = self.derived_from(arr);
            for &d in &derived {
                let in_defs = self
                    .single_def
                    .iter()
                    .filter(|(l, _)| derived.contains(l))
                    .filter(|(_, rv)| {
                        let mut n = 0;
                        let mut count = |o: &Operand<'tcx>| {
                            if matches!(o, Operand::Copy(p) | Operand::Move(p) if p.as_local() == Some(d)) {
                                n += 1;
                            }
                        };
                        match rv {
                            Rvalue::Use(o) | Rvalue::Cast(_, o, _) => count(o),
                            Rvalue::BinaryOp(_, ab) => {
                                count(&ab.0);
                                count(&ab.1);
                            }
                            Rvalue::Aggregate(_, fs) => fs.iter().for_each(count),
                            _ => {}
                        }
                        n > 0
                    })
                    .count();
                let in_call = call_args.iter().filter(|o| matches!(o, Operand::Copy(p) | Operand::Move(p) if p.as_local() == Some(d))).count();
                if self.uses.get(&d).copied().unwrap_or(0) != in_defs + in_call {
                    continue 'arrays;
                }
            }
            let Some(bb) = self.body.basic_blocks.iter_enumerated().find(|(_, b)| {
                matches!(&b.terminator, Some(Terminator { kind: TerminatorKind::Call { destination, .. }, .. }) if destination.as_local() == Some(dest))
            }).map(|(bb, _)| bb) else { continue };
            let stmts = &self.body.basic_blocks[bb].statements;
            let mut seen = vec![false; len as usize];
            for (si, st) in stmts.iter().enumerate() {
                let StatementKind::Assign(a) = &st.kind else { continue };
                if a.0.local != arr {
                    continue;
                }
                let [PlaceElem::ConstantIndex { offset, .. }] = a.0.projection.as_slice() else { continue };
                let k = *offset as usize;
                if k >= seen.len() || seen[k] {
                    continue 'arrays;
                }
                seen[k] = true;
                // Operands of the stored value must still mean the same at the call.
                let ms: Vec<Local> = mentions(self.body, bb, si).into_iter().filter(|m| *m != arr).collect();
                for sj in si + 1..stmts.len() {
                    if let StatementKind::Assign(b) = &stmts[sj].kind {
                        if b.0.as_local().is_some_and(|d| ms.contains(&d)) {
                            continue 'arrays;
                        }
                    }
                }
            }
            if !seen.iter().all(|s| *s) {
                continue;
            }
            // Nothing else may touch the array: only its zero-init, the slot
            // stores counted above, and taking its address.
            for (b, data) in self.body.basic_blocks.iter_enumerated() {
                for (si, st) in data.statements.iter().enumerate() {
                    let StatementKind::Assign(a) = &st.kind else { continue };
                    if a.0.local == arr {
                        let ok = (a.0.projection.is_empty() && matches!(a.1, Rvalue::Repeat(..) | Rvalue::Aggregate(..)))
                            || (b == bb && matches!(a.0.projection.as_slice(), [PlaceElem::ConstantIndex { .. }]));
                        if !ok {
                            continue 'arrays;
                        }
                        continue;
                    }
                    if matches!(a.1, Rvalue::RawPtr(_, p) if p.as_local() == Some(arr)) {
                        continue;
                    }
                    let mut touched = false;
                    Touch(arr, &mut touched).visit_statement(st, Location { block: b, statement_index: si });
                    if touched {
                        continue 'arrays;
                    }
                }
                if let Some(t) = &data.terminator {
                    let mut touched = false;
                    Touch(arr, &mut touched).visit_terminator(t, Location { block: b, statement_index: data.statements.len() });
                    if touched {
                        continue 'arrays;
                    }
                }
            }
            plumbing.extend(derived);
            out.insert(arr);
        }
        out
    }

    /// `Val((ptr as u64) << 32 | 4)`, `ptr = &raw mut arr as *mut u8` -> `arr`.
    fn array_behind(&self, o: &Operand<'tcx>, depth: u8) -> Option<Local> {
        self.array_behind_at(o, depth).filter(|(_, off)| *off == 0).map(|(a, _)| a)
    }

    /// `Val((ptr as u64) << 32 | 4)`, `ptr = &raw mut arr as *mut u8` plus a
    /// constant offset -> `(arr, byte offset)`.
    fn array_behind_at(&self, o: &Operand<'tcx>, depth: u8) -> Option<(Local, u64)> {
        if depth > 8 {
            return None;
        }
        match self.def_of(o)? {
            Rvalue::Aggregate(_, fs) => self.array_behind_at(fs.iter().next()?, depth + 1),
            Rvalue::BinaryOp(BinOp::BitOr | BinOp::Shl, ab) => self.array_behind_at(&ab.0, depth + 1),
            Rvalue::BinaryOp(BinOp::Offset | BinOp::Add, ab) => {
                let (a, off) = self.array_behind_at(&ab.0, depth + 1)?;
                Some((a, off + self.konst_u64(&ab.1)?))
            }
            Rvalue::Cast(_, inner, _) | Rvalue::Use(inner) => self.array_behind_at(inner, depth + 1),
            Rvalue::RawPtr(_, p) => p.as_local().filter(|l| self.body.local_decls[*l].ty.is_array()).map(|l| (l, 0)),
            _ => None,
        }
    }

    /// A payload with a made-up name (`v226`, `ld61`, `_13`) that is stored
    /// into a map's value array is named after the key at that position:
    /// `pool`, `user`. Before the literals are rendered.
    fn name_fields(&mut self) {
        let generic = |n: &str| n.strip_prefix('_').unwrap_or(n).trim_start_matches(|c: char| c.is_ascii_lowercase()).chars().all(|c| c.is_ascii_digit());
        let mut used: HashSet<String> = self.names.values().cloned().collect();
        let mut renames: Vec<(Local, String)> = Vec::new();
        for b in self.body.basic_blocks.iter() {
            let Some(Terminator { kind: TerminatorKind::Call { func, args, .. }, .. }) = &b.terminator else { continue };
            let Operand::Constant(c) = func else { continue };
            let ty::FnDef(d, _) = c.const_.ty().kind() else { continue };
            if self.tcx.item_name(*d).as_str() != "map_new_from_linear_memory" {
                continue;
            }
            let Some(keys) = args.first().and_then(|a| self.konst_u64(&a.node)).filter(|b| b & 0xff == 4).and_then(|b| self.spec.keys.get(&(b >> 32))) else { continue };
            let Some((arr, 0)) = args.get(1).and_then(|a| self.array_behind_at(&a.node, 0)) else { continue };
            for st in self.body.basic_blocks.iter().flat_map(|b| &b.statements) {
                let StatementKind::Assign(a) = &st.kind else { continue };
                let [PlaceElem::ConstantIndex { offset, .. }] = a.0.projection.as_slice() else { continue };
                let (Some(key), true) = (keys.get(*offset as usize), a.0.local == arr) else { continue };
                let op = match &a.1 {
                    Rvalue::Use(o) => Some(o),
                    Rvalue::Aggregate(_, fs) => fs.iter().next(),
                    _ => None,
                };
                let Some(l) = op.and_then(|o| self.source_local(o)) else { continue };
                if l.as_usize() <= self.body.arg_count || !self.names.get(&l).map_or(true, |n| generic(n)) || renames.iter().any(|(x, _)| *x == l) {
                    continue;
                }
                let mut n = key.clone();
                if !used.insert(n.clone()) {
                    n = format!("{n}_{}", l.as_usize());
                    used.insert(n.clone());
                }
                renames.push((l, n));
            }
        }
        self.names.extend(renames);
    }

    /// `*(param + off)`: a word this function reads from what a caller built.
    fn param_load(&self, o: &Operand<'tcx>) -> Option<(Local, u64)> {
        let (Operand::Copy(p) | Operand::Move(p)) = o else { return None };
        if let [PlaceElem::Deref] = p.projection.as_slice() {
            return self.param_ptr(&Operand::Copy(Place::from(p.local)), 0);
        }
        match self.def_of(o)? {
            Rvalue::Use(inner) => self.param_load(inner),
            _ => None,
        }
    }

    /// A pointer parameter plus a constant: the parameter and the byte offset.
    fn param_ptr(&self, o: &Operand<'tcx>, off: u64) -> Option<(Local, u64)> {
        if let Operand::Copy(p) | Operand::Move(p) = o {
            if let Some(l) = p.as_local().filter(|l| (1..=self.body.arg_count).contains(&l.as_usize())) {
                return Some((l, off));
            }
        }
        match self.def_of(o)? {
            Rvalue::Cast(_, inner, _) | Rvalue::Use(inner) => self.param_ptr(inner, off),
            Rvalue::BinaryOp(BinOp::Offset | BinOp::Add, ab) => self.param_ptr(&ab.0, off + self.konst_u64(&ab.1)?),
            _ => None,
        }
    }

    /// The switch arms `bb` sits under, for switches on a word read through
    /// a pointer parameter: what a caller decided by what it wrote there.
    /// Walks rustc's dominator tree; an arm applies when the block on the
    /// path is that arm's target.
    fn conds_of(&self, bb: BasicBlock) -> Vec<Cond> {
        let doms = self.body.basic_blocks.dominators();
        let mut out = Vec::new();
        let mut child = bb;
        while let Some(d) = doms.immediate_dominator(child) {
            if let TerminatorKind::SwitchInt { discr, targets } = &self.body.basic_blocks[d].terminator().kind {
                if let Some((p, off)) = self.param_load(discr) {
                    let word = format!("{}@{off}", self.local(p));
                    match targets.iter().find(|(_, t)| *t == child) {
                        Some((v, _)) => out.push((word, vec![v as u64], false)),
                        None if targets.otherwise() == child => out.push((word, targets.iter().map(|(v, _)| v as u64).collect(), true)),
                        None => {}
                    }
                }
            }
            child = d;
        }
        out
    }

    /// The words written into the frame an argument points to, as of a call
    /// in `bb`: byte offset from the pointer -> (the value as the contract
    /// knows it, its constant). Stores along the dominator chain, in order,
    /// through a slot or a pointer into the frame; a store anywhere else, or
    /// a call handed a pointer into the frame, forgets what it may have
    /// overwritten -- from that pointer's offset on. ponytail: a callee
    /// writing below the pointer it was given is not Rust; not considered.
    fn frame_words(&self, bb: BasicBlock, o: &Operand<'tcx>) -> HashMap<u64, (String, Option<u64>)> {
        let Some((arr, base)) = self.array_behind_at(o, 0) else { return HashMap::new() };
        let derived = self.derived_from(arr);
        let doms = self.body.basic_blocks.dominators();
        let mut chain = vec![bb];
        while let Some(d) = doms.immediate_dominator(*chain.last().unwrap()) {
            chain.push(d);
        }
        chain.reverse();
        // (offset, value) of a store, None for one at an unknown offset.
        let store = |a: &(Place<'tcx>, Rvalue<'tcx>)| -> Option<Option<(u64, (String, Option<u64>))>> {
            let off = if a.0.local == arr {
                match a.0.projection.as_slice() {
                    [PlaceElem::ConstantIndex { offset, .. }] => Some(offset * 8),
                    _ => None,
                }
            } else if matches!(a.0.projection.as_slice(), [PlaceElem::Deref]) && derived.contains(&a.0.local) {
                self.array_behind_at(&Operand::Copy(Place::from(a.0.local)), 0).map(|(_, k)| k)
            } else {
                return None; // not a store into this frame
            };
            let (val, k) = match &a.1 {
                Rvalue::Use(op) => (self.key_shape(op).ok(), self.konst_u64(op)),
                rv => (self.as_val_expr(rv).ok(), None),
            };
            Some(off.zip(val).map(|(off, v)| (off, (v, k))))
        };
        // The byte ranges a block's call may write into the frame: a pointer
        // into it handed to a callee that writes through that parameter. The
        // host's unpacks write exactly `len` Vals; a lifted callee, from the
        // pointer on.
        let call_writes = |data: &BasicBlockData<'tcx>| -> Vec<(u64, Option<u64>)> {
            let Some(Terminator { kind: TerminatorKind::Call { func, args, .. }, .. }) = &data.terminator else { return vec![] };
            let name = self.callee_name(func).unwrap_or_default();
            let ops: Vec<Operand<'tcx>> = args.iter().map(|a| a.node.clone()).collect();
            args.iter()
                .enumerate()
                .filter_map(|(j, a)| {
                    let (x, k) = self.array_behind_at(&a.node, 0)?;
                    if x != arr {
                        return None;
                    }
                    let extent = self.write_extent(func, j)?;
                    let exact = matches!((name.as_str(), j), ("vec_unpack_to_linear_memory", 1) | ("map_unpack_to_linear_memory", 2));
                    let end = if exact { self.len_arg(&name, &ops).map(|n| k + 8 * n) } else { extent.map(|e| k + e) };
                    Some((k, end))
                })
                .collect()
        };
        let clobber = |words: &mut HashMap<u64, (String, Option<u64>)>, (k, end): (u64, Option<u64>)| {
            words.retain(|off, _| *off < k || end.is_some_and(|e| *off >= e));
        };
        let mut words: HashMap<u64, (String, Option<u64>)> = HashMap::new();
        for b in &chain {
            let data = &self.body.basic_blocks[*b];
            for st in &data.statements {
                let StatementKind::Assign(a) = &st.kind else { continue };
                match store(a) {
                    Some(Some((off, v))) => {
                        words.insert(off, v);
                    }
                    Some(None) => words.clear(),
                    None => {}
                }
            }
            if *b != bb {
                for r in call_writes(data) {
                    clobber(&mut words, r);
                }
            }
        }
        // Anything off the chain that may have run: forget what it touches.
        for (b, data) in self.body.basic_blocks.iter_enumerated() {
            if chain.contains(&b) {
                continue;
            }
            for st in &data.statements {
                let StatementKind::Assign(a) = &st.kind else { continue };
                match store(a) {
                    Some(Some((off, _))) => {
                        words.remove(&off);
                    }
                    Some(None) => words.clear(),
                    None => {}
                }
            }
            for r in call_writes(data) {
                clobber(&mut words, r);
            }
        }
        words.into_iter().filter_map(|(k, v)| k.checked_sub(base).map(|o| (o, v))).collect()
    }

    /// The length a host call is told, as a constant.
    fn len_arg(&self, callee: &str, args: &[Operand<'tcx>]) -> Option<u64> {
        let i = match callee {
            "vec_new_from_linear_memory" => 1,
            "map_new_from_linear_memory" | "vec_unpack_to_linear_memory" => 2,
            "map_unpack_to_linear_memory" => 3,
            _ => return None,
        };
        self.konst_u64(args.get(i)?).filter(|b| b & 0xff == 4).map(|b| b >> 32)
    }

    /// The Vals a host call reads from a frame that is not one whole Val
    /// array: the slots from the offset, each stored exactly once in this
    /// block before the call, with nothing in the block writing through a
    /// pointer into the frame. Exact, or None.
    fn range_shape(&self, bb: BasicBlock, arr: Local, first: u64, len: u64) -> Option<Vec<(String, Option<Local>)>> {
        let stmts = &self.body.basic_blocks[bb].statements;
        let derived = self.derived_from(arr);
        let mut out: Vec<Option<(String, Option<Local>)>> = vec![None; len as usize];
        for st in stmts {
            let StatementKind::Assign(a) = &st.kind else { continue };
            if a.0.projection.iter().any(|e| matches!(e, PlaceElem::Deref)) && derived.contains(&a.0.local) {
                return None; // a write through a pointer into the frame
            }
            if a.0.local != arr {
                continue;
            }
            let [PlaceElem::ConstantIndex { offset, .. }] = a.0.projection.as_slice() else { continue };
            let Some(k) = offset.checked_sub(first).filter(|k| *k < len) else { continue };
            if out[k as usize].is_some() {
                return None; // stored twice: not a plain initialiser
            }
            let src = match &a.1 {
                Rvalue::Use(o) => self.source_local(o),
                _ => None,
            };
            out[k as usize] = Some((self.as_val_expr(&a.1).ok()?, src));
        }
        out.into_iter().collect()
    }

    /// The Rust type a local is declared with: `Val` for a payload local,
    /// `[Val; N]` for a frame the host reads Vals from.
    fn local_ty(&self, l: Local) -> String {
        if self.payloads.contains(&l) {
            return "Val".into();
        }
        if let Some(n) = self.val_arrays.get(&l) {
            return format!("[Val; {n}]");
        }
        // `&raw mut` of a Val frame is a pointer to one.
        if let Some(Rvalue::RawPtr(_, p)) = self.single_def.get(&l) {
            if let Some(n) = p.as_local().and_then(|a| self.val_arrays.get(&a)) {
                return format!("*mut [Val; {n}]");
            }
        }
        ty_str(self.tcx, self.body.local_decls[l].ty)
    }

    /// The Val local an operand is the payload of, through copies: `v`,
    /// `v.0`, or a local defined as either.
    fn val_source(&self, o: &Operand<'tcx>) -> Option<Local> {
        let p = match o {
            Operand::Copy(p) | Operand::Move(p) => p,
            _ => return None,
        };
        if self.val_of_payload_place(p).is_some() {
            return Some(p.local);
        }
        let l = p.as_local()?;
        if self.body.local_decls[l].ty == self.env.val || self.payloads.contains(&l) {
            return Some(l);
        }
        match self.def_of(o)? {
            Rvalue::Use(inner) => self.val_source(inner),
            _ => None,
        }
    }

    /// The local a stored value comes from: its Val local, else itself.
    fn source_local(&self, o: &Operand<'tcx>) -> Option<Local> {
        self.val_source(o).or_else(|| match o {
            Operand::Copy(p) | Operand::Move(p) => p.as_local(),
            _ => None,
        })
    }

    fn line(&mut self, s: impl Into<String>) {
        self.out.push((self.depth, s.into()));
    }

    fn raw_name(&self, l: Local) -> String {
        self.names.get(&l).cloned().unwrap_or_else(|| format!("_{}", l.as_usize()))
    }

    fn local(&self, l: Local) -> String {
        if let Some((e, _)) = self.folded.get(&l) {
            return e.clone();
        }
        self.raw_name(l)
    }

    fn place(&self, p: &Place<'tcx>) -> String {
        let mut s = self.local(p.local);
        if self.folded.contains_key(&p.local) && !p.projection.is_empty() {
            s = format!("({s})");
        }
        for e in p.projection {
            s = match e {
                PlaceElem::Deref => format!("(*{s})"),
                PlaceElem::Field(f, _) => format!("{s}.{}", f.as_usize()),
                PlaceElem::Index(l) => format!("{s}[{} as usize]", self.local(l)),
                PlaceElem::ConstantIndex { offset, .. } => format!("{s}[{offset}]"),
                PlaceElem::Downcast(..) => s,
                other => format!("{s}/* {other:?} */"),
            };
        }
        s
    }

    fn konst(&self, c: &ConstOperand<'tcx>) -> R<String> {
        let tcx = self.tcx;
        let ty = c.const_.ty();
        if let ty::FnDef(def_id, _) = ty.kind() {
            return Ok(tcx.item_name(*def_id).to_string());
        }
        if ty.is_unit() {
            return Ok("()".into());
        }
        let Some(scalar) = c.const_.try_to_scalar() else { return Err(format!("non-scalar constant {:?}", c.const_)) };
        Ok(match scalar {
            Scalar::Int(i) => {
                let bits = i.to_bits(i.size());
                match ty.kind() {
                    ty::Bool => (bits != 0).to_string(),
                    ty::Adt(def, _) if def.did() == self.env.val_def => self.val_str(bits as u64),
                    ty::Adt(def, _) if def.is_enum() => {
                        let (v, _) = def.discriminants(tcx).find(|(_, d)| d.val == bits).ok_or("enum constant without a variant")?;
                        format!("{}::{}", tcx.item_name(def.did()), def.variant(v).name)
                    }
                    ty::RawPtr(..) => format!("({bits}usize as {})", ty_str(tcx, ty)),
                    ty::Int(_) => format!("{}{}", i.to_int(i.size()), ty_str(tcx, ty)),
                    _ => format!("{bits}{}", ty_str(tcx, ty)),
                }
            }
            Scalar::Ptr(p, _) => match tcx.try_get_global_alloc(p.provenance.alloc_id()) {
                Some(GlobalAlloc::Static(d)) => format!("(&raw mut {} as {})", tcx.item_name(d), ty_str(tcx, ty)),
                _ => return Err("pointer constant into an allocation".into()),
            },
        })
    }

    fn operand(&self, o: &Operand<'tcx>) -> R<String> {
        match o {
            // A slot of a Val frame read as the integer it also is.
            Operand::Copy(p) | Operand::Move(p) if self.is_val_slot(p) => Ok(format!("{}.0", self.place(p))),
            Operand::Copy(p) | Operand::Move(p) => Ok(self.place(p)),
            Operand::Constant(c) => self.konst(c),
            Operand::RuntimeChecks(_) => Err("runtime-checks operand".into()),
        }
    }

    /// Display names of this function's parameters, in order.
    fn param_names(&self) -> Vec<String> {
        self.body.args_iter().map(|l| self.local(l)).collect()
    }

    fn rvalue(&self, rv: &Rvalue<'tcx>) -> R<String> {
        let tcx = self.tcx;
        Ok(match rv {
            Rvalue::Use(o) => self.operand(o)?,
            Rvalue::CopyForDeref(p) => self.place(p),
            Rvalue::Repeat(o, n) => format!("[{}; {}]", self.operand(o)?, n.try_to_target_usize(tcx).ok_or("array length")?),
            Rvalue::BinaryOp(op, ab) => {
                let (a, mut b) = (self.operand(&ab.0)?, self.operand(&ab.1)?);
                if matches!(op, BinOp::Eq | BinOp::Ne) {
                    if let Some(k) = self.konst_u64(&ab.1) {
                        if self.is_tag(&ab.0) {
                            if let Some(n) = tag_name(k) {
                                b = format!("Tag::{n}");
                            }
                        } else if let Some(i) = self.payload_of_param(&ab.0) {
                            // A parameter's payload against a literal: the literal is a Val.
                            b = format!("{}.0", self.val_str(k));
                            if let Some(c) = self.spec.param_enum(&self.fname, i).and_then(|e| self.spec.enum_case(e, k >> 32).map(|c| format!("{e}::{c}"))) {
                                if k & 0xff == 4 {
                                    b = format!("{b} /* {c} */");
                                }
                            }
                        } else if let Some(c) = self.enum_of(&ab.0).and_then(|e| self.spec.enum_case(e, k).map(|c| format!("{e}::{c}"))) {
                            b = format!("{b} /* {c} */");
                        }
                    }
                }
                match op {
                    BinOp::Add => format!("{a}.wrapping_add({b})"),
                    BinOp::Sub => format!("{a}.wrapping_sub({b})"),
                    BinOp::Mul => format!("{a}.wrapping_mul({b})"),
                    BinOp::Div => format!("{a} / {b}"),
                    BinOp::Rem => format!("{a} % {b}"),
                    BinOp::BitAnd => format!("{a} & {b}"),
                    BinOp::BitOr => format!("{a} | {b}"),
                    BinOp::BitXor => format!("{a} ^ {b}"),
                    BinOp::Shl => format!("{a}.wrapping_shl({b} as u32)"),
                    BinOp::Shr => format!("{a}.wrapping_shr({b} as u32)"),
                    BinOp::Eq => format!("{a} == {b}"),
                    BinOp::Ne => format!("{a} != {b}"),
                    BinOp::Lt => format!("{a} < {b}"),
                    BinOp::Le => format!("{a} <= {b}"),
                    BinOp::Gt => format!("{a} > {b}"),
                    BinOp::Ge => format!("{a} >= {b}"),
                    BinOp::Offset => format!("{a}.wrapping_offset({b})"),
                    other => return Err(format!("binary op {other:?}")),
                }
            }
            Rvalue::UnaryOp(UnOp::Not, a) => format!("!{}", self.operand(a)?),
            Rvalue::UnaryOp(UnOp::Neg, a) => format!("{}.wrapping_neg()", self.operand(a)?),
            Rvalue::Cast(kind, o, ty) => {
                let (o, t) = (self.operand(o)?, ty_str(tcx, *ty));
                match kind {
                    CastKind::Transmute => format!("core::mem::transmute::<_, {t}>({o})"),
                    _ => format!("{o} as {t}"),
                }
            }
            Rvalue::Aggregate(kind, fields) => {
                let fs: Vec<String> = fields.iter().map(|f| self.operand(f)).collect::<R<_>>()?;
                match **kind {
                    AggregateKind::Adt(def, _, ..) if def == self.env.val_def => format!("Val({})", fs.join(", ")),
                    AggregateKind::Adt(def, variant, ..) => {
                        format!("{}::{}", tcx.item_name(def), tcx.adt_def(def).variant(variant).name)
                    }
                    AggregateKind::Array(_) => format!("[{}]", fs.join(", ")),
                    AggregateKind::Tuple => format!("({})", fs.join(", ")),
                    _ => return Err(format!("aggregate {kind:?}")),
                }
            }
            Rvalue::RawPtr(k, p) => {
                format!("&raw {} {}", if matches!(k, RawPtrKind::Mut) { "mut" } else { "const" }, self.place(p))
            }
            Rvalue::Discriminant(p) => format!("({} as u64)", self.place(p)),
            other => return Err(format!("rvalue {other:?}")),
        })
    }

    /// A folded operand's rvalue, if it was folded.
    fn folded_rv(&self, o: &Operand<'tcx>) -> Option<&Rvalue<'tcx>> {
        match o {
            Operand::Copy(p) | Operand::Move(p) => self.folded.get(&p.as_local()?).map(|(_, rv)| rv),
            _ => None,
        }
    }

    /// Is this place a slot of a frame the host reads Vals from?
    fn is_val_slot(&self, pl: &Place<'tcx>) -> bool {
        self.val_arrays.contains_key(&pl.local) && matches!(pl.projection.as_slice(), [PlaceElem::ConstantIndex { .. }])
    }

    /// The right-hand side of an assignment as Rust. A destination that holds
    /// a Val -- a payload local, a Val frame slot -- gets the value as a Val.
    fn assign_expr(&self, pl: &Place<'tcx>, rv: &Rvalue<'tcx>) -> R<String> {
        let is_val_agg = |rv: &Rvalue<'tcx>| matches!(rv, Rvalue::Aggregate(k, _) if matches!(**k, AggregateKind::Adt(d, ..) if d == self.env.val_def));
        if pl.as_local().is_some_and(|l| self.payloads.contains(&l)) || self.is_val_slot(pl) {
            return self.as_val_expr(rv);
        }
        if let Rvalue::Repeat(_, n) = rv {
            if let Some(n) = pl.as_local().and_then(|l| self.val_arrays.get(&l)).or(n.try_to_target_usize(self.tcx).as_ref()) {
                if pl.as_local().is_some_and(|l| self.val_arrays.contains_key(&l)) {
                    return Ok(format!("[Val(0); {n}]"));
                }
            }
        }
        if is_val_agg(rv) {
            if let Rvalue::Aggregate(_, fs) = rv {
                let o = fs.iter().next().ok_or("Val without a payload")?;
                return self.as_val_expr(&Rvalue::Use(o.clone()));
            }
        }
        self.rvalue(rv)
    }

    /// `v` when the place is `v.0` of a Val-typed local.
    fn val_of_payload_place(&self, p: &Place<'tcx>) -> Option<String> {
        if let [PlaceElem::Field(f, _)] = p.projection.as_slice() {
            if f.as_usize() == 0 && self.body.local_decls[p.local].ty == self.env.val {
                return Some(self.local(p.local));
            }
        }
        None
    }

    /// An rvalue computing a Val payload, written as the Val it is: a constant
    /// decoded, `v.0` back to `v`, a payload local by name, `(x << 32) | 4` as
    /// `Val::u32(x)`, anything else wrapped.
    fn as_val_expr(&self, rv: &Rvalue<'tcx>) -> R<String> {
        match rv {
            Rvalue::Use(Operand::Constant(c)) => {
                let bits = c.const_.try_to_scalar_int().ok_or("payload constant")?;
                Ok(self.val_str(bits.to_bits(bits.size()) as u64))
            }
            Rvalue::Use(o @ (Operand::Copy(p) | Operand::Move(p))) => {
                if let Some(v) = self.val_of_payload_place(p) {
                    return Ok(v);
                }
                if self.is_val_slot(p) {
                    return Ok(self.place(p));
                }
                if p.as_local().is_some_and(|l| self.payloads.contains(&l)) {
                    return Ok(self.place(p));
                }
                match self.def_of(o) {
                    Some(Rvalue::Use(Operand::Copy(q) | Operand::Move(q))) if self.val_of_payload_place(q).is_some() => {
                        Ok(self.val_of_payload_place(q).unwrap())
                    }
                    Some(inner) if !matches!(inner, Rvalue::Use(_)) => self.val_of_expr(inner),
                    _ => Ok(format!("Val({})", self.place(p))),
                }
            }
            _ => self.val_of_expr(rv),
        }
    }

    /// A Val whose payload is computed by `rv`. `(x << 32) | 4` is the U32Val
    /// encoding of `x`, and reads as such.
    fn val_of_expr(&self, rv: &Rvalue<'tcx>) -> R<String> {
        if let Rvalue::BinaryOp(BinOp::BitOr, ab) = rv {
            if self.konst_u64(&ab.1) == Some(4) {
                if let Some(Rvalue::BinaryOp(BinOp::Shl, xy)) = self.folded_rv(&ab.0) {
                    if self.konst_u64(&xy.1) == Some(32) {
                        return Ok(format!("Val::u32({} as u32)", self.operand(&xy.0)?));
                    }
                }
            }
        }
        Ok(format!("Val({})", self.rvalue(rv)?))
    }

    /// A Val constant, with what the spec says about it.
    fn val_str(&self, bits: u64) -> String {
        let base = val_expr(bits);
        let (tag, body) = (bits & 0xff, bits >> 8);
        let note = match tag {
            3 if body & 0xff_ffff == 0 => self.spec.error_name(body >> 24),
            14 => sym_str(body).and_then(|s| self.spec.union_case(&s)),
            _ => None,
        };
        match note {
            Some(n) => format!("{base} /* {n} */"),
            None => base,
        }
    }

    /// The rvalue that defines a plain-local operand, folded or single-def.
    fn def_of(&self, o: &Operand<'tcx>) -> Option<&Rvalue<'tcx>> {
        let l = match o {
            Operand::Copy(p) | Operand::Move(p) => p.as_local()?,
            _ => return None,
        };
        self.folded.get(&l).map(|(_, rv)| rv).or_else(|| self.single_def.get(&l))
    }

    /// If this operand is the payload of an exported parameter (`param.0`,
    /// possibly through a copy), that parameter's index.
    fn payload_of_param(&self, o: &Operand<'tcx>) -> Option<usize> {
        let p = match o {
            Operand::Copy(p) | Operand::Move(p) => p,
            _ => return None,
        };
        if let [PlaceElem::Field(f, _)] = p.projection.as_slice() {
            let i = p.local.as_usize();
            return (f.as_usize() == 0 && i >= 1 && i <= self.body.arg_count).then_some(i - 1);
        }
        match self.def_of(o)? {
            Rvalue::Use(inner) => self.payload_of_param(inner),
            _ => None,
        }
    }

    /// If this operand is the U32Val body of a parameter declared as an
    /// integer enum -- `(param.0 >> 32) as uN` -- that enum's name.
    fn enum_of(&self, o: &Operand<'tcx>) -> Option<&str> {
        match self.def_of(o)? {
            Rvalue::Cast(CastKind::IntToInt, inner, _) | Rvalue::Use(inner) => self.enum_of(inner),
            Rvalue::BinaryOp(BinOp::Shr, xy) if self.konst_u64(&xy.1) == Some(32) => {
                self.spec.param_enum(&self.fname, self.payload_of_param(&xy.0)?)
            }
            _ => None,
        }
    }

    /// Is this operand `x & 0xff`, a Val's tag? Then constants compared with
    /// it are tags and read by name.
    fn is_tag(&self, o: &Operand<'tcx>) -> bool {
        let rv = match o {
            Operand::Copy(p) | Operand::Move(p) => p.as_local().and_then(|l| self.folded.get(&l).map(|(_, rv)| rv).or_else(|| self.single_def.get(&l))),
            _ => None,
        };
        matches!(rv, Some(Rvalue::BinaryOp(BinOp::BitAnd, ab)) if self.konst_u64(&ab.1) == Some(0xff))
    }

    fn konst_u64(&self, o: &Operand<'tcx>) -> Option<u64> {
        match o {
            Operand::Constant(c) => c.const_.try_to_scalar_int().map(|i| i.to_bits(i.size()) as u64),
            _ => None,
        }
    }

    /// Emit the statements of a block. A pure single-use temporary is folded
    /// into its use; a pure statement nothing reads is not written -- rustc
    /// kept it only for its debuginfo name.
    fn stmts(&mut self, bb: BasicBlock) -> R<()> {
        self.cur_bb = bb;
        let data = &self.body.basic_blocks[bb];
        for (si, st) in data.statements.iter().enumerate() {
            if let StatementKind::Assign(a) = &st.kind {
                let (pl, rv) = &**a;
                // The address plumbing of a literal array is the literal itself.
                if pl.as_local().is_some_and(|l| self.addr_locals.contains(&l)) {
                    continue;
                }
                // A literal Val array: its zero-init vanishes and its slot
                // stores are collected for the call that takes the array.
                if self.literal.contains(&pl.local) {
                    if pl.projection.is_empty() {
                        continue;
                    }
                    if let [PlaceElem::ConstantIndex { offset, .. }] = pl.projection.as_slice() {
                        let e = self.as_val_expr(rv)?;
                        // The Val local behind the element, for its shape.
                        let src = match rv {
                            Rvalue::Use(o) => self.source_local(o),
                            _ => None,
                        };
                        let n = self.val_arrays[&pl.local] as usize;
                        let slots = self.array_lits.entry(pl.local).or_insert_with(|| vec![None; n]);
                        slots[*offset as usize] = Some((e, src));
                        continue;
                    }
                }
                if let Some(l) = pl.as_local().filter(|l| *l != Local::ZERO && l.as_usize() > self.body.arg_count) {
                    let uses = self.uses.get(&l).copied().unwrap_or(0);
                    if pure(rv) && uses == 0 {
                        continue;
                    }
                    // An array is only ever used as a place (`&raw mut`, `[i]`); it stays.
                    let is_array = self.body.local_decls[l].ty.is_array();
                    if pure(rv) && !is_array && uses == 1 && self.defs.get(&l) == Some(&1) && self.use_follows(bb, si, l) {
                        let e = self.assign_expr(pl, rv)?;
                        let e = if e.contains(' ') && !e.starts_with("Val") { format!("({e})") } else { e };
                        self.folded.insert(l, (e, rv.clone()));
                        continue;
                    }
                }
            }
            self.stmt(st)?;
        }
        Ok(())
    }

    /// Is the one use of `l` later in this block, with nothing in between
    /// reassigning an operand of its definition?
    fn use_follows(&self, bb: BasicBlock, si: usize, l: Local) -> bool {
        let def_mentions: Vec<Local> = mentions(self.body, bb, si).into_iter().filter(|m| *m != l).collect();
        let n = self.body.basic_blocks[bb].statements.len();
        for sj in si + 1..=n {
            let m = mentions(self.body, bb, sj);
            if m.contains(&l) {
                return true;
            }
            if let Some(StatementKind::Assign(a)) = self.body.basic_blocks[bb].statements.get(sj).map(|s| &s.kind) {
                if let Some(d) = a.0.as_local() {
                    if def_mentions.contains(&d) {
                        return false;
                    }
                }
            }
        }
        false
    }

    fn stmt(&mut self, st: &Statement<'tcx>) -> R<()> {
        match &st.kind {
            StatementKind::Assign(a) => {
                let (pl, rv) = &**a;
                if pl.ty(&self.body.local_decls, self.tcx).ty.is_unit() {
                    return Ok(()); // `_x = const ()`, or the destination of a void call
                }
                if self.sdk {
                    self.sdk_stmt(pl, rv)?;
                } else {
                    let s = format!("{} = {};", self.place(pl), self.assign_expr(pl, rv)?);
                    self.line(s);
                    if let [PlaceElem::Deref] = pl.projection.as_slice() {
                        self.wrote_through(&Operand::Copy(Place::from(pl.local)), Some(8));
                    }
                }
                // A shape travels through a copy, a phi copy or a `Val(..)`
                // of a payload local included; what reaches `_0` is what
                // this function returns.
                let carried = match rv {
                    Rvalue::Use(o) => Some(o),
                    Rvalue::Aggregate(k, fs) if matches!(**k, AggregateKind::Adt(d, ..) if d == self.env.val_def) => fs.iter().next(),
                    _ => None,
                };
                if let (Some(dst), Some(o)) = (pl.as_local(), carried) {
                    let src = self.source_local(o);
                    let sh = match o {
                        Operand::Constant(c) => c.const_.try_to_scalar_int().filter(|_| c.const_.ty() == self.env.val).map(|i| self.val_str(i.to_bits(i.size()) as u64)),
                        _ => src
                            .and_then(|l| self.shape_of(l).or_else(|| (l.as_usize() >= 1 && l.as_usize() <= self.body.arg_count).then(|| self.local(l))))
                            // A word read from what a caller built: the caller knows it.
                            .or_else(|| self.param_load(o).map(|(p, off)| format!("{}@{off}", self.local(p)))),
                    };
                    if let Some(sh) = sh {
                        if dst == Local::ZERO {
                            // Each alternative with the arms it was made under.
                            let entries = src.and_then(|l| self.shapes.get(&l).cloned()).unwrap_or_else(|| vec![(self.conds_of(self.cur_bb), sh.clone())]);
                            for (conds, s) in entries {
                                self.returned(s, conds);
                            }
                        }
                        self.push_shape(dst, sh);
                    }
                }
            }
            StatementKind::SetDiscriminant { place, variant_index } => {
                let ty = place.ty(&self.body.local_decls, self.tcx).ty;
                let ty::Adt(def, _) = ty.kind() else { return Err("SetDiscriminant on a non-enum".into()) };
                let s = format!("{} = {}::{};", self.place(place), self.tcx.item_name(def.did()), def.variant(*variant_index).name);
                self.line(s);
            }
            StatementKind::StorageLive(_)
            | StatementKind::StorageDead(_)
            | StatementKind::Nop
            | StatementKind::PlaceMention(_)
            | StatementKind::FakeRead(..)
            | StatementKind::ConstEvalCounter
            | StatementKind::BackwardIncompatibleDropHint { .. }
            | StatementKind::AscribeUserType(..) => {}
            other => return Err(format!("statement {other:?}")),
        }
        Ok(())
    }

    fn call_line(&mut self, bb: BasicBlock, func: &Operand<'tcx>, args: &[Spanned<Operand<'tcx>>], destination: &Place<'tcx>) -> R<()> {
        self.cur_bb = bb;
        let f = self.operand(func)?;
        for (j, a) in args.iter().enumerate() {
            if let Some(ext) = self.write_extent(func, j) {
                self.wrote_through(&a.node, ext);
            }
        }
        let val_pos = Self::val_position(&f);
        let keys_pos = Self::keys_position(&f);
        self.inter.borrow_mut().called.insert(f.clone());
        // A function that hands the host a constant error is a panic wrapper.
        if f == "fail_with_error" {
            if let Some(e) = args.first().and_then(|a| self.konst_u64(&a.node)) {
                let e = self.val_str(e);
                self.inter.borrow_mut().fails.entry(self.fname.clone()).or_insert(e);
            }
        }
        let mut a: Vec<String> = Vec::new();
        let mut elems: Option<Vec<(String, Option<Local>)>> = None;
        let mut keys: Option<Vec<String>> = None;
        let mut text: Option<String> = None;
        // The text the code can carry as a literal; the array length behind a `pos(..)`.
        let mut literal: Option<String> = None;
        let mut pos_len: Option<u64> = None;
        let arg_ops: Vec<Operand<'tcx>> = args.iter().map(|a| a.node.clone()).collect();
        for (k, arg) in args.iter().enumerate() {
            // The position of a Val array: the array itself, as a literal
            // when it is written whole right here, else by name.
            if Some(k) == val_pos {
                if let Some((arr, off)) = self.array_behind_at(&arg.node, 0) {
                    if let Some(lits) = self.array_lits.get(&arr).filter(|l| off == 0 && l.iter().all(Option::is_some)) {
                        let es: Vec<(String, Option<Local>)> = lits.iter().flatten().cloned().collect();
                        a.push(format!("pos(&[{}])", es.iter().map(|(e, _)| e.as_str()).collect::<Vec<_>>().join(", ")));
                        pos_len = Some(es.len() as u64);
                        elems = Some(es);
                        continue;
                    }
                    if let Some(&n) = self.val_arrays.get(&arr).filter(|_| off == 0) {
                        a.push(format!("pos(&{})", self.raw_name(arr)));
                        pos_len = Some(n);
                        continue;
                    }
                    // Part of a frame: the slots it covers, if they are plainly written here.
                    if let Some(len) = self.len_arg(&f, &arg_ops) {
                        if off % 8 == 0 {
                            elems = self.range_shape(bb, arr, off / 8, len);
                        }
                    }
                }
            }
            let mut s = self.operand(&arg.node)?;
            // The rodata position of a map's keys: name them.
            if Some(k) == keys_pos {
                if let Some(ks) = self.konst_u64(&arg.node).filter(|b| b & 0xff == 4).and_then(|b| self.spec.keys.get(&(b >> 32))) {
                    s = format!("{s} /* {} */", ks.iter().map(|k| format!("{k:?}")).collect::<Vec<_>>().join(", "));
                    keys = Some(ks.clone());
                }
            }
            // The rodata position of a symbol's or string's text: show it.
            if k == 0 && matches!(f.as_str(), "symbol_new_from_linear_memory" | "string_new_from_linear_memory") {
                let u32val = |o: &Operand<'tcx>| self.konst_u64(o).filter(|b| b & 0xff == 4).map(|b| b >> 32);
                let pos = u32val(&arg.node);
                let len = args.get(1).and_then(|a| u32val(&a.node));
                let t = match (pos, len) {
                    (Some(p), Some(l)) => self.spec.text_at(p, l).or_else(|| self.spec.strings.get(&p).cloned()),
                    (Some(p), None) => self.spec.strings.get(&p).cloned(),
                    _ => None,
                };
                if let Some(t) = t {
                    if len == Some(t.len() as u64) {
                        literal = Some(t.clone());
                    }
                    s = format!("{s} /* {t:?} */");
                    text = Some(t);
                }
            }
            a.push(s);
        }
        // Unpacking one spec type's fields or cases: a `try_from_val` derive.
        if let Some(t) = keys.as_ref().and_then(|ks| match f.as_str() {
            "map_unpack_to_linear_memory" => self.spec.struct_for_keys(ks),
            "symbol_index_in_linear_memory" => self.spec.union_for_cases(ks),
            _ => None,
        }) {
            self.inter.borrow_mut().unpacks.entry(self.fname.clone()).or_default().push(t.to_string());
        }
        // The SDK constructor the call is, with its data as the literal the
        // source had: the host reads the same bytes. `show` is the callee as
        // written; `f` stays the callee as lifted.
        let mut show = self.display(&f);
        if let Some(&(i, j, _)) = self.prev.text_helpers.get(&f) {
            let is_param = |o: &Operand<'tcx>, idx: usize| matches!(o, Operand::Copy(p) | Operand::Move(p) if p.as_local() == Some(Local::from_usize(idx + 1)));
            let own = self.prev.text_helpers.get(&self.fname).is_some_and(|&(si, sj, _)| is_param(&arg_ops[i], si) && is_param(&arg_ops[j], sj));
            literal = match (self.konst_u64(&arg_ops[i]), self.konst_u64(&arg_ops[j])) {
                (Some(p), Some(l)) => self.spec.text_at(p, l),
                _ => None,
            };
            a[i] = match (&literal, own) {
                (Some(t), _) => format!("{t:?}"),
                (None, true) => "s".into(),
                (None, false) => format!("str_at({} as u64, {} as u64)", a[i], a[j]),
            };
            a.remove(j);
        } else if let Some(t) = &literal {
            show = if f.starts_with("symbol") { "Val::symbol".into() } else { "Val::string".into() };
            a = vec![format!("{t:?}")];
        } else if let Some(n) = pos_len.filter(|n| self.len_arg(&f, &arg_ops) == Some(*n)) {
            let inner = |s: &str| s[4..s.len() - 1].to_string(); // `pos(X)` -> `X`
            match f.as_str() {
                "vec_new_from_linear_memory" => {
                    show = "Val::vec".into();
                    a = vec![inner(&a[0])];
                }
                "map_new_from_linear_memory" if keys.as_ref().is_some_and(|k| k.len() as u64 == n) => {
                    show = "Val::map".into();
                    let ks = keys.clone().unwrap_or_default().iter().map(|k| format!("{k:?}")).collect::<Vec<_>>().join(", ");
                    a = vec![format!("&[{ks}]"), inner(&a[1])];
                }
                _ => {}
            }
        }
        // What was just built, in the contract's own terms.
        let shape = match (f.as_str(), &elems, &keys) {
            ("vec_new_from_linear_memory", Some(es), _) => {
                let parts: Vec<String> = es.iter().map(|(e, src)| src.and_then(|l| self.shape_of(l)).unwrap_or_else(|| e.clone())).collect();
                let sym = parts.first().and_then(|p| p.strip_prefix("Val::sym(\"").or_else(|| p.strip_prefix("Symbol(\""))).and_then(|r| r.split('"').next());
                match sym.and_then(|s| self.spec.union_case(s)) {
                    Some(case) if parts.len() == 1 => Some(case),
                    Some(case) => Some(format!("{case}({})", parts[1..].join(", "))),
                    None => Some(format!("Vec[{}]", parts.join(", "))),
                }
            }
            ("symbol_new_from_linear_memory", _, _) if text.is_some() => {
                let t = text.clone().unwrap_or_default();
                Some(match self.spec.union_case(&t) {
                    Some(case) => format!("Symbol({t:?}) /* {case} */"),
                    None => format!("Symbol({t:?})"),
                })
            }
            ("string_new_from_linear_memory", _, _) if text.is_some() => Some(format!("String({:?})", text.clone().unwrap_or_default())),
            // A symbol from a position this function was given: the text is
            // the caller's to supply, once `substitute` has put its argument in.
            ("symbol_new_from_linear_memory" | "string_new_from_linear_memory", _, _) => Some(format!(
                "{}(@{}, {})",
                if f.starts_with("symbol") { "Symbol" } else { "String" },
                a.first().cloned().unwrap_or_default(),
                a.get(1).cloned().unwrap_or_default()
            )),
            // A lifted helper whose returned shape the previous pass
            // recorded: its parameters stand for our arguments.
            (callee, _, _) => {
                let templates = self.prev.ret_shapes.get(callee).cloned().unwrap_or_default();
                if templates.is_empty() {
                    None
                } else {
                    let arg_shapes: Vec<String> = args.iter().map(|a| self.key_shape(&a.node)).collect::<R<_>>()?;
                    // What this block wrote into the frames it passes decides
                    // the callee's arms and fills its loads; a word it did not
                    // write keeps every alternative.
                    let frames: Vec<HashMap<u64, (String, Option<u64>)>> = args.iter().map(|a| self.frame_words(bb, &a.node)).collect();
                    let word = |w: &str, params: &[String]| -> Option<(String, Option<u64>)> {
                        let (p, off) = w.split_once('@')?;
                        frames.get(params.iter().position(|x| x == p)?)?.get(&off.parse::<u64>().ok()?).cloned()
                    };
                    let out: Vec<String> = templates
                        .iter()
                        .filter(|(_, params, conds)| {
                            conds.iter().all(|(w, vals, neg)| match word(w, params).and_then(|(_, k)| k) {
                                Some(c) => vals.contains(&c) != *neg,
                                None => true,
                            })
                        })
                        .map(|(t, params, _)| {
                            let mut t = t.clone();
                            for (i, p) in params.iter().enumerate() {
                                for (off, (v, _)) in frames.get(i).into_iter().flatten() {
                                    t = t.replace(&format!("{p}@{off}"), v);
                                }
                            }
                            self.resolve_text(substitute(&blank_words(&t), params, &arg_shapes))
                        })
                        .collect();
                    Some(alternatives(out))
                }
            }
        };
        let shape = shape.or_else(|| match (f.as_str(), &elems, &keys) {
            ("map_new_from_linear_memory", es, Some(ks)) => {
                let fields: Vec<String> = ks
                    .iter()
                    .enumerate()
                    .map(|(i, k)| match es.as_ref().and_then(|e| e.get(i)) {
                        Some((e, src)) => {
                            let v = src.and_then(|l| self.shape_of(l)).unwrap_or_else(|| e.clone());
                            if v == *k { k.clone() } else { format!("{k}: {v}") }
                        }
                        None => k.clone(),
                    })
                    .collect();
                Some(match self.spec.struct_for_keys(ks) {
                    Some(st) => format!("{st} {{ {} }}", fields.join(", ")),
                    None => format!("Map{{ {} }}", fields.join(", ")),
                })
            }
            _ => None,
        });
        let dty = self.body.local_decls[destination.local].ty;
        let unread = destination.as_local().is_some_and(|l| self.uses.get(&l).copied().unwrap_or(0) == 0);
        let mut s = if dty.is_unit() || dty.is_never() || unread {
            format!("{show}({});", a.join(", "))
        } else {
            format!("{} = {show}({});", self.place(destination), a.join(", "))
        };
        if let Some(sh) = &shape {
            // Text already in the code needs only what the spec calls it.
            let note = match &literal {
                Some(t) => self.spec.union_case(t),
                None => Some(sh.clone()),
            };
            if let Some(n) = note {
                s = format!("{s} // {n}");
            }
            if let Some(l) = destination.as_local() {
                self.push_shape(l, sh.clone());
                if l == Local::ZERO {
                    self.returned(sh.clone(), self.conds_of(bb));
                }
            }
        }
        if self.sdk {
            self.sdk_call(&f, args, destination, shape.as_deref())?;
        } else {
            self.line(s);
        }
        // A helper that uses a parameter as a storage key: the access is the
        // caller's, with the caller's key.
        let param_accesses = self.prev.param_accesses.get(&f).cloned().unwrap_or_default();
        for (i, op, dur) in param_accesses {
            if let Some(arg) = args.get(i) {
                let key = self.key_shape(&arg.node)?;
                self.inter.borrow_mut().schema.push((dur, key, op, format!("{} via {}", self.display(&self.fname), self.display(&f))));
            }
        }
        // A storage access: durability, the key as the contract knows it.
        let (key_i, dur_i) = match f.as_str() {
            "put_contract_data" => (0, 2),
            "get_contract_data" | "has_contract_data" | "del_contract_data" | "extend_contract_data_ttl" => (0, 1),
            _ => return Ok(()),
        };
        let key = self.key_shape(&args[key_i].node)?;
        let dur = a.get(dur_i).map(|d| d.trim_start_matches("StorageType::").to_lowercase()).unwrap_or_else(|| "?".into());
        let op = match f.as_str() {
            "put_contract_data" => format!("put({})", self.key_shape(&args[1].node)?),
            "extend_contract_data_ttl" => "extend_ttl".into(),
            other => other.trim_end_matches("_contract_data").to_string(),
        };
        // A key that is one of our parameters is really the caller's key.
        let param_key = match &args[key_i].node {
            Operand::Copy(p) | Operand::Move(p) => p.as_local().filter(|l| l.as_usize() >= 1 && l.as_usize() <= self.body.arg_count),
            _ => None,
        };
        if let Some(l) = param_key {
            self.inter.borrow_mut().param_accesses.entry(self.fname.clone()).or_default().push((l.as_usize() - 1, op.clone(), dur.clone()));
            if self.final_pass && self.prev.called.contains(&self.fname) {
                return Ok(()); // reported at the callers
            }
        }
        self.inter.borrow_mut().schema.push((dur, key, op, self.display(&self.fname)));
        Ok(())
    }

    /// `Symbol(@Val::u32(1048727u64 as u32), Val::u32(7u64 as u32))`: a
    /// position and length a caller supplied through a helper. The text is
    /// read from the data, when the data is there.
    fn resolve_text(&self, shape: String) -> String {
        let mut s = shape;
        while let Some(i) = s.find("(@") {
            let Some(end) = s[i..].find("))") else { break };
            let inner = &s[i + 2..i + end + 1];
            let mut nums = inner.split("Val::u32(").skip(1).map(|r| r.chars().take_while(|c| c.is_ascii_digit()).collect::<String>().parse::<u64>().ok());
            let (pos, len) = (nums.next().flatten(), nums.next().flatten());
            let text = match (pos, len) {
                (Some(p), Some(l)) => self.spec.text_at(p, l).or_else(|| self.spec.strings.get(&p).cloned()),
                (Some(p), None) => self.spec.strings.get(&p).cloned(),
                _ => None,
            };
            let repl = match text {
                Some(t) => match self.spec.union_case(&t) {
                    Some(case) => format!("({t:?}) /* {case} */"),
                    None => format!("({t:?})"),
                },
                None => format!("(at {inner})"),
            };
            s.replace_range(i..i + end + 2, &repl);
        }
        s
    }

    /// Every shape a local may hold, as one string. A local folded into its
    /// use never passed through `stmt`: if it is a word read through a
    /// pointer parameter, that is its shape.
    fn shape_of(&self, l: Local) -> Option<String> {
        self.shapes.get(&l).map(|v| alternatives(v.iter().map(|(_, s)| s.clone()).collect())).or_else(|| {
            let (p, off) = match self.def_of(&Operand::Copy(Place::from(l)))? {
                Rvalue::Use(o) => self.param_load(o)?,
                _ => return None,
            };
            Some(format!("{}@{off}", self.local(p)))
        })
    }

    /// A local takes on a shape on one more path: under the arms of the block being emitted.
    fn push_shape(&mut self, l: Local, shape: String) {
        let conds = self.conds_of(self.cur_bb);
        let v = self.shapes.entry(l).or_default();
        if !v.iter().any(|(c, s)| *s == shape && *c == conds) {
            v.push((conds, shape));
        }
    }

    /// Record what this function returns, for its callers: in terms of its
    /// parameters and the words it read through them; its own locals mean
    /// nothing there and become `_`.
    fn returned(&self, shape: String, conds: Vec<Cond>) {
        let params = self.param_names();
        // Not the locals named after map keys: in a shape that word is the key.
        let locals: Vec<String> = (self.body.arg_count + 1..self.body.local_decls.len())
            .map(|i| self.local(Local::from_usize(i)))
            .filter(|n| !self.spec.keys.values().any(|ks| ks.contains(n)))
            .collect();
        let shape = substitute(&shape, &locals, &vec!["_".to_string(); locals.len()]).replace("Val(_)", "_");
        let mut inter = self.inter.borrow_mut();
        let v = inter.ret_shapes.entry(self.fname.clone()).or_default();
        if !v.iter().any(|(s, _, c)| *s == shape && *c == conds) {
            v.push((shape, params, conds));
        }
    }

    /// The lifted or host function a call is to.
    fn callee_name(&self, func: &Operand<'tcx>) -> Option<String> {
        let Operand::Constant(c) = func else { return None };
        let ty::FnDef(d, _) = c.const_.ty().kind() else { return None };
        Some(self.tcx.item_name(*d).to_string())
    }

    /// Does a call's callee write through its `j`th argument, and how far
    /// past it? None: it does not. Some(None): it does, unboundedly. A host
    /// function writes when it copies to linear memory; a lifted one as its
    /// summary says, or unboundedly before there is one.
    fn write_extent(&self, func: &Operand<'tcx>, j: usize) -> Option<Option<u64>> {
        let Operand::Constant(c) = func else { return Some(None) };
        let ty::FnDef(d, _) = c.const_.ty().kind() else { return Some(None) };
        let name = self.tcx.item_name(*d).to_string();
        if self.tcx.is_foreign_item(*d) {
            return name.contains("to_linear_memory").then_some(None);
        }
        match self.prev.param_writes.get(&name) {
            Some(ps) => ps.iter().find(|(i, _)| *i == j).map(|(_, e)| *e),
            None => Some(None),
        }
    }

    /// This function writes `end` bytes past `ptr`, or unboundedly (None).
    /// Through a parameter plus a constant, the extent is known; through
    /// anything else that may come from a parameter, it is not.
    fn wrote_through(&self, ptr: &Operand<'tcx>, end: Option<u64>) {
        let hits: Vec<(usize, Option<u64>)> = match self.param_ptr(ptr, 0) {
            Some((p, off)) => vec![(p.as_usize() - 1, end.map(|e| off + e))],
            None => {
                let Some(l) = (match ptr {
                    Operand::Copy(p) | Operand::Move(p) => p.as_local(),
                    _ => None,
                }) else {
                    return;
                };
                self.body.args_iter().filter(|p| self.may_derive(*p).contains(&l)).map(|p| (p.as_usize() - 1, None)).collect()
            }
        };
        let mut inter = self.inter.borrow_mut();
        let ps = inter.param_writes.entry(self.fname.clone()).or_default();
        for (i, e) in hits {
            match ps.iter_mut().find(|(x, _)| *x == i) {
                Some((_, cur)) => *cur = cur.zip(e).map(|(a, b)| a.max(b)),
                None => ps.push((i, e)),
            }
        }
    }

    /// Every local that may be computed from `root`, through any assignment:
    /// the may-alias closure, for what is not single-definition.
    fn may_derive(&self, root: Local) -> HashSet<Local> {
        let mut set: HashSet<Local> = [root].into_iter().collect();
        loop {
            let before = set.len();
            for st in self.body.basic_blocks.iter().flat_map(|b| &b.statements) {
                let StatementKind::Assign(a) = &st.kind else { continue };
                let Some(l) = a.0.as_local() else { continue };
                let from = |o: &Operand<'tcx>| match o {
                    Operand::Copy(p) | Operand::Move(p) => set.contains(&p.local),
                    _ => false,
                };
                let derived = match &a.1 {
                    Rvalue::Use(o) | Rvalue::Cast(_, o, _) | Rvalue::UnaryOp(_, o) => from(o),
                    Rvalue::BinaryOp(_, ab) => from(&ab.0) || from(&ab.1),
                    Rvalue::Aggregate(_, fs) => fs.iter().any(from),
                    _ => false,
                };
                if derived {
                    set.insert(l);
                }
            }
            if set.len() == before {
                return set;
            }
        }
    }

    /// A function as written: its derive name when it is one, else as lifted.
    fn display(&self, f: &str) -> String {
        self.prev.renames.get(f).map(|(id, _)| id.clone()).unwrap_or_else(|| f.to_string())
    }

    /// A value the host is handed, in the contract's terms: a built vec or
    /// map by its shape, a constant decoded, a parameter by its declared type,
    /// anything else by name.
    fn key_shape(&self, o: &Operand<'tcx>) -> R<String> {
        if let Some(l) = match o {
            Operand::Copy(p) | Operand::Move(p) => p.as_local(),
            _ => None,
        } {
            if let Some(s) = self.shape_of(l) {
                return Ok(s);
            }
            if l.as_usize() >= 1 && l.as_usize() <= self.body.arg_count {
                let ty = self.spec.params.get(&self.fname).and_then(|ps| ps.get(l.as_usize() - 1));
                return Ok(match ty {
                    Some(t) => format!("{}: {t}", self.local(l)),
                    None => self.local(l),
                });
            }
            // An unresolved local is this function's; say whose.
            if !self.folded.contains_key(&l) {
                return Ok(format!("{}::{}", self.display(&self.fname), self.local(l)));
            }
        }
        self.operand(o)
    }

    // ---- source level ----------------------------------------------------

    /// An assignment in SDK terms. A store into a frame and pure plumbing
    /// say nothing: the shapes carry them. A value bound for the return is
    /// wrapped as the spec's return type wants. A Val assigned or read more
    /// than once is bound to its name.
    fn sdk_stmt(&mut self, pl: &Place<'tcx>, rv: &Rvalue<'tcx>) -> R<()> {
        let Some(dst) = pl.as_local() else { return Ok(()) };
        // A constant written to a payload local is the Val it encodes.
        let value = |me: &Self| -> R<String> {
            match rv {
                Rvalue::Use(Operand::Constant(c)) if me.payloads.contains(&dst) => match c.const_.try_to_scalar_int() {
                    Some(i) => me.sdk_value(&me.val_str(i.to_bits(i.size()) as u64)),
                    None => me.sdk_rvalue(rv),
                },
                _ => me.sdk_rvalue(rv),
            }
        };
        if dst == Local::ZERO || self.ret_locals.contains(&dst) {
            let from_ret = ret_source(self.env, rv).is_some_and(|l| self.ret_locals.contains(&l));
            let e = value(self)?;
            let e = if from_ret { e } else { self.wrap_ret(e) };
            return Ok(self.sdk_bind(dst, e));
        }
        let is_val = self.body.local_decls[dst].ty == self.env.val || self.payloads.contains(&dst);
        let (defs, uses) = (self.defs.get(&dst).copied().unwrap_or(0), self.live_uses(dst));
        if is_val && uses > 0 && (defs > 1 || uses > 1) {
            let e = value(self)?;
            let n = self.sdk_name(dst);
            self.line(format!("{n} = {e};"));
            self.declared.insert(dst);
        }
        Ok(())
    }

    /// A value for a return-bound local: the return expression itself when
    /// `_0` is assigned right before every `return`, else a named binding.
    fn sdk_bind(&mut self, dst: Local, e: String) {
        if dst == Local::ZERO && self.ret_inline {
            self.ret_expr = Some(e);
        } else {
            let n = self.sdk_name(dst);
            self.line(format!("{n} = {e};"));
            self.declared.insert(dst);
        }
    }

    /// Uses of `l` by statements that matter: a pure statement nothing reads
    /// is rustc's debuginfo, not a use.
    fn live_uses(&self, l: Local) -> usize {
        let mut n = self.uses.get(&l).copied().unwrap_or(0);
        for (bb, data) in self.body.basic_blocks.iter_enumerated() {
            for (si, st) in data.statements.iter().enumerate() {
                if let StatementKind::Assign(a) = &st.kind {
                    if pure(&a.1) && a.0.as_local().is_some_and(|d| self.uses.get(&d).copied().unwrap_or(0) == 0) && mentions(self.body, bb, si).contains(&l) {
                        n = n.saturating_sub(1);
                    }
                }
            }
        }
        n
    }

    fn sdk_name(&self, l: Local) -> String {
        let n = self.raw_name(l);
        if l == Local::ZERO && n == "_0" { "ret".into() } else { n }
    }

    fn sdk_arg(&self, args: &[Spanned<Operand<'tcx>>], i: usize) -> R<String> {
        self.sdk_operand(&args.get(i).ok_or("missing argument")?.node)
    }

    fn sdk_dur(&self, args: &[Spanned<Operand<'tcx>>], i: usize) -> R<&'static str> {
        match args.get(i).and_then(|a| self.konst_u64(&a.node)) {
            Some(0) => Ok("temporary"),
            Some(1) => Ok("persistent"),
            Some(2) => Ok("instance"),
            _ => Err("durability is not a constant".into()),
        }
    }

    /// A call in SDK terms: storage, auth, events and ledger reads as the
    /// `Env` methods they are; a constructor or derive by the shape it
    /// builds; a panic wrapper by its error. A result read once is inlined
    /// at its use, read more it is bound to its name.
    fn sdk_call(&mut self, f: &str, args: &[Spanned<Operand<'tcx>>], destination: &Place<'tcx>, shape: Option<&str>) -> R<()> {
        let mut expr: Option<String> = None;
        let line = match f {
            "put_contract_data" => Some(format!("env.storage().{}().set(&{}, &{});", self.sdk_dur(args, 2)?, self.sdk_arg(args, 0)?, self.sdk_arg(args, 1)?)),
            "del_contract_data" => Some(format!("env.storage().{}().remove(&{});", self.sdk_dur(args, 1)?, self.sdk_arg(args, 0)?)),
            "extend_contract_data_ttl" => Some(format!(
                "env.storage().{}().extend_ttl(&{}, {}, {});",
                self.sdk_dur(args, 1)?,
                self.sdk_arg(args, 0)?,
                self.sdk_arg(args, 2)?,
                self.sdk_arg(args, 3)?
            )),
            "extend_current_contract_instance_and_code_ttl" => Some(format!("env.storage().instance().extend_ttl({}, {});", self.sdk_arg(args, 0)?, self.sdk_arg(args, 1)?)),
            "require_auth" => Some(format!("{}.require_auth();", self.sdk_arg(args, 0)?)),
            "fail_with_error" => Some(format!("panic_with_error!(&env, {});", self.sdk_arg(args, 0)?)),
            "trap" => Some("panic!();".to_string()),
            "contract_event" => {
                let topics = self.sdk_value(&self.key_shape(&args[0].node)?)?;
                let topics = topics.strip_prefix("vec![&env, ").and_then(|t| t.strip_suffix(']')).map(|t| format!("({t},)")).ok_or("event topics")?;
                Some(format!("env.events().publish({topics}, {});", self.sdk_arg(args, 1)?))
            }
            "has_contract_data" => {
                expr = Some(format!("env.storage().{}().has(&{})", self.sdk_dur(args, 1)?, self.sdk_arg(args, 0)?));
                None
            }
            "get_contract_data" => {
                expr = Some(format!("env.storage().{}().get(&{}).unwrap()", self.sdk_dur(args, 1)?, self.sdk_arg(args, 0)?));
                None
            }
            "get_current_contract_address" => {
                expr = Some("env.current_contract_address()".into());
                None
            }
            "get_ledger_timestamp" => {
                expr = Some("env.ledger().timestamp()".into());
                None
            }
            "get_ledger_sequence" => {
                expr = Some("env.ledger().sequence()".into());
                None
            }
            _ if self.prev.fails.contains_key(f) => Some(format!("panic_with_error!(&env, {});", self.sdk_value(&self.prev.fails[f])?)),
            _ if self.prev.diverges.contains(f) => Some("panic!();".to_string()),
            _ => match shape.map(|sh| self.sdk_value(sh)) {
                Some(Ok(e)) => {
                    expr = Some(e);
                    None
                }
                _ => return Err(format!("call to {}", self.display(f))),
            },
        };
        if let Some(l) = line {
            self.line(l);
        }
        let (Some(e), Some(l)) = (expr, destination.as_local()) else { return Ok(()) };
        let (defs, uses) = (self.defs.get(&l).copied().unwrap_or(0), self.live_uses(l));
        if l == Local::ZERO || self.ret_locals.contains(&l) {
            let e = self.wrap_ret(e);
            self.sdk_bind(l, e);
        } else if uses == 1 && defs <= 1 {
            // ponytail: a storage read inlined at its one use; a write in between would reorder it. Not seen.
            self.inlined.insert(l, e);
        } else if uses > 0 {
            let n = self.sdk_name(l);
            self.line(format!("{n} = {e};"));
            self.declared.insert(l);
        }
        Ok(())
    }

    /// A branch in SDK terms. On a bool, or a bool the host returned: `if`.
    /// On an integer enum parameter: `match` over its cases. On anything the
    /// source never saw -- a tag check, a payload bound -- a guard: the one
    /// arm that goes on is the code, the arms that trap are the SDK's.
    fn sdk_switch(&mut self, bb: BasicBlock, discr: &Operand<'tcx>, targets: &SwitchTargets, tail: Option<BasicBlock>) -> R<()> {
        let is_bool = discr.ty(&self.body.local_decls, self.tcx).is_bool();
        let cond = if is_bool {
            self.sdk_operand(discr).ok()
        } else {
            self.bool_val(discr).and_then(|l| self.sdk_operand(&Operand::Copy(Place::from(l))).ok())
        };
        if let Some(c) = cond {
            let (mut then, mut els) = (targets.otherwise(), targets.otherwise());
            for (v, t) in targets.iter() {
                if v == 0 {
                    els = t
                } else {
                    then = t
                }
            }
            let then_lines = self.capture(|s| s.branch(bb, then, tail))?;
            let else_lines = self.capture(|s| s.branch(bb, els, tail))?;
            let c = strip_parens(c);
            match (then_lines.is_empty(), else_lines.is_empty()) {
                (true, true) => {}
                (false, true) => self.arm(format!("if {c}"), then_lines),
                (true, false) => self.arm(format!("if !{c}"), else_lines),
                (false, false) => {
                    self.arm(format!("if {c}"), then_lines);
                    let n = self.out.len();
                    self.out[n - 1].1 = "} else {".into();
                    self.out.extend(else_lines);
                    self.line("}");
                }
            }
            return Ok(());
        }
        let tail_dead = tail.is_some_and(|t| self.diverges_at(t, 0));
        let dead = |lines: &[(usize, String)]| lines.iter().all(|(_, l)| is_diverging(l)) && (!lines.is_empty() || tail_dead);
        if let Some((p, e)) = self.enum_param(discr) {
            self.line(format!("match {} {{", self.local(p)));
            self.depth += 1;
            let mut seen: Vec<String> = Vec::new();
            for (v, t) in targets.iter() {
                let lines = self.capture(|s| s.branch(bb, t, tail))?;
                let case = self.spec.enum_case(&e, v as u64).ok_or(format!("{e} has no case {v}"))?.to_string();
                seen.push(case.clone());
                self.arm(format!("{e}::{case} =>"), lines);
            }
            let lines = self.capture(|s| s.branch(bb, targets.otherwise(), tail))?;
            let rest: Vec<String> = self.spec.enums.get(&e).map(|cs| cs.iter().filter(|(c, _)| !seen.contains(c)).map(|(c, _)| c.clone()).collect()).unwrap_or_default();
            match rest.as_slice() {
                [] if dead(&lines) => {} // exhaustive; the trap for a value outside the enum is the SDK's
                [one] => self.arm(format!("{e}::{one} =>"), lines),
                _ => self.arm("_ =>".into(), lines),
            }
            self.depth -= 1;
            self.line("}");
            return Ok(());
        }
        let mut arms: Vec<Vec<(usize, String)>> = Vec::new();
        for (_, t) in targets.iter() {
            arms.push(self.capture(|s| s.branch(bb, t, tail))?);
        }
        arms.push(self.capture(|s| s.branch(bb, targets.otherwise(), tail))?);
        let mut live: Vec<Vec<(usize, String)>> = arms.into_iter().filter(|a| !dead(a)).collect();
        match live.len() {
            0 => self.line("panic!();"),
            1 => {
                // The guard's one live arm, at this depth.
                let mut lines = live.pop().unwrap_or_default();
                let min = lines.iter().map(|(d, _)| *d).min().unwrap_or(self.depth);
                for l in &mut lines {
                    l.0 = l.0 - min + self.depth;
                }
                self.out.extend(lines);
            }
            _ => return Err(format!("branch on {}", self.operand(discr).unwrap_or_default())),
        }
        Ok(())
    }

    /// Does control reaching `bb` never return? A trap, an unreachable, a
    /// call that never returns, or a straight path to one.
    fn diverges_at(&self, bb: BasicBlock, depth: u8) -> bool {
        if depth > 6 {
            return false;
        }
        match &self.body.basic_blocks[bb].terminator().kind {
            TerminatorKind::Unreachable => true,
            TerminatorKind::Goto { target } => self.diverges_at(*target, depth + 1),
            TerminatorKind::Call { func, target, .. } => {
                let name = self.callee_name(func).unwrap_or_default();
                target.is_none() || name == "trap" || self.prev.diverges.contains(&name) || self.prev.fails.contains_key(&name) || target.is_some_and(|t| self.diverges_at(t, depth + 1))
            }
            _ => false,
        }
    }

    /// The bool Val the host returned that this payload is: `has_contract_data`.
    fn bool_val(&self, o: &Operand<'tcx>) -> Option<Local> {
        let l = self.val_source(o)?;
        (self.call_def.get(&l)?.0 == "has_contract_data").then_some(l)
    }

    /// `(param.0 >> 32) as uN` of a parameter declared as an integer enum:
    /// the parameter and its enum.
    fn enum_param(&self, o: &Operand<'tcx>) -> Option<(Local, String)> {
        match self.def_of(o)? {
            Rvalue::Cast(CastKind::IntToInt, inner, _) | Rvalue::Use(inner) => self.enum_param(inner),
            Rvalue::BinaryOp(BinOp::Shr, xy) if self.konst_u64(&xy.1) == Some(32) => {
                let i = self.payload_of_param(&xy.0)?;
                let e = self.spec.param_enum(&self.fname, i)?;
                Some((Local::from_usize(i + 1), e.to_string()))
            }
            _ => None,
        }
    }

    /// An operand as the source wrote it: a parameter by name (cloned when
    /// its type is not Copy), a constant decoded, a bound name, an inlined
    /// result, a shape; else what it was defined as.
    fn sdk_operand(&self, o: &Operand<'tcx>) -> R<String> {
        if let Operand::Constant(c) = o {
            if c.const_.ty() == self.env.val {
                if let Some(i) = c.const_.try_to_scalar_int() {
                    return self.sdk_value(&self.val_str(i.to_bits(i.size()) as u64));
                }
            }
            return self.operand(o);
        }
        let (Operand::Copy(p) | Operand::Move(p)) = o else { return Err("operand".into()) };
        if let Some(i) = self.payload_of_param(o) {
            return Ok(self.param_expr(Local::from_usize(i + 1)));
        }
        let Some(l) = p.as_local() else { return Err(format!("not reconstructed: {}", self.place(p))) };
        if (1..=self.body.arg_count).contains(&l.as_usize()) {
            return Ok(self.param_expr(l));
        }
        if self.declared.contains(&l) {
            return Ok(self.sdk_name(l));
        }
        if let Some(e) = self.inlined.get(&l) {
            return Ok(e.clone());
        }
        if let Some(sh) = self.shape_of(l) {
            return self.sdk_value(&sh);
        }
        if let Some(src) = self.val_source(o).filter(|s| *s != l) {
            return self.sdk_operand(&Operand::Copy(Place::from(src)));
        }
        if let Some(rv) = self.def_of(o) {
            return self.sdk_rvalue(rv);
        }
        Err(format!("not reconstructed: {}", self.local(l)))
    }

    fn sdk_rvalue(&self, rv: &Rvalue<'tcx>) -> R<String> {
        match rv {
            Rvalue::Use(o) => self.sdk_operand(o),
            Rvalue::Aggregate(k, fs) if matches!(**k, AggregateKind::Adt(d, ..) if d == self.env.val_def) => {
                let o = fs.iter().next().ok_or("Val without a payload")?;
                // `Val((b.0 == 1) as u64)`: a bool re-encoded is the bool.
                if let Some(Rvalue::Cast(_, inner, _)) = self.def_of(o) {
                    if let Some(Rvalue::BinaryOp(BinOp::Eq, ab)) = self.def_of(inner) {
                        if self.konst_u64(&ab.1) == Some(1) {
                            if let Some(src) = self.val_source(&ab.0) {
                                return self.sdk_operand(&Operand::Copy(Place::from(src)));
                            }
                        }
                    }
                }
                self.sdk_operand(o)
            }
            _ => Err(format!("not reconstructed: {}", self.rvalue(rv)?)),
        }
    }

    /// A parameter as an expression: `.clone()` unless its type is Copy.
    fn param_expr(&self, l: Local) -> String {
        let n = self.local(l);
        if self.copy_param(&n) { n } else { format!("{n}.clone()") }
    }

    fn copy_param(&self, name: &str) -> bool {
        let Some(i) = self.body.args_iter().position(|l| self.local(l) == name) else { return true };
        let ty = self.spec.params.get(&self.fname).and_then(|ps| ps.get(i)).map(String::as_str).unwrap_or("Val");
        matches!(ty, "bool" | "u32" | "i32" | "u64" | "i64" | "u128" | "i128" | "Val") || self.spec.enums.contains_key(ty)
    }

    /// The return value as the spec's return type wants it: `Ok`/`Err` for a
    /// `Result`, `Some`/`None` for an `Option`, nothing for `()`.
    fn wrap_ret(&self, e: String) -> String {
        let ret = self.spec.sigs.get(&self.fname).and_then(|s| s.split_once(" -> ")).map(|(_, r)| r.trim()).unwrap_or("()");
        if ret.starts_with("Result<") {
            if self.spec.errors.iter().any(|(en, case, _)| e == format!("{en}::{case}")) {
                format!("Err({e})")
            } else {
                format!("Ok({e})")
            }
        } else if ret.starts_with("Option<") {
            if e == "()" { "None".into() } else { format!("Some({e})") }
        } else if ret == "()" {
            String::new()
        } else {
            e
        }
    }

    /// A shape or decoded constant as the source wrote it: `symbol_short!`,
    /// `Symbol::new`, the error and union cases by name, struct literals with
    /// their fields, parameters cloned. Anything not fully known is an error.
    fn sdk_value(&self, s: &str) -> R<String> {
        let own = format!("{}::", self.display(&self.fname));
        let hole = s.split(|c: char| !c.is_alphanumeric() && c != '_').any(|w| w == "_");
        if hole || s.contains("Val(") || s.contains("::{") || s.contains(" | ") || s.contains('@') || s.contains("(at ") || s.contains("Map{") || s.contains(&own) {
            return Err(format!("value not reconstructed: {s}"));
        }
        // `X /* Path */` is Path -- an error case, a unit union case; other comments go.
        let mut t = String::new();
        let mut rest = s;
        while let Some(i) = rest.find(" /* ") {
            let end = i + rest[i..].find(" */").ok_or("comment")?;
            let (head, c) = (&rest[..i], &rest[i + 4..end]);
            if c.contains("::") && !c.contains(' ') {
                t.push_str(&head[..expr_start(head)]);
                t.push_str(c);
            } else {
                t.push_str(head);
            }
            rest = &rest[end + 3..];
        }
        t.push_str(rest);
        if t.contains("Val::error(") || t.contains("Val::small(") {
            return Err(format!("value not reconstructed: {s}"));
        }
        let t = rewrite_calls(&t, "Val::sym(", &|a| format!("symbol_short!({a})"));
        let t = rewrite_calls(&t, "Val::symbol(", &|a| format!("Symbol::new(&env, {a})"));
        let t = rewrite_calls(&t, "Symbol(", &|a| format!("Symbol::new(&env, {a})"));
        let t = rewrite_calls(&t, "Val::string(", &|a| format!("String::from_str(&env, {a})"));
        let t = rewrite_calls(&t, "String(", &|a| format!("String::from_str(&env, {a})"));
        let t = rewrite_calls(&t, "Val::u32(", &|a| a.to_string());
        let t = rewrite_calls(&t, "Val::i32(", &|a| a.to_string());
        let t = t.replace("Val::TRUE", "true").replace("Val::FALSE", "false").replace("Val::VOID", "()");
        let t = rewrite_calls(&t.replace("Vec[", "Vec("), "Vec(", &|a| format!("vec![&env, {a}]"));
        let t = expand_shorthand(&t);
        Ok(self.clone_params(&t))
    }

    /// Non-Copy parameters used as values get `.clone()`: not field names,
    /// not paths, not inside string literals.
    fn clone_params(&self, s: &str) -> String {
        let b = s.as_bytes();
        let (mut out, mut i) = (String::new(), 0);
        while i < b.len() {
            let c = b[i] as char;
            if c == '"' {
                let end = s[i + 1..].find('"').map(|e| i + 1 + e).unwrap_or(b.len() - 1);
                out.push_str(&s[i..=end]);
                i = end + 1;
                continue;
            }
            if c.is_ascii_alphabetic() || c == '_' {
                let mut j = i;
                while j < b.len() && (b[j].is_ascii_alphanumeric() || b[j] == b'_') {
                    j += 1;
                }
                let word = &s[i..j];
                let key = s[j..].trim_start().starts_with(':') && !s[j..].trim_start().starts_with("::");
                let path = out.ends_with("::") || out.ends_with('.');
                let is_param = self.body.args_iter().any(|l| self.local(l) == word);
                out.push_str(word);
                if is_param && !key && !path && !self.copy_param(word) {
                    out.push_str(".clone()");
                }
                i = j;
                continue;
            }
            out.push(c);
            i += 1;
        }
        out
    }

    /// The contract function as soroban-sdk source: the spec's signature with
    /// `env: Env` first, the body from the shapes. Err names the first thing
    /// the source level could not say.
    fn emit_sdk(mut self) -> R<String> {
        self.sdk = true;
        let sig = self.spec.sigs.get(&self.fname).cloned().ok_or("no spec signature")?;
        // What flows to the return unchanged, and whether `_0` is assigned right before every return.
        let mut ret: HashSet<Local> = [Local::ZERO].into_iter().collect();
        loop {
            let n = ret.len();
            for st in self.body.basic_blocks.iter().flat_map(|b| &b.statements) {
                let StatementKind::Assign(a) = &st.kind else { continue };
                if !a.0.as_local().is_some_and(|d| ret.contains(&d)) {
                    continue;
                }
                if let Some(l) = ret_source(self.env, &a.1).filter(|l| l.as_usize() > self.body.arg_count) {
                    ret.insert(l);
                }
            }
            if ret.len() == n {
                break;
            }
        }
        self.ret_locals = ret;
        self.ret_inline = self.body.basic_blocks.iter().all(|b| {
            !b.statements.iter().any(|st| matches!(&st.kind, StatementKind::Assign(a) if a.0.as_local() == Some(Local::ZERO))) || matches!(b.terminator().kind, TerminatorKind::Return)
        });
        self.depth = 2;
        self.node(START_BLOCK, None)?;
        let mut lines = std::mem::take(&mut self.out);
        tidy(&mut lines);
        let mut s = format!("    {}\n", sdk_header(&sig)?);
        for l in self.body.vars_and_temps_iter().chain(Some(Local::ZERO)) {
            if self.declared.contains(&l) {
                s.push_str(&format!("        let mut {};\n", self.sdk_name(l)));
            }
        }
        for (depth, text) in lines {
            s.push_str(&"    ".repeat(depth));
            s.push_str(&text);
            s.push('\n');
        }
        s.push_str("    }\n");
        Ok(s)
    }

    // ---- structure -------------------------------------------------------

    fn is_merge(&self, bb: BasicBlock) -> bool {
        self.body.basic_blocks.predecessors()[bb].len() >= 2
    }

    fn is_header(&self, bb: BasicBlock) -> bool {
        let doms = self.body.basic_blocks.dominators();
        self.body.basic_blocks.predecessors()[bb].iter().any(|p| doms.dominates(bb, *p))
    }

    /// Dominator-tree children of `bb` that are merge nodes, in RPO.
    fn merges_under(&self, bb: BasicBlock) -> Vec<BasicBlock> {
        let doms = self.body.basic_blocks.dominators();
        let mut v: Vec<BasicBlock> = self
            .body
            .basic_blocks
            .indices()
            .filter(|c| *c != bb && self.rpo.contains_key(c) && doms.immediate_dominator(*c) == Some(bb) && self.is_merge(*c))
            .collect();
        v.sort_by_key(|c| self.rpo[c]);
        v
    }

    /// The natural loop of header `h`: blocks it dominates from which it is
    /// reached again.
    fn loop_of(&self, h: BasicBlock) -> HashSet<BasicBlock> {
        let doms = self.body.basic_blocks.dominators();
        let preds = self.body.basic_blocks.predecessors();
        let mut set = HashSet::from([h]);
        let mut stack: Vec<BasicBlock> = preds[h].iter().copied().filter(|p| doms.dominates(h, *p)).collect();
        while let Some(b) = stack.pop() {
            if set.insert(b) {
                stack.extend(preds[b].iter().copied().filter(|p| doms.dominates(h, *p)));
            }
        }
        set
    }

    /// Run `f` with its lines captured instead of emitted, one level deeper:
    /// they will sit inside an arm.
    fn capture(&mut self, f: impl FnOnce(&mut Self) -> R<()>) -> R<Vec<(usize, String)>> {
        let saved = std::mem::take(&mut self.out);
        self.depth += 1;
        let r = f(self);
        self.depth -= 1;
        let lines = std::mem::replace(&mut self.out, saved);
        r.map(|_| lines)
    }

    fn begin(&mut self, label: BasicBlock) -> usize {
        self.open.push(label);
        self.depth += 1;
        self.out.len()
    }

    /// Close a labelled block opened at `start`: write the label only if some
    /// jump used it; otherwise the lines just lose one level of nesting.
    fn end_block(&mut self, label: BasicBlock, start: usize) {
        self.depth -= 1;
        self.open.pop();
        if self.used.contains(&label) {
            self.out.insert(start, (self.depth, format!("'b{}: {{", label.as_usize())));
            self.line("}");
        } else {
            for l in &mut self.out[start..] {
                l.0 -= 1;
            }
        }
    }

    fn end_loop(&mut self, header: BasicBlock, start: usize) {
        self.depth -= 1;
        self.open.pop();
        let head = if self.used.contains(&header) { format!("'l{}: loop {{", header.as_usize()) } else { "loop {".into() };
        self.out.insert(start, (self.depth, head));
        self.line("}");
    }

    /// `'b_m2: { 'b_m1: { 'b_m0: { inner } node(m0) } node(m1) } node(m2)`,
    /// with tails threaded: `inner` falls through to m0, node(m_i) to m_i+1,
    /// and the last one to whatever this whole chain falls through to.
    fn chain(&mut self, merges: &[BasicBlock], tail: Option<BasicBlock>, inner: &mut dyn FnMut(&mut Self, Option<BasicBlock>) -> R<()>) -> R<()> {
        let starts: Vec<usize> = merges.iter().rev().map(|m| self.begin(*m)).collect();
        inner(self, merges.first().copied().or(tail))?;
        for (i, m) in merges.iter().enumerate() {
            self.end_block(*m, starts[merges.len() - 1 - i]);
            self.node(*m, merges.get(i + 1).copied().or(tail))?;
        }
        Ok(())
    }

    /// Emit `bb` and everything it dominates. `tail` is the block that
    /// execution reaches by falling off the end of what is being emitted.
    fn node(&mut self, bb: BasicBlock, tail: Option<BasicBlock>) -> R<()> {
        let merges = self.merges_under(bb);
        if !self.is_header(bb) {
            return self.chain(&merges, tail, &mut |s, t| s.code(bb, t));
        }
        // A loop: merge nodes in its body live inside the `loop`, exits after
        // it. Falling off the end of the body is the back edge.
        let body = self.loop_of(bb);
        let (inside, exits): (Vec<_>, Vec<_>) = merges.into_iter().partition(|m| body.contains(m));
        self.chain(&exits, tail, &mut |s, _| {
            let start = s.begin(bb);
            s.chain(&inside, Some(bb), &mut |s, t| s.code(bb, t))?;
            s.end_loop(bb, start);
            Ok(())
        })
    }

    /// The code for a jump from `from` to `to`.
    fn branch(&mut self, from: BasicBlock, to: BasicBlock, tail: Option<BasicBlock>) -> R<()> {
        if Some(to) == tail {
            return Ok(()); // falls through
        }
        let doms = self.body.basic_blocks.dominators();
        let (kind, label) = if self.is_header(to) && doms.dominates(to, from) {
            ("continue 'l", to)
        } else if self.is_merge(to) {
            ("break 'b", to)
        } else {
            return self.node(to, tail);
        };
        if !self.open.contains(&label) {
            return Err(format!("bb{} is jumped to from outside its region: irreducible control flow", label.as_usize()));
        }
        self.used.insert(label);
        self.line(format!("{kind}{};", label.as_usize()));
        Ok(())
    }

    fn arm(&mut self, head: String, lines: Vec<(usize, String)>) {
        if lines.is_empty() {
            self.line(format!("{head} {{}}"));
            return;
        }
        self.line(format!("{head} {{"));
        self.out.extend(lines);
        self.line("}");
    }

    /// Statements and terminator of one block.
    fn code(&mut self, bb: BasicBlock, tail: Option<BasicBlock>) -> R<()> {
        self.stmts(bb)?;
        let data = &self.body.basic_blocks[bb];
        let Some(t) = &data.terminator else { return Err("block without terminator".into()) };
        match &t.kind {
            TerminatorKind::Goto { target } => self.branch(bb, *target, tail)?,
            TerminatorKind::Return => {
                let s = if self.sdk {
                    let e = if self.ret_inline { self.ret_expr.take().unwrap_or_default() } else { self.sdk_name(Local::ZERO) };
                    if e.is_empty() || self.body.local_decls[Local::ZERO].ty.is_unit() { "return;".to_string() } else { format!("return {e};") }
                } else if self.body.local_decls[Local::ZERO].ty.is_unit() {
                    "return;".to_string()
                } else {
                    format!("return {};", self.local(Local::ZERO))
                };
                self.line(s);
            }
            TerminatorKind::Unreachable => self.line("unreachable!();"),
            TerminatorKind::Call { func, args, destination, target, .. } => {
                self.call_line(bb, func, args, destination)?;
                if let Some(t) = target {
                    self.branch(bb, *t, tail)?;
                }
            }
            TerminatorKind::SwitchInt { discr, targets } if self.sdk => self.sdk_switch(bb, discr, targets, tail)?,
            TerminatorKind::SwitchInt { discr, targets } => {
                let d = strip_parens(self.operand(discr)?);
                if discr.ty(&self.body.local_decls, self.tcx).is_bool() {
                    let mut then = targets.otherwise();
                    let mut els = targets.otherwise();
                    for (v, t) in targets.iter() {
                        if v == 0 { els = t } else { then = t }
                    }
                    let then_lines = self.capture(|s| s.branch(bb, then, tail))?;
                    let else_lines = self.capture(|s| s.branch(bb, els, tail))?;
                    match (then_lines.is_empty(), else_lines.is_empty()) {
                        (true, true) => {}
                        (false, true) => self.arm(format!("if {d}"), then_lines),
                        (true, false) => self.arm(format!("if !{d}"), else_lines),
                        (false, false) => {
                            self.arm(format!("if {d}"), then_lines);
                            let n = self.out.len();
                            self.out[n - 1].1 = "} else {".into();
                            self.out.extend(else_lines);
                            self.line("}");
                        }
                    }
                } else {
                    self.line(format!("match {d} {{"));
                    self.depth += 1;
                    let tag = self.is_tag(discr);
                    let en = self.enum_of(discr).map(str::to_string);
                    for (v, t) in targets.iter() {
                        let lines = self.capture(|s| s.branch(bb, t, tail))?;
                        let pat = match (tag_name(v as u64), &en) {
                            (Some(n), _) if tag => format!("Tag::{n}"),
                            (_, Some(e)) => match self.spec.enum_case(e, v as u64) {
                                Some(c) => format!("{v} /* {e}::{c} */"),
                                None => v.to_string(),
                            },
                            _ => v.to_string(),
                        };
                        self.arm(format!("{pat} =>"), lines);
                    }
                    let lines = self.capture(|s| s.branch(bb, targets.otherwise(), tail))?;
                    self.arm("_ =>".into(), lines);
                    self.depth -= 1;
                    self.line("}");
                }
            }
            other => return Err(format!("terminator {other:?}")),
        }
        Ok(())
    }

    /// The fallback for a CFG the structurer cannot place: one arm per block,
    /// dispatch on `__bb`. Faithful, and valid Rust; just not pretty.
    fn state_machine(&mut self) -> R<()> {
        self.line("let mut __bb: usize = 0;");
        self.line("loop {");
        self.depth += 1;
        self.line("match __bb {");
        self.depth += 1;
        for bb in self.body.basic_blocks.reverse_postorder() {
            self.line(format!("{} => {{", bb.as_usize()));
            self.depth += 1;
            self.stmts(*bb)?;
            let data = &self.body.basic_blocks[*bb];
            let goto = |t: BasicBlock| format!("__bb = {}; continue;", t.as_usize());
            match &data.terminator.as_ref().ok_or("block without terminator")?.kind {
                TerminatorKind::Goto { target } => self.line(goto(*target)),
                TerminatorKind::Return => {
                    let s = if self.body.local_decls[Local::ZERO].ty.is_unit() { "return;".to_string() } else { format!("return {};", self.local(Local::ZERO)) };
                self.line(s);
                }
                TerminatorKind::Unreachable => self.line("unreachable!();"),
                TerminatorKind::Call { func, args, destination, target, .. } => {
                    self.call_line(*bb, func, args, destination)?;
                    if let Some(t) = target {
                        self.line(goto(*t));
                    }
                }
                TerminatorKind::SwitchInt { discr, targets } => {
                    let is_bool = discr.ty(&self.body.local_decls, self.tcx).is_bool();
                    self.line(format!("match {} {{", self.operand(discr)?));
                    for (v, t) in targets.iter() {
                        let pat = if is_bool { (v != 0).to_string() } else { v.to_string() };
                        self.line(format!("    {pat} => {{ __bb = {}; }}", t.as_usize()));
                    }
                    self.line(format!("    _ => {{ __bb = {}; }}", targets.otherwise().as_usize()));
                    self.line("}");
                    self.line("continue;");
                }
                other => return Err(format!("terminator {other:?}")),
            }
            self.depth -= 1;
            self.line("}");
        }
        self.line("_ => unreachable!(),");
        self.depth -= 1;
        self.line("}");
        self.depth -= 1;
        self.line("}");
        Ok(())
    }

    fn emit(mut self) -> R<String> {
        self.inter.borrow_mut().param_writes.entry(self.fname.clone()).or_default();
        let tcx = self.tcx;
        let def_id = self.body.source.def_id();
        let name = self.display(&self.fname);
        let vis = if tcx.visibility(def_id).is_public() { "pub " } else { "" };
        // `mut`: rustc's copy propagation may reuse an argument local.
        let mut params: Vec<String> =
            self.body.args_iter().map(|l| format!("mut {}: {}", self.local(l), ty_str(tcx, self.body.local_decls[l].ty))).collect();
        // The SDK's text constructor: its position and length are one `&str`.
        let mut prologue = String::new();
        // What the derive recognition or the fingerprints say this is, else what its shape says.
        let mut doc = self
            .prev
            .renames
            .get(&self.fname)
            .map(|(_, d)| d.clone())
            .or_else(|| self.spec.sdk.get(&self.fname).map(|n| format!("/// {n}\n")))
            .unwrap_or_default();
        if let Some(&(i, j, kind)) = self.prev.text_helpers.get(&self.fname) {
            let ty = |l: Local| ty_str(tcx, self.body.local_decls[l].ty);
            let (pi, pj) = (Local::from_usize(i + 1), Local::from_usize(j + 1));
            let ptr = if ty(pi).starts_with('*') { format!("s.as_ptr() as {}", ty(pi)) } else { format!("s.as_ptr() as usize as {}", ty(pi)) };
            prologue = format!("        let mut {}: {} = {ptr};\n        let mut {}: {} = s.len() as {};\n", self.local(pi), ty(pi), self.local(pj), ty(pj), ty(pj));
            if doc.is_empty() {
                doc = format!("/// The SDK's `{}`.\n", if kind == "Symbol" { "Symbol::new" } else { "String::from_str" });
            }
            params[i] = "s: &str".into();
            params.remove(j);
        }
        let ret_ty = self.body.local_decls[Local::ZERO].ty;
        let ret = if ret_ty.is_unit() { String::new() } else { format!(" -> {}", ty_str(tcx, ret_ty)) };

        // Structured when the CFG is reducible; a state machine otherwise. The
        // state machine hides the flow from rustc's definite-initialisation
        // check, so there the locals start zeroed; MIR still writes each
        // before any read.
        self.depth = 2;
        let mut zeroed = false;
        if let Err(e) = self.node(START_BLOCK, None) {
            self.out.clear();
            self.used.clear();
            self.open.clear();
            self.folded.clear();
            self.line(format!("// {e}; emitted as a state machine."));
            self.state_machine()?;
            zeroed = true;
        }
        let code = std::mem::take(&mut self.out);

        // The declared signature, from contractspecv0, above the ABI one.
        doc.push_str(&self.spec.sigs.get(&self.fname).map(|sig| format!("/// spec: {sig}\n")).unwrap_or_default());
        let mut s = format!("{doc}{vis}fn {name}({}){ret} {{\n    unsafe {{\n{prologue}", params.join(", "));
        let init = if zeroed { " = core::mem::zeroed()" } else { "" };
        for l in self.body.vars_and_temps_iter().chain((!ret_ty.is_unit()).then_some(Local::ZERO)) {
            let t = self.body.local_decls[l].ty;
            if t.is_unit() || t.is_never() || self.folded.contains_key(&l) || self.literal.contains(&l) || self.addr_locals.contains(&l) {
                continue; // nothing to hold, or written into its one use
            }
            let uses = self.uses.get(&l).copied().unwrap_or(0);
            let dead = uses == 0 && self.body.basic_blocks.iter().flat_map(|b| &b.statements).all(|st| match &st.kind {
                StatementKind::Assign(a) => a.0.as_local() != Some(l) || pure(&a.1),
                _ => true,
            });
            if dead && l != Local::ZERO {
                continue; // every definition was skipped as unread
            }
            s.push_str(&format!("        let mut {}: {}{init};\n", self.raw_name(l), self.local_ty(l)));
        }
        for (depth, text) in code {
            s.push_str(&"    ".repeat(depth));
            s.push_str(&text);
            s.push('\n');
        }
        s.push_str("    }\n}\n");
        Ok(s)
    }
}
