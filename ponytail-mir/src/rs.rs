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
use std::collections::{HashMap, HashSet};

use rustc_middle::mir::interpret::{GlobalAlloc, Scalar};
use rustc_middle::mir::*;
use rustc_middle::ty::{self, Ty, TyCtxt};
use rustc_span::Spanned;

use crate::mir::Env;

type R<T> = Result<T, String>;

pub fn emit<'tcx>(tcx: TyCtxt<'tcx>, env: &Env<'tcx>, header: &str, bodies: &[&Body<'tcx>], spec: &Spec) -> R<String> {
    let mut out = String::from(header);
    for body in bodies {
        out.push('\n');
        out.push_str(&Fn_::new(tcx, env, body, spec).emit()?);
    }
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
    pub fn parse(lines: Vec<String>) -> Spec {
        let mut s = Spec::default();
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
                let inner = rest.find('(').map(|i| &rest[i + 1..rest.rfind(')').unwrap_or(rest.len())]).unwrap_or("");
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
            }
        }
        s
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
    /// Vals from (`vec_new_from_linear_memory`, the values of `map_new_..`):
    /// their slots hold Vals, so a constant stored into one is decoded.
    val_arrays: HashSet<Local>,
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
    fn new(tcx: TyCtxt<'tcx>, env: &'a Env<'tcx>, body: &'a Body<'tcx>, spec: &'a Spec) -> Self {
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
            val_arrays: HashSet::new(),
            folded: HashMap::new(),
            out: Vec::new(),
            depth: 0,
            open: Vec::new(),
            used: HashSet::new(),
        };
        me.val_arrays = me.find_val_arrays();
        me
    }

    /// Arrays handed to the host at a Val-reading position. The position is
    /// `Val::u32(frame as u32)`: walk that back to the `&raw mut` it came from.
    fn find_val_arrays(&self) -> HashSet<Local> {
        let mut set = HashSet::new();
        for bb in self.body.basic_blocks.iter() {
            let Some(Terminator { kind: TerminatorKind::Call { func, args, .. }, .. }) = &bb.terminator else { continue };
            let Some(Operand::Constant(c)) = Some(func) else { continue };
            let ty::FnDef(d, _) = c.const_.ty().kind() else { continue };
            let pos = match self.tcx.item_name(*d).as_str() {
                "vec_new_from_linear_memory" => 0,
                "map_new_from_linear_memory" | "map_unpack_to_linear_memory" => match self.tcx.item_name(*d).as_str() {
                    "map_new_from_linear_memory" => 1,
                    _ => 2,
                },
                "vec_unpack_to_linear_memory" => 1,
                _ => continue,
            };
            let Some(arg) = args.get(pos) else { continue };
            if let Some(arr) = self.array_behind(&arg.node, 0) {
                set.insert(arr);
            }
        }
        set
    }

    /// `Val((ptr as u64) << 32 | 4)`, `ptr = &raw mut arr as *mut u8` -> `arr`.
    fn array_behind(&self, o: &Operand<'tcx>, depth: u8) -> Option<Local> {
        if depth > 8 {
            return None;
        }
        match self.def_of(o)? {
            Rvalue::Aggregate(_, fs) => self.array_behind(fs.iter().next()?, depth + 1),
            Rvalue::BinaryOp(BinOp::BitOr | BinOp::Shl, ab) => self.array_behind(&ab.0, depth + 1),
            Rvalue::Cast(_, inner, _) | Rvalue::Use(inner) => self.array_behind(inner, depth + 1),
            Rvalue::RawPtr(_, p) => p.as_local().filter(|l| self.body.local_decls[*l].ty.is_array()),
            _ => None,
        }
    }

    /// The Rust type a local is declared with: `Val` for a payload local.
    fn local_ty(&self, l: Local) -> String {
        if self.payloads.contains(&l) { "Val".into() } else { ty_str(self.tcx, self.body.local_decls[l].ty) }
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
            Operand::Copy(p) | Operand::Move(p) => Ok(self.place(p)),
            Operand::Constant(c) => self.konst(c),
            Operand::RuntimeChecks(_) => Err("runtime-checks operand".into()),
        }
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

    /// The right-hand side of an assignment as Rust.
    fn assign_expr(&self, pl: &Place<'tcx>, rv: &Rvalue<'tcx>) -> R<String> {
        let is_val_agg = |rv: &Rvalue<'tcx>| matches!(rv, Rvalue::Aggregate(k, _) if matches!(**k, AggregateKind::Adt(d, ..) if d == self.env.val_def));
        Ok(match (pl.as_local().filter(|l| self.payloads.contains(l)), rv) {
            // Assigning a payload local: the value is a Val.
            (Some(_), Rvalue::Use(Operand::Constant(c))) => {
                let bits = c.const_.try_to_scalar_int().ok_or("payload constant")?;
                self.val_str(bits.to_bits(bits.size()) as u64)
            }
            // A constant into a slot of a frame the host reads Vals from.
            (None, Rvalue::Use(Operand::Constant(c)))
                if self.val_arrays.contains(&pl.local) && matches!(pl.projection.as_slice(), [PlaceElem::ConstantIndex { .. }]) =>
            {
                let bits = c.const_.try_to_scalar_int().ok_or("slot constant")?;
                format!("{}.0", self.val_str(bits.to_bits(bits.size()) as u64))
            }
            (Some(_), Rvalue::Use(Operand::Copy(p) | Operand::Move(p))) if p.as_local().is_some_and(|l| self.payloads.contains(&l)) => self.place(p),
            (Some(_), _) => self.val_of_expr(rv)?,
            (None, Rvalue::Aggregate(_, fs)) if is_val_agg(rv) => {
                let o = fs.iter().next().ok_or("Val without a payload")?;
                match o {
                    // `Val(l)` of a payload local is the local itself.
                    Operand::Copy(p) | Operand::Move(p) if p.as_local().is_some_and(|l| self.payloads.contains(&l)) => self.place(p),
                    _ => match self.folded_rv(o) {
                        Some(r) => self.val_of_expr(r)?,
                        None => self.rvalue(rv)?,
                    },
                }
            }
            _ => self.rvalue(rv)?,
        })
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
        let data = &self.body.basic_blocks[bb];
        for (si, st) in data.statements.iter().enumerate() {
            if let StatementKind::Assign(a) = &st.kind {
                let (pl, rv) = &**a;
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
                let s = format!("{} = {};", self.place(pl), self.assign_expr(pl, rv)?);
                self.line(s);
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

    fn call_line(&mut self, func: &Operand<'tcx>, args: &[Spanned<Operand<'tcx>>], destination: &Place<'tcx>) -> R<()> {
        let f = self.operand(func)?;
        let a: Vec<String> = args.iter().map(|a| self.operand(&a.node)).collect::<R<_>>()?;
        let dty = self.body.local_decls[destination.local].ty;
        let unread = destination.as_local().is_some_and(|l| self.uses.get(&l).copied().unwrap_or(0) == 0);
        let s = if dty.is_unit() || dty.is_never() || unread {
            format!("{f}({});", a.join(", "))
        } else {
            format!("{} = {f}({});", self.place(destination), a.join(", "))
        };
        self.line(s);
        Ok(())
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
                let s = if self.body.local_decls[Local::ZERO].ty.is_unit() { "return;".to_string() } else { format!("return {};", self.local(Local::ZERO)) };
                self.line(s);
            }
            TerminatorKind::Unreachable => self.line("unreachable!();"),
            TerminatorKind::Call { func, args, destination, target, .. } => {
                self.call_line(func, args, destination)?;
                if let Some(t) = target {
                    self.branch(bb, *t, tail)?;
                }
            }
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
                    self.call_line(func, args, destination)?;
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
        let tcx = self.tcx;
        let def_id = self.body.source.def_id();
        let name = tcx.item_name(def_id);
        let vis = if tcx.visibility(def_id).is_public() { "pub " } else { "" };
        // `mut`: rustc's copy propagation may reuse an argument local.
        let params: Vec<String> =
            self.body.args_iter().map(|l| format!("mut {}: {}", self.local(l), ty_str(tcx, self.body.local_decls[l].ty))).collect();
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
        let doc = self.spec.sigs.get(&self.fname).map(|sig| format!("/// spec: {sig}\n")).unwrap_or_default();
        let mut s = format!("{doc}{vis}fn {name}({}){ret} {{\n    unsafe {{\n", params.join(", "));
        let init = if zeroed { " = core::mem::zeroed()" } else { "" };
        for l in self.body.vars_and_temps_iter().chain((!ret_ty.is_unit()).then_some(Local::ZERO)) {
            let t = self.body.local_decls[l].ty;
            if t.is_unit() || t.is_never() || self.folded.contains_key(&l) {
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
