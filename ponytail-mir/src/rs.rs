//! MIR -> Rust, structured.
//!
//! The control flow comes from rustc's own analyses over the body: reverse
//! postorder, dominators, predecessors. A block that two edges reach is
//! placed after its immediate dominator inside a labelled block, so a jump
//! to it is `break 'b`; a loop header is `'l: loop { .. }` and its back edges
//! `continue 'l`; every other block has one predecessor and is written inline
//! where that predecessor branches. This is the Ramsey algorithm for reducible
//! graphs, which is what inlined wasm gives. Every local is declared once at
//! the top and assigned where MIR assigns it; rustc's definite-initialisation
//! check then confirms what SSA promised.
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::fmt::Write as _;

use rustc_middle::mir::interpret::GlobalAlloc;
use rustc_middle::mir::*;
use rustc_middle::ty::{self, Ty, TyCtxt};

use crate::mir::Env;

type R<T> = Result<T, String>;

pub fn emit<'tcx>(tcx: TyCtxt<'tcx>, env: &Env<'tcx>, header: &str, bodies: &[Body<'tcx>]) -> R<String> {
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

struct Fn_<'a, 'tcx> {
    tcx: TyCtxt<'tcx>,
    env: &'a Env<'tcx>,
    body: &'a Body<'tcx>,
    names: HashMap<Local, String>,
    rpo: HashMap<BasicBlock, usize>,
    /// Labels currently open while structuring; a jump to one that is not
    /// means the CFG is not reducible, and the function falls back.
    open: RefCell<Vec<BasicBlock>>,
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
                if !p.projection.is_empty() {
                    continue;
                }
                // An LLVM name (`cmp2.not`) as a Rust identifier, whole and
                // unique in this function.
                let mut n = crate::rs_name(&d.name.to_string().replace('.', "_"));
                if !used.insert(n.clone()) {
                    n = format!("{n}_{}", p.local.as_usize());
                    used.insert(n.clone());
                }
                names.insert(p.local, n);
            }
        }
        let rpo = body.basic_blocks.reverse_postorder().iter().enumerate().map(|(n, b)| (*b, n)).collect();
        Fn_ { tcx, env, body, names, rpo, open: RefCell::new(Vec::new()) }
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
                other => format!("{s}/* {other:?} */"),
            };
        }
        s
    }

    fn konst(&self, c: &ConstOperand<'tcx>) -> R<String> {
        let ty = c.const_.ty();
        if let ty::FnDef(def_id, _) = ty.kind() {
            return Ok(self.tcx.item_name(*def_id).to_string());
        }
        let Some(scalar) = c.const_.try_to_scalar() else { return Err(format!("non-scalar constant {:?}", c.const_)) };
        Ok(match scalar {
            interpret::Scalar::Int(i) => {
                let bits = i.to_bits(i.size());
                if ty.is_bool() {
                    (bits != 0).to_string()
                } else if ty.is_raw_ptr() {
                    format!("({bits}usize as {})", ty_str(self.tcx, ty))
                } else {
                    format!("{bits}{}", ty_str(self.tcx, ty))
                }
            }
            interpret::Scalar::Ptr(p, _) => match self.tcx.try_get_global_alloc(p.provenance.alloc_id()) {
                Some(GlobalAlloc::Static(d)) => format!("(&raw mut {} as {})", self.tcx.item_name(d), ty_str(self.tcx, ty)),
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
        Ok(match rv {
            Rvalue::Use(o) => self.operand(o)?,
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
                let (o, t) = (self.operand(o)?, ty_str(self.tcx, *ty));
                match kind {
                    CastKind::Transmute => format!("core::mem::transmute::<_, {t}>({o})"),
                    _ => format!("{o} as {t}"),
                }
            }
            Rvalue::Aggregate(kind, fields) => match **kind {
                AggregateKind::Adt(def, _, ..) if def == self.env.val_def => {
                    format!("Val({})", fields.iter().map(|f| self.operand(f)).collect::<R<Vec<_>>>()?.join(", "))
                }
                AggregateKind::Adt(def, variant, ..) => {
                    let adt = self.tcx.adt_def(def);
                    format!("{}::{}", self.tcx.item_name(def), adt.variant(variant).name)
                }
                _ => return Err(format!("aggregate {kind:?}")),
            },
            Rvalue::RawPtr(k, p) => {
                format!("&raw {} {}", if matches!(k, RawPtrKind::Mut) { "mut" } else { "const" }, self.place(p))
            }
            other => return Err(format!("rvalue {other:?}")),
        })
    }

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

    /// The code for a jump from `from` to `to`.
    fn branch(&self, from: BasicBlock, to: BasicBlock, ind: &str) -> R<String> {
        let doms = self.body.basic_blocks.dominators();
        if self.is_header(to) && doms.dominates(to, from) {
            self.check_open(to)?;
            return Ok(format!("{ind}continue 'l{};\n", to.as_usize()));
        }
        if self.is_merge(to) {
            self.check_open(to)?;
            return Ok(format!("{ind}break 'b{};\n", to.as_usize()));
        }
        self.node(to, ind)
    }

    fn check_open(&self, bb: BasicBlock) -> R<()> {
        if self.open.borrow().contains(&bb) {
            Ok(())
        } else {
            Err(format!("bb{} is jumped to from outside its region: irreducible control flow", bb.as_usize()))
        }
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

    fn open_labels(&self, s: &mut String, inner: &mut String, merges: &[BasicBlock]) {
        for m in merges.iter().rev() {
            let _ = writeln!(s, "{inner}'b{}: {{", m.as_usize());
            inner.push_str("    ");
            self.open.borrow_mut().push(*m);
        }
    }

    fn close_labels(&self, s: &mut String, inner: &mut String, merges: &[BasicBlock]) -> R<()> {
        for m in merges {
            inner.truncate(inner.len() - 4);
            let _ = writeln!(s, "{inner}}}");
            self.open.borrow_mut().pop();
            s.push_str(&self.node(*m, inner)?);
        }
        Ok(())
    }

    fn node(&self, bb: BasicBlock, ind: &str) -> R<String> {
        let mut s = String::new();
        let merges = self.merges_under(bb);
        let mut inner = ind.to_string();
        if !self.is_header(bb) {
            self.open_labels(&mut s, &mut inner, &merges);
            s.push_str(&self.code(bb, &inner)?);
            self.close_labels(&mut s, &mut inner, &merges)?;
            return Ok(s);
        }
        // A loop: merge nodes in its body live inside the `loop`, and only the
        // exits -- merge nodes it dominates but which never come back -- after.
        let body = self.loop_of(bb);
        let (inside, exits): (Vec<_>, Vec<_>) = merges.iter().copied().partition(|m| body.contains(m));
        self.open_labels(&mut s, &mut inner, &exits);
        let _ = writeln!(s, "{inner}'l{}: loop {{", bb.as_usize());
        inner.push_str("    ");
        self.open.borrow_mut().push(bb);
        self.open_labels(&mut s, &mut inner, &inside);
        s.push_str(&self.code(bb, &inner)?);
        self.close_labels(&mut s, &mut inner, &inside)?;
        inner.truncate(inner.len() - 4);
        let _ = writeln!(s, "{inner}}}");
        self.open.borrow_mut().pop();
        self.close_labels(&mut s, &mut inner, &exits)?;
        Ok(s)
    }

    /// The fallback for a CFG the structurer cannot place: one arm per block,
    /// dispatch on `__bb`. Faithful, and valid Rust; just not pretty.
    fn state_machine(&self, ind: &str) -> R<String> {
        let mut s = format!("{ind}let mut __bb: usize = 0;\n{ind}loop {{\n{ind}    match __bb {{\n");
        let inner = format!("{ind}            ");
        for bb in self.body.basic_blocks.reverse_postorder() {
            let _ = writeln!(s, "{ind}        {} => {{", bb.as_usize());
            let data = &self.body.basic_blocks[*bb];
            for st in &data.statements {
                if let StatementKind::Assign(a) = &st.kind {
                    let _ = writeln!(s, "{inner}{} = {};", self.place(&a.0), self.rvalue(&a.1)?);
                }
            }
            let goto = |t: BasicBlock| format!("{inner}__bb = {}; continue;\n", t.as_usize());
            match &data.terminator.as_ref().ok_or("block without terminator")?.kind {
                TerminatorKind::Goto { target } => s.push_str(&goto(*target)),
                TerminatorKind::Return => {
                    let _ = writeln!(s, "{inner}return {};", if self.body.local_decls[Local::ZERO].ty.is_unit() { "" } else { "_0" });
                }
                TerminatorKind::Unreachable => {
                    let _ = writeln!(s, "{inner}unreachable!();");
                }
                TerminatorKind::Call { func, args, destination, target, .. } => {
                    let f = self.operand(func)?;
                    let a: Vec<String> = args.iter().map(|a| self.operand(&a.node)).collect::<R<_>>()?;
                    let dty = self.body.local_decls[destination.local].ty;
                    if dty.is_unit() || dty.is_never() {
                        let _ = writeln!(s, "{inner}{f}({});", a.join(", "));
                    } else {
                        let _ = writeln!(s, "{inner}{} = {f}({});", self.place(destination), a.join(", "));
                    }
                    if let Some(t) = target {
                        s.push_str(&goto(*t));
                    }
                }
                TerminatorKind::SwitchInt { discr, targets } => {
                    let is_bool = discr.ty(&self.body.local_decls, self.tcx).is_bool();
                    let _ = writeln!(s, "{inner}match {} {{", self.operand(discr)?);
                    for (v, t) in targets.iter() {
                        let pat = if is_bool { (v != 0).to_string() } else { v.to_string() };
                        let _ = writeln!(s, "{inner}    {pat} => {{ __bb = {}; }}", t.as_usize());
                    }
                    let _ = writeln!(s, "{inner}    _ => {{ __bb = {}; }}\n{inner}}}\n{inner}continue;", targets.otherwise().as_usize());
                }
                other => return Err(format!("terminator {other:?}")),
            }
            let _ = writeln!(s, "{ind}        }}");
        }
        let _ = write!(s, "{ind}        _ => unreachable!(),\n{ind}    }}\n{ind}}}\n");
        Ok(s)
    }

    /// Statements and terminator of one block.
    fn code(&self, bb: BasicBlock, ind: &str) -> R<String> {
        let data = &self.body.basic_blocks[bb];
        let mut s = String::new();
        for st in &data.statements {
            if let StatementKind::Assign(a) = &st.kind {
                let _ = writeln!(s, "{ind}{} = {};", self.place(&a.0), self.rvalue(&a.1)?);
            }
        }
        let Some(t) = &data.terminator else { return Err("block without terminator".into()) };
        match &t.kind {
            TerminatorKind::Goto { target } => s.push_str(&self.branch(bb, *target, ind)?),
            TerminatorKind::Return => {
                if self.body.local_decls[Local::ZERO].ty.is_unit() {
                    let _ = writeln!(s, "{ind}return;");
                } else {
                    let _ = writeln!(s, "{ind}return _0;");
                }
            }
            TerminatorKind::Unreachable => {
                let _ = writeln!(s, "{ind}unreachable!();");
            }
            TerminatorKind::Call { func, args, destination, target, .. } => {
                let f = self.operand(func)?;
                let a: Vec<String> = args.iter().map(|a| self.operand(&a.node)).collect::<R<_>>()?;
                let dty = self.body.local_decls[destination.local].ty;
                if dty.is_unit() || dty.is_never() {
                    let _ = writeln!(s, "{ind}{f}({});", a.join(", "));
                } else {
                    let _ = writeln!(s, "{ind}{} = {f}({});", self.place(destination), a.join(", "));
                }
                match target {
                    Some(t) => s.push_str(&self.branch(bb, *t, ind)?),
                    None => {}
                }
            }
            TerminatorKind::SwitchInt { discr, targets } => {
                let d = self.operand(discr)?;
                let inner = format!("{ind}    ");
                let dty = discr.ty(&self.body.local_decls, self.tcx);
                if dty.is_bool() && targets.iter().count() == 1 {
                    let (v, bb0) = targets.iter().next().unwrap();
                    let (then, els) = if v == 0 { (targets.otherwise(), bb0) } else { (bb0, targets.otherwise()) };
                    let _ = writeln!(s, "{ind}if {d} {{");
                    s.push_str(&self.branch(bb, then, &inner)?);
                    let _ = writeln!(s, "{ind}}} else {{");
                    s.push_str(&self.branch(bb, els, &inner)?);
                    let _ = writeln!(s, "{ind}}}");
                } else {
                    let _ = writeln!(s, "{ind}match {d} {{");
                    let inner2 = format!("{inner}    ");
                    for (v, t) in targets.iter() {
                        let _ = writeln!(s, "{inner}{v} => {{");
                        s.push_str(&self.branch(bb, t, &inner2)?);
                        let _ = writeln!(s, "{inner}}}");
                    }
                    let _ = writeln!(s, "{inner}_ => {{");
                    s.push_str(&self.branch(bb, targets.otherwise(), &inner2)?);
                    let _ = writeln!(s, "{inner}}}\n{ind}}}");
                }
            }
            other => return Err(format!("terminator {other:?}")),
        }
        Ok(s)
    }

    fn emit(&self) -> R<String> {
        let tcx = self.tcx;
        let def_id = self.body.source.def_id();
        let name = tcx.item_name(def_id);
        let vis = if tcx.visibility(def_id).is_public() { "pub " } else { "" };
        let params: Vec<String> = self
            .body
            .args_iter()
            .map(|l| format!("{}: {}", self.local(l), ty_str(tcx, self.body.local_decls[l].ty)))
            .collect();
        let ret_ty = self.body.local_decls[Local::ZERO].ty;
        let ret = if ret_ty.is_unit() { String::new() } else { format!(" -> {}", ty_str(tcx, ret_ty)) };
        let mut s = format!("{vis}fn {name}({}){ret} {{\n    unsafe {{\n", params.join(", "));
        // Structured when the CFG is reducible; a state machine otherwise.
        // Structured code declares every local once and assigns it where MIR
        // does, and rustc's definite-initialisation check is then the proof
        // that SSA held. The state machine hides the flow from that check,
        // so there the locals start zeroed; MIR still writes each before any
        // read.
        self.open.borrow_mut().clear();
        let (body, init) = match self.node(START_BLOCK, "        ") {
            Ok(b) => (b, false),
            Err(e) => {
                let _ = writeln!(s, "        // {e}; emitted as a state machine.");
                (self.state_machine("        ")?, true)
            }
        };
        for l in self.body.vars_and_temps_iter() {
            let t = self.body.local_decls[l].ty;
            if t.is_unit() || t.is_never() {
                continue; // destinations of void and diverging calls: nothing to hold
            }
            // A frame is only ever addressed, never assigned as a whole; its
            // contents are unspecified in wasm too, and zero is the alloca.
            let init = match (init, t.kind()) {
                (_, ty::Array(..)) => " = core::mem::zeroed()",
                (true, _) => " = core::mem::zeroed()",
                _ => "",
            };
            let _ = writeln!(s, "        let mut {}: {}{init};", self.local(l), ty_str(tcx, t));
        }
        if !ret_ty.is_unit() {
            let init = if init { " = core::mem::zeroed()" } else { "" };
            let _ = writeln!(s, "        let mut _0: {}{init};", ty_str(tcx, ret_ty));
        }
        s.push_str(&body);
        s.push_str("    }\n}\n");
        Ok(s)
    }
}
