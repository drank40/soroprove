//! Structure: dominators, merges, loops; the function as structured Rust, or a state machine.
use std::collections::HashSet;
use rustc_middle::mir::*;

use super::*;

impl<'a, 'tcx> Fn_<'a, 'tcx> {
    pub(super) fn is_merge(&self, bb: BasicBlock) -> bool {
        self.body.basic_blocks.predecessors()[bb].len() >= 2
    }

    pub(super) fn is_header(&self, bb: BasicBlock) -> bool {
        let doms = self.body.basic_blocks.dominators();
        self.body.basic_blocks.predecessors()[bb].iter().any(|p| doms.dominates(bb, *p))
    }

    /// Dominator-tree children of `bb` that are merge nodes, in RPO.
    pub(super) fn merges_under(&self, bb: BasicBlock) -> Vec<BasicBlock> {
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
    pub(super) fn loop_of(&self, h: BasicBlock) -> HashSet<BasicBlock> {
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
    pub(super) fn capture(&mut self, f: impl FnOnce(&mut Self) -> R<()>) -> R<Vec<(usize, String)>> {
        let saved = std::mem::take(&mut self.out);
        self.depth += 1;
        let r = f(self);
        self.depth -= 1;
        let lines = std::mem::replace(&mut self.out, saved);
        r.map(|_| lines)
    }

    pub(super) fn begin(&mut self, label: BasicBlock) -> usize {
        self.open.push(label);
        self.depth += 1;
        self.out.len()
    }

    /// Close a labelled block opened at `start`: write the label only if some
    /// jump used it; otherwise the lines just lose one level of nesting.
    pub(super) fn end_block(&mut self, label: BasicBlock, start: usize) {
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

    pub(super) fn end_loop(&mut self, header: BasicBlock, start: usize) {
        self.depth -= 1;
        self.open.pop();
        let head = if self.used.contains(&header) { format!("'l{}: loop {{", header.as_usize()) } else { "loop {".into() };
        self.out.insert(start, (self.depth, head));
        self.line("}");
    }

    /// `'b_m2: { 'b_m1: { 'b_m0: { inner } node(m0) } node(m1) } node(m2)`,
    /// with tails threaded: `inner` falls through to m0, node(m_i) to m_i+1,
    /// and the last one to whatever this whole chain falls through to.
    pub(super) fn chain(&mut self, merges: &[BasicBlock], tail: Option<BasicBlock>, inner: &mut dyn FnMut(&mut Self, Option<BasicBlock>) -> R<()>) -> R<()> {
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
    pub(super) fn node(&mut self, bb: BasicBlock, tail: Option<BasicBlock>) -> R<()> {
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
    pub(super) fn branch(&mut self, from: BasicBlock, to: BasicBlock, tail: Option<BasicBlock>) -> R<()> {
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

    pub(super) fn arm(&mut self, head: String, lines: Vec<(usize, String)>) {
        if lines.is_empty() {
            self.line(format!("{head} {{}}"));
            return;
        }
        self.line(format!("{head} {{"));
        self.out.extend(lines);
        self.line("}");
    }

    /// Statements and terminator of one block.
    pub(super) fn code(&mut self, bb: BasicBlock, tail: Option<BasicBlock>) -> R<()> {
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
                    let tag = self.is_tag(discr);
                    // The tag consts are u64; an i32-wide tag is matched as u64.
                    let d = if tag && discr.ty(&self.body.local_decls, self.tcx) == self.tcx.types.u32 { format!("{d} as u64") } else { d };
                    self.line(format!("match {d} {{"));
                    self.depth += 1;
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
    pub(super) fn state_machine(&mut self) -> R<()> {
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

    pub(super) fn emit(mut self) -> R<String> {
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
