//! The source level: an export as soroban-sdk code, statement by statement.
use std::collections::HashSet;
use rustc_middle::mir::*;
use rustc_span::Spanned;

use super::*;

impl<'a, 'tcx> Fn_<'a, 'tcx> {
    /// An assignment in SDK terms. A store into a frame and pure plumbing
    /// say nothing: the shapes carry them. A value bound for the return is
    /// wrapped as the spec's return type wants. A Val assigned or read more
    /// than once is bound to its name.
    pub(super) fn sdk_stmt(&mut self, pl: &Place<'tcx>, rv: &Rvalue<'tcx>) -> R<()> {
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
            // What the shapes know the value to be beats how it was computed.
            let e = match self.shape_of(dst).map(|sh| self.sdk_value(&sh)) {
                Some(Ok(e)) => e,
                _ => value(self)?,
            };
            let n = self.sdk_name(dst);
            self.line(format!("{n} = {e};"));
            self.declared.insert(dst);
        }
        Ok(())
    }

    /// A value for a return-bound local: the return expression itself when
    /// `_0` is assigned right before every `return`, else a named binding.
    pub(super) fn sdk_bind(&mut self, dst: Local, e: String) {
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
    pub(super) fn live_uses(&self, l: Local) -> usize {
        // Uses minus the mentions inside pure statements nothing reads (rustc
        // debuginfo). Computed once for every local in a single pass, not
        // rescanned per call -- the per-statement path asks for this a lot.
        if self.dead_mentions.borrow().is_none() {
            let mut dead: HashMap<Local, usize> = HashMap::new();
            for (bb, data) in self.body.basic_blocks.iter_enumerated() {
                for (si, st) in data.statements.iter().enumerate() {
                    if let StatementKind::Assign(a) = &st.kind {
                        if pure(&a.1) && a.0.as_local().is_some_and(|d| self.uses.get(&d).copied().unwrap_or(0) == 0) {
                            for m in mentions(self.body, bb, si) {
                                *dead.entry(m).or_default() += 1;
                            }
                        }
                    }
                }
            }
            *self.dead_mentions.borrow_mut() = Some(dead);
        }
        let dead = self.dead_mentions.borrow().as_ref().and_then(|d| d.get(&l).copied()).unwrap_or(0);
        self.uses.get(&l).copied().unwrap_or(0).saturating_sub(dead)
    }

    /// The type a use gives an otherwise untyped local (a storage read
    /// rustc cannot infer): the receiver of `require_auth` is an `Address`.
    /// diver: the one use-typed case so far.
    fn use_type(&self, l: Local) -> Option<&'static str> {
        self.body.basic_blocks.iter().find_map(|b| match &b.terminator.as_ref()?.kind {
            TerminatorKind::Call { func, args, .. } if self.callee_name(func).as_deref() == Some("require_auth") => {
                (self.source_local(&args.first()?.node) == Some(l)).then_some("Address")
            }
            _ => None,
        })
    }

    pub(super) fn sdk_name(&self, l: Local) -> String {
        let n = self.raw_name(l);
        if l == Local::ZERO && n == "_0" { "ret".into() } else { n }
    }

    pub(super) fn sdk_arg(&self, args: &[Spanned<Operand<'tcx>>], i: usize) -> R<String> {
        self.sdk_operand(&args.get(i).ok_or("missing argument")?.node)
    }

    pub(super) fn sdk_dur(&self, args: &[Spanned<Operand<'tcx>>], i: usize) -> R<&'static str> {
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
    pub(super) fn sdk_call(&mut self, f: &str, args: &[Spanned<Operand<'tcx>>], destination: &Place<'tcx>, shape: Option<&str>) -> R<()> {
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
            "bytes_len" => {
                expr = Some(format!("{}.len()", self.sdk_arg(args, 0)?));
                None
            }
            "compute_hash_sha256" | "compute_hash_keccak256" => {
                expr = Some(format!("env.crypto().{}(&{})", &f[13..], self.sdk_arg(args, 0)?));
                None
            }
            "recover_key_ecdsa_secp256k1" => {
                expr = Some(format!("env.crypto().secp256k1_recover(&{}, &{}, {})", self.sdk_arg(args, 0)?, self.sdk_arg(args, 1)?, self.sdk_arg(args, 2)?));
                None
            }
            "serialize_to_bytes" => {
                expr = Some(format!("{}.to_xdr(&env)", self.sdk_arg(args, 0)?));
                None
            }
            "obj_cmp" => {
                expr = Some(format!("({}.cmp(&{}) as i64)", self.sdk_arg(args, 0)?, self.sdk_arg(args, 1)?));
                None
            }
            "llvm_bswap_i64" => {
                expr = Some(format!("{}.swap_bytes()", self.sdk_arg(args, 0)?));
                None
            }
            // The SDK's token client, every argument by pointer into a frame.
            _ if self.spec.sdk.get(f).is_some_and(|p| p.ends_with("TokenClient::transfer")) => {
                let a = |me: &Self, i: usize, off: u64| -> R<String> {
                    let l = me.frame_arg(me.cur_bb, &args[i].node, off).ok_or_else(|| format!("argument {i} of transfer"))?;
                    me.sdk_operand(&Operand::Copy(Place::from(l)))
                };
                // The amount is an i128 in two words at the fourth pointer.
                let lo = self.frame_arg(self.cur_bb, &args[3].node, 0);
                let hi = self.frame_arg(self.cur_bb, &args[3].node, 8);
                let amount = match (lo, hi) {
                    (Some(lo), Some(hi)) => fold_wide(&format!("i128({}, {})", self.key_shape(&Operand::Copy(Place::from(hi)))?, self.key_shape(&Operand::Copy(Place::from(lo)))?)),
                    _ => return Err("transfer amount".into()),
                };
                Some(format!("token::Client::new(&env, &{}).transfer(&{}, &{}, &({} as i128));", a(self, 0, 0)?, a(self, 1, 0)?, a(self, 2, 0)?, self.sdk_value(&amount)?))
            }
            _ if self.spec.sdk.get(f).is_some_and(|p| p.ends_with("Env>::contract_event")) => {
                let topics = self.sdk_value(&self.key_shape(&args[0].node)?)?;
                let topics = topics.strip_prefix("vec![&env, ").and_then(|t| t.strip_suffix(']')).map(|t| format!("({t},)")).ok_or("event topics")?;
                Some(format!("env.events().publish({topics}, {});", self.sdk_arg(args, 1)?))
            }
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
            // diver: a storage read inlined at its one use; a write in between would reorder it. Not seen.
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
    pub(super) fn sdk_switch(&mut self, bb: BasicBlock, discr: &Operand<'tcx>, targets: &SwitchTargets, tail: Option<BasicBlock>) -> R<()> {
        // A number read out of a Val: the parameter (or host value) itself,
        // its words `x as u64` and `(x >> 64) as u64`; nothing to write.
        if let Some(d) = self.decodes.get(&bb).cloned() {
            let e = self.sdk_operand(&Operand::Copy(Place::from(d.val)))?;
            for (l, part) in d.parts {
                let v = match part {
                    decode::Part::Lo => format!("({e} as u64)"),
                    decode::Part::Hi => format!("(({e} >> 64) as u64)"),
                    decode::Part::Whole => e.clone(),
                };
                self.inlined.insert(l, v);
            }
            return Ok(());
        }
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
            // Both arms the same (a number re-encoded either way): no branch.
            if then_lines == else_lines {
                self.out.extend(then_lines);
                return Ok(());
            }
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
    pub(super) fn diverges_at(&self, bb: BasicBlock, depth: u8) -> bool {
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
    pub(super) fn bool_val(&self, o: &Operand<'tcx>) -> Option<Local> {
        let l = self.val_source(o)?;
        (self.call_def.get(&l)?.0 == "has_contract_data").then_some(l)
    }

    /// `(param.0 >> 32) as uN` of a parameter declared as an integer enum:
    /// the parameter and its enum.
    pub(super) fn enum_param(&self, o: &Operand<'tcx>) -> Option<(Local, String)> {
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
    pub(super) fn sdk_operand(&self, o: &Operand<'tcx>) -> R<String> {
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

    pub(super) fn sdk_rvalue(&self, rv: &Rvalue<'tcx>) -> R<String> {
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
                // A number re-encoded from its parts is that number.
                if let Some(enc) = self.small_encode(o) {
                    return self.sdk_value(&fold_wide(&enc));
                }
                self.sdk_operand(o)
            }
            _ => Err(format!("not reconstructed: {}", self.rvalue(rv)?)),
        }
    }

    /// A parameter as an expression: `.clone()` unless its type is Copy.
    pub(super) fn param_expr(&self, l: Local) -> String {
        let n = self.local(l);
        if self.copy_param(&n) { n } else { format!("{n}.clone()") }
    }

    pub(super) fn copy_param(&self, name: &str) -> bool {
        let Some(i) = self.body.args_iter().position(|l| self.local(l) == name) else { return true };
        let ty = self.spec.params.get(&self.fname).and_then(|ps| ps.get(i)).map(String::as_str).unwrap_or("Val");
        matches!(ty, "bool" | "u32" | "i32" | "u64" | "i64" | "u128" | "i128" | "Val") || self.spec.enums.contains_key(ty)
    }

    /// The return value as the spec's return type wants it: `Ok`/`Err` for a
    /// `Result`, `Some`/`None` for an `Option`, nothing for `()`.
    pub(super) fn wrap_ret(&self, e: String) -> String {
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
    pub(super) fn sdk_value(&self, s: &str) -> R<String> {
        // `fname::x` is a local of this function that had no shape -- often
        // one the source bound (a storage read, a require_auth receiver).
        // If it is declared, inlined or a parameter, say it by name.
        let own = format!("{}::", self.display(&self.fname));
        if let Some(rest) = s.strip_prefix(&own) {
            if rest.chars().all(|c| c.is_alphanumeric() || c == '_') {
                if let Some(l) = self.body.local_decls.indices().find(|l| self.raw_name(*l) == rest) {
                    if self.declared.contains(&l) || self.inlined.contains_key(&l) || (1..=self.body.arg_count).contains(&l.as_usize()) {
                        return self.sdk_operand(&Operand::Copy(Place::from(l)));
                    }
                }
            }
        }
        let hole = s.split(|c: char| !c.is_alphanumeric() && c != '_').any(|w| w == "_");
        if hole || s.contains("Val(") || s.contains("::{") || s.contains(" | ") || s.contains('@') || s.contains("(at ") || s.contains("Map{") || s.contains(&own) || s.contains("u128(") || s.contains("i128(") {
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
        let t = rewrite_calls(&t, "lo(", &|a| format!("({a} as u64)"));
        let t = t.replace("get_ledger_timestamp()", "env.ledger().timestamp()").replace("get_ledger_sequence()", "env.ledger().sequence()").replace("get_current_contract_address()", "env.current_contract_address()");
        let t = rewrite_calls(&t, "hi(", &|a| format!("(({a} >> 64) as u64)"));
        let t = rewrite_calls(&t, "Val::i32(", &|a| a.to_string());
        let t = t.replace("Val::TRUE", "true").replace("Val::FALSE", "false").replace("Val::VOID", "()");
        let t = rewrite_calls(&t.replace("Vec[", "Vec("), "Vec(", &|a| format!("vec![&env, {a}]"));
        let t = expand_shorthand(&t);
        Ok(self.clone_params(&t))
    }

    /// Non-Copy parameters used as values get `.clone()`: not field names,
    /// not paths, not inside string literals.
    pub(super) fn clone_params(&self, s: &str) -> String {
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
    pub(super) fn emit_sdk(mut self) -> R<String> {
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
                let ty = self.use_type(l).map(|t| format!(": {t}")).unwrap_or_default();
                s.push_str(&format!("        let mut {}{ty};\n", self.sdk_name(l)));
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
}
