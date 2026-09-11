//! Statements and calls: folding, shapes, summaries, the storage schema.
use std::collections::{HashMap, HashSet};
use rustc_middle::mir::*;
use rustc_middle::ty::{self};
use rustc_span::Spanned;

use super::*;

impl<'a, 'tcx> Fn_<'a, 'tcx> {
    /// Emit the statements of a block. A pure single-use temporary is folded
    /// into its use; a pure statement nothing reads is not written -- rustc
    /// kept it only for its debuginfo name.
    pub(super) fn stmts(&mut self, bb: BasicBlock) -> R<()> {
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
    pub(super) fn use_follows(&self, bb: BasicBlock, si: usize, l: Local) -> bool {
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

    pub(super) fn stmt(&mut self, st: &Statement<'tcx>) -> R<()> {
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

    pub(super) fn call_line(&mut self, bb: BasicBlock, func: &Operand<'tcx>, args: &[Spanned<Operand<'tcx>>], destination: &Place<'tcx>) -> R<()> {
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
    pub(super) fn resolve_text(&self, shape: String) -> String {
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
    pub(super) fn shape_of(&self, l: Local) -> Option<String> {
        self.shapes.get(&l).map(|v| alternatives(v.iter().map(|(_, s)| s.clone()).collect())).or_else(|| {
            let (p, off) = match self.def_of(&Operand::Copy(Place::from(l)))? {
                Rvalue::Use(o) => self.param_load(o)?,
                _ => return None,
            };
            Some(format!("{}@{off}", self.local(p)))
        })
    }

    /// A local takes on a shape on one more path: under the arms of the block being emitted.
    pub(super) fn push_shape(&mut self, l: Local, shape: String) {
        let conds = self.conds_of(self.cur_bb);
        let v = self.shapes.entry(l).or_default();
        if !v.iter().any(|(c, s)| *s == shape && *c == conds) {
            v.push((conds, shape));
        }
    }

    /// Record what this function returns, for its callers: in terms of its
    /// parameters and the words it read through them; its own locals mean
    /// nothing there and become `_`.
    pub(super) fn returned(&self, shape: String, conds: Vec<Cond>) {
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
    pub(super) fn callee_name(&self, func: &Operand<'tcx>) -> Option<String> {
        let Operand::Constant(c) = func else { return None };
        let ty::FnDef(d, _) = c.const_.ty().kind() else { return None };
        Some(self.tcx.item_name(*d).to_string())
    }

    /// Does a call's callee write through its `j`th argument, and how far
    /// past it? None: it does not. Some(None): it does, unboundedly. A host
    /// function writes when it copies to linear memory; a lifted one as its
    /// summary says, or unboundedly before there is one.
    pub(super) fn write_extent(&self, func: &Operand<'tcx>, j: usize) -> Option<Option<u64>> {
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
    pub(super) fn wrote_through(&self, ptr: &Operand<'tcx>, end: Option<u64>) {
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
    pub(super) fn may_derive(&self, root: Local) -> HashSet<Local> {
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
    pub(super) fn display(&self, f: &str) -> String {
        self.prev.renames.get(f).map(|(id, _)| id.clone()).unwrap_or_else(|| f.to_string())
    }

    /// A value the host is handed, in the contract's terms: a built vec or
    /// map by its shape, a constant decoded, a parameter by its declared type,
    /// anything else by name.
    pub(super) fn key_shape(&self, o: &Operand<'tcx>) -> R<String> {
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
}
