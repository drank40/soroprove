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

pub fn emit<'tcx>(tcx: TyCtxt<'tcx>, env: &Env<'tcx>, header: &str, bodies: &[&Body<'tcx>]) -> R<String> {
    let mut out = String::from(header);
    for body in bodies {
        out.push('\n');
        out.push_str(&Fn_::new(tcx, env, body).emit()?);
    }
    Ok(out)
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

struct Fn_<'a, 'tcx> {
    tcx: TyCtxt<'tcx>,
    env: &'a Env<'tcx>,
    body: &'a Body<'tcx>,
    names: HashMap<Local, String>,
    payloads: HashSet<Local>,
    rpo: HashMap<BasicBlock, usize>,
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
    fn new(tcx: TyCtxt<'tcx>, env: &'a Env<'tcx>, body: &'a Body<'tcx>) -> Self {
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
        Fn_ { tcx, env, body, names, payloads, rpo, out: Vec::new(), depth: 0, open: Vec::new(), used: HashSet::new() }
    }

    /// The Rust type a local is declared with: `Val` for a payload local.
    fn local_ty(&self, l: Local) -> String {
        if self.payloads.contains(&l) { "Val".into() } else { ty_str(self.tcx, self.body.local_decls[l].ty) }
    }

    fn line(&mut self, s: impl Into<String>) {
        self.out.push((self.depth, s.into()));
    }

    fn local(&self, l: Local) -> String {
        self.names.get(&l).cloned().unwrap_or_else(|| format!("_{}", l.as_usize()))
    }

    fn place(&self, p: &Place<'tcx>) -> String {
        let mut s = self.local(p.local);
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
                    ty::Adt(def, _) if def.did() == self.env.val_def => val_expr(bits as u64),
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
                let (a, b) = (self.operand(&ab.0)?, self.operand(&ab.1)?);
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

    fn stmt(&mut self, st: &Statement<'tcx>) -> R<()> {
        match &st.kind {
            StatementKind::Assign(a) => {
                let (pl, rv) = &**a;
                if pl.ty(&self.body.local_decls, self.tcx).ty.is_unit() {
                    return Ok(()); // `_x = const ()`, or the destination of a void call
                }
                let rhs = match (pl.as_local().filter(|l| self.payloads.contains(l)), rv) {
                    // Assigning a payload local: the value is a Val.
                    (Some(_), Rvalue::Use(Operand::Constant(c))) => {
                        let bits = c.const_.try_to_scalar_int().ok_or("payload constant")?;
                        val_expr(bits.to_bits(bits.size()) as u64)
                    }
                    (Some(_), Rvalue::Use(Operand::Copy(p) | Operand::Move(p))) if p.as_local().is_some_and(|l| self.payloads.contains(&l)) => self.place(p),
                    (Some(_), _) => format!("Val({})", self.rvalue(rv)?),
                    // `Val(l)` of a payload local is the local itself.
                    (None, Rvalue::Aggregate(k, fs)) if matches!(**k, AggregateKind::Adt(d, ..) if d == self.env.val_def) => {
                        match fs.iter().next() {
                            Some(Operand::Copy(p) | Operand::Move(p)) if p.as_local().is_some_and(|l| self.payloads.contains(&l)) => self.place(p),
                            _ => self.rvalue(rv)?,
                        }
                    }
                    _ => self.rvalue(rv)?,
                };
                let s = format!("{} = {rhs};", self.place(pl));
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
        let s = if dty.is_unit() || dty.is_never() {
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
        let data = &self.body.basic_blocks[bb];
        for st in &data.statements {
            self.stmt(st)?;
        }
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
                let d = self.operand(discr)?;
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
                    for (v, t) in targets.iter() {
                        let lines = self.capture(|s| s.branch(bb, t, tail))?;
                        self.arm(format!("{v} =>"), lines);
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
            let data = &self.body.basic_blocks[*bb];
            for st in &data.statements {
                self.stmt(st)?;
            }
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
            self.line(format!("// {e}; emitted as a state machine."));
            self.state_machine()?;
            zeroed = true;
        }
        let code = std::mem::take(&mut self.out);

        let mut s = format!("{vis}fn {name}({}){ret} {{\n    unsafe {{\n", params.join(", "));
        let init = if zeroed { " = core::mem::zeroed()" } else { "" };
        for l in self.body.vars_and_temps_iter().chain((!ret_ty.is_unit()).then_some(Local::ZERO)) {
            let t = self.body.local_decls[l].ty;
            if t.is_unit() || t.is_never() {
                continue; // destinations of void and diverging calls: nothing to hold
            }
            s.push_str(&format!("        let mut {}: {}{init};\n", self.local(l), self.local_ty(l)));
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
