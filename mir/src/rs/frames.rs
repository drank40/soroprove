//! Frames: Val arrays, literal arrays, words read through pointer parameters and the arms they decide.
use std::collections::{HashMap, HashSet};
use std::rc::Rc;
use rustc_middle::mir::*;
use rustc_middle::ty::{self};

use super::*;

/// Byte offset in a frame -> the values it may hold, each under switch arms.
pub(super) type Words = HashMap<u64, Vec<(Vec<Cond>, String, Option<u64>)>>;

impl<'a, 'tcx> Fn_<'a, 'tcx> {
    /// Everything computed from `&raw mut arr`: casts, the exposed address,
    /// the packed `Val::u32` position. Single-definition locals only.
    pub(super) fn derived_from(&self, arr: Local) -> HashSet<Local> {
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
    pub(super) fn val_position(callee: &str) -> Option<usize> {
        Some(match callee {
            "vec_new_from_linear_memory" => 0,
            "map_new_from_linear_memory" | "vec_unpack_to_linear_memory" => 1,
            "map_unpack_to_linear_memory" => 2,
            _ => return None,
        })
    }

    /// The keys-position argument of a host call that reads map keys.
    pub(super) fn keys_position(callee: &str) -> Option<usize> {
        Some(match callee {
            "map_new_from_linear_memory" => 0,
            "map_unpack_to_linear_memory" | "symbol_index_in_linear_memory" => 1,
            _ => return None,
        })
    }

    /// Arrays handed to the host at a Val-reading position, with their
    /// length. The position is `Val::u32(frame as u32)`: walk that back to
    /// the `&raw mut` it came from.
    pub(super) fn find_val_arrays(&self) -> HashMap<Local, u64> {
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
    pub(super) fn find_literal_arrays(&self) -> (HashSet<Local>, HashSet<Local>) {
        let mut plumbing = HashSet::new();
        let arrays = self.find_literal_arrays_inner(&mut plumbing);
        (arrays, plumbing)
    }

    pub(super) fn find_literal_arrays_inner(&self, plumbing: &mut HashSet<Local>) -> HashSet<Local> {
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
    pub(super) fn array_behind(&self, o: &Operand<'tcx>, depth: u8) -> Option<Local> {
        self.array_behind_at(o, depth).filter(|(_, off)| *off == 0).map(|(a, _)| a)
    }

    /// `Val((ptr as u64) << 32 | 4)`, `ptr = &raw mut arr as *mut u8` plus a
    /// constant offset -> `(arr, byte offset)`.
    pub(super) fn array_behind_at(&self, o: &Operand<'tcx>, depth: u8) -> Option<(Local, u64)> {
        if depth > 16 {
            return None;
        }
        if let Some(rv) = self.def_of(o) {
            return self.array_behind_rv(rv, depth);
        }
        // A phi of the same address on every path (LLVM keeps the arms'
        // separate geps apart): that address.
        let l = match o {
            Operand::Copy(p) | Operand::Move(p) => p.as_local().filter(|l| self.defs.get(l).copied().unwrap_or(0) > 1)?,
            _ => return None,
        };
        let mut found: Option<(Local, u64)> = None;
        for st in self.body.basic_blocks.iter().flat_map(|b| &b.statements) {
            let StatementKind::Assign(a) = &st.kind else { continue };
            if a.0.as_local() != Some(l) {
                continue;
            }
            let here = self.array_behind_rv(&a.1, depth + 1)?;
            if found.is_some_and(|f| f != here) {
                return None;
            }
            found = Some(here);
        }
        found
    }

    fn array_behind_rv(&self, rv: &Rvalue<'tcx>, depth: u8) -> Option<(Local, u64)> {
        match rv {
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
    pub(super) fn name_fields(&mut self) {
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
    pub(super) fn param_load(&self, o: &Operand<'tcx>) -> Option<(Local, u64)> {
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
    pub(super) fn param_ptr(&self, o: &Operand<'tcx>, off: u64) -> Option<(Local, u64)> {
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
    pub(super) fn conds_of(&self, bb: BasicBlock) -> Vec<Cond> {
        if let Some(c) = self.conds_memo.borrow().get(&bb) {
            return c.clone();
        }
        let out = self.conds_walk(bb);
        self.conds_memo.borrow_mut().insert(bb, out.clone());
        out
    }

    fn conds_walk(&self, bb: BasicBlock) -> Vec<Cond> {
        let doms = self.body.basic_blocks.dominators();
        let mut out = Vec::new();
        let mut child = bb;
        while let Some(d) = doms.immediate_dominator(child) {
            if let TerminatorKind::SwitchInt { discr, targets } = &self.body.basic_blocks[d].terminator().kind {
                // A word read through a pointer parameter, `a0@8`; or the
                // parameter itself, `a0`, an integer the caller passed (an
                // enum's discriminant split off its payload). diver: a
                // narrowing cast of the parameter compares the caller's
                // whole constant; enum discriminants are small.
                let word = if let Some((p, off)) = self.param_load(discr) {
                    let bytes = match discr.ty(&self.body.local_decls, self.tcx).kind() {
                        ty::Uint(ty::UintTy::U8) | ty::Int(ty::IntTy::I8) => 1,
                        ty::Uint(ty::UintTy::U16) | ty::Int(ty::IntTy::I16) => 2,
                        ty::Uint(ty::UintTy::U32) | ty::Int(ty::IntTy::I32) => 4,
                        _ => 8,
                    };
                    let w = format!("{}@{off}", self.local(p));
                    if bytes < 8 { format!("{w}:{bytes}") } else { w }
                } else if let Some((p, 0)) = self.param_ptr(discr, 0) {
                    self.local(p)
                } else {
                    child = d;
                    continue;
                };
                match targets.iter().find(|(_, t)| *t == child) {
                    Some((v, _)) => out.push((word, vec![v as u64], false)),
                    None if targets.otherwise() == child => out.push((word, targets.iter().map(|(v, _)| v as u64).collect(), true)),
                    None => {}
                }
            }
            child = d;
        }
        out
    }

    /// The words written into the frame an argument points to, as of a call
    /// in `bb`: byte offset from the pointer -> (the value as the contract
    /// knows it, its constant). One value where every path agrees; the
    /// alternatives otherwise.
    pub(super) fn frame_words(&self, bb: BasicBlock, o: &Operand<'tcx>) -> HashMap<u64, (String, Option<u64>)> {
        let Some((arr, base)) = self.array_behind_at(o, 0) else {
            // A pointer into rodata: a static, its words as they lie there.
            let Some(p) = self.konst_u64(o) else { return HashMap::new() };
            return (0..8)
                .filter_map(|i| {
                    let w = self.spec.u64_at(p + 8 * i)?;
                    Some((8 * i, (self.val_str(w), Some(w))))
                })
                .collect();
        };
        self.words_at(bb, self.body.basic_blocks[bb].statements.len(), arr)
            .into_iter()
            .filter_map(|(k, vs)| {
                let o = k.checked_sub(base)?;
                let (s, konst) = match vs.as_slice() {
                    [(_, s, k)] => (s.clone(), *k),
                    _ => (alternatives(vs.iter().map(|v| v.1.clone()).collect()), None),
                };
                Some((o, (s, konst)))
            })
            .collect()
    }

    /// The Val words of frame array `arr` as of statement `upto` of `bb`
    /// (past the end: its terminator too): byte offset -> the values it may
    /// hold, each with the switch arms it was stored under. Stores flow
    /// along every path into the block, merging where paths join: one value
    /// where they agree, else one per path, under that path's arms. A store
    /// at an unknown offset, or a call handed a pointer into the frame,
    /// forgets what it may have overwritten -- from that pointer's offset
    /// on -- except the SDK's small-symbol encoder, whose result is known. A
    /// loop forgets the offsets its body touches. diver: a callee writing
    /// below the pointer it was given is not Rust; not considered.
    pub(super) fn words_at(&self, bb: BasicBlock, upto: usize, arr: Local) -> Words {
        let mut words = self.words_start(bb, arr, &mut HashSet::new());
        self.run_block(bb, upto, arr, &mut words);
        words
    }

    /// The words at the entry of `bb`: what every predecessor leaves, merged.
    fn words_start(&self, bb: BasicBlock, arr: Local, active: &mut HashSet<BasicBlock>) -> Words {
        if bb == START_BLOCK {
            return Words::new();
        }
        if let Some(w) = self.words_memo.borrow().get(&(arr, bb, false)) {
            return w.clone();
        }
        let doms = self.body.basic_blocks.dominators();
        active.insert(bb);
        let mut ends: Vec<(BasicBlock, Words)> = Vec::new();
        let mut looped = false;
        for &p in &self.body.basic_blocks.predecessors()[bb] {
            // diver: an irreducible cycle is cut where the walk first meets it.
            if active.contains(&p) || doms.dominates(bb, p) {
                looped = true;
                continue;
            }
            ends.push((p, self.words_end(p, arr, active)));
        }
        active.remove(&bb);
        let mut merged = Words::new();
        if let Some((_, first)) = ends.first() {
            for off in first.keys() {
                let Some(vals) = ends.iter().map(|(p, w)| w.get(off).map(|v| (*p, v))).collect::<Option<Vec<_>>>() else { continue };
                let same = |v: &Vec<(Vec<Cond>, String, Option<u64>)>| v.len() == 1 && v[0].1 == vals[0].1[0].1 && v[0].2 == vals[0].1[0].2;
                if vals.iter().all(|(_, v)| same(v)) {
                    merged.insert(*off, vec![(vec![], vals[0].1[0].1.clone(), vals[0].1[0].2)]);
                    continue;
                }
                // One entry per value: a value reached under several sets of
                // arms keeps the arms they share -- the outer ones, which
                // `conds_of` lists last.
                let mut entry: Vec<(Vec<Cond>, String, Option<u64>)> = Vec::new();
                for (p, v) in &vals {
                    let cp = self.conds_of(*p);
                    for (c, s, k) in v.iter() {
                        let c = if c.is_empty() { cp.clone() } else { c.clone() };
                        match entry.iter_mut().find(|(_, s2, k2)| s2 == s && k2 == k) {
                            Some((c2, ..)) => {
                                let n = c.iter().rev().zip(c2.iter().rev()).take_while(|(a, b)| a == b).count();
                                *c2 = c2[c2.len() - n..].to_vec();
                            }
                            None => entry.push((c, s.clone(), *k)),
                        }
                    }
                }
                merged.insert(*off, entry);
            }
        }
        if looped {
            // diver: a loop body's stores are forgotten, not read.
            let derived = self.derived_rc(arr);
            for (b, data) in self.body.basic_blocks.iter_enumerated() {
                if doms.dominates(bb, b) {
                    for st in &data.statements {
                        if let StatementKind::Assign(a) = &st.kind {
                            match self.frame_store_off(arr, &derived, &a.0) {
                                Some(Some(off)) => {
                                    merged.remove(&off);
                                }
                                Some(None) => merged.clear(),
                                None => {}
                            }
                        }
                    }
                    for r in self.call_writes(data, arr) {
                        Self::clobber(&mut merged, r);
                    }
                }
            }
        }
        self.words_memo.borrow_mut().insert((arr, bb, false), merged.clone());
        merged
    }

    /// The words at the end of `bb`, its terminator applied.
    fn words_end(&self, bb: BasicBlock, arr: Local, active: &mut HashSet<BasicBlock>) -> Words {
        if let Some(w) = self.words_memo.borrow().get(&(arr, bb, true)) {
            return w.clone();
        }
        let mut w = self.words_start(bb, arr, active);
        self.run_block(bb, usize::MAX, arr, &mut w);
        self.words_memo.borrow_mut().insert((arr, bb, true), w.clone());
        w
    }

    /// The locals that hold a pointer into `arr`, computed once.
    fn derived_rc(&self, arr: Local) -> Rc<HashSet<Local>> {
        if let Some(d) = self.derived_memo.borrow().get(&arr) {
            return d.clone();
        }
        let d = Rc::new(self.derived_from(arr));
        self.derived_memo.borrow_mut().insert(arr, d.clone());
        d
    }

    /// The offset a store into the frame writes (None when unknown); None
    /// when the store is elsewhere.
    fn frame_store_off(&self, arr: Local, derived: &HashSet<Local>, pl: &Place<'tcx>) -> Option<Option<u64>> {
        if pl.local == arr {
            return Some(match pl.projection.as_slice() {
                [PlaceElem::ConstantIndex { offset, .. }] => Some(offset * 8),
                _ => None,
            });
        }
        if matches!(pl.projection.as_slice(), [PlaceElem::Deref]) && derived.contains(&pl.local) {
            return Some(self.array_behind_at(&Operand::Copy(Place::from(pl.local)), 0).map(|(_, k)| k));
        }
        None
    }

    /// Apply the statements of `b` before `upto`, and its terminator when
    /// `upto` is past them all, to `words`.
    fn run_block(&self, b: BasicBlock, upto: usize, arr: Local, words: &mut Words) {
        let data = &self.body.basic_blocks[b];
        let derived = self.derived_rc(arr);
        for st in data.statements.iter().take(upto) {
            let StatementKind::Assign(a) = &st.kind else { continue };
            match self.frame_store(arr, &derived, a) {
                Some(Some((off, vs))) => {
                    words.insert(off, vs);
                }
                Some(None) => words.clear(),
                None => {}
            }
        }
        if upto <= data.statements.len() {
            return;
        }
        if let Some(enc) = self.encoder_words(data, arr) {
            for (off, v) in enc {
                words.insert(off, vec![(vec![], v.0, v.1)]);
            }
            return;
        }
        for r in self.call_writes(data, arr) {
            Self::clobber(words, r);
        }
    }

    /// A store into the frame: its offset and values (None at an unknown
    /// offset); None when the store is elsewhere.
    fn frame_store(&self, arr: Local, derived: &HashSet<Local>, a: &(Place<'tcx>, Rvalue<'tcx>)) -> Option<Option<(u64, Vec<(Vec<Cond>, String, Option<u64>)>)>> {
        let off = self.frame_store_off(arr, derived, &a.0)?;
        let vals = match &a.1 {
            // A local with a value per arm stores one per arm.
            Rvalue::Use(op) => match self.source_local(op).and_then(|l| self.shapes.get(&l)).filter(|v| v.len() > 1) {
                Some(v) => Some(v.iter().map(|(c, s)| (c.clone(), s.clone(), None)).collect()),
                None => self.key_shape(op).ok().map(|s| vec![(vec![], s, self.konst_u64(op))]),
            },
            rv => self.as_val_expr(rv).ok().map(|s| vec![(vec![], s, None)]),
        };
        Some(off.zip(vals))
    }

    /// The byte ranges a block's call may write into the frame: a pointer
    /// into it handed to a callee that writes through that parameter. The
    /// host's unpacks write exactly `len` Vals; a lifted callee, from the
    /// pointer on.
    fn call_writes(&self, data: &BasicBlockData<'tcx>, arr: Local) -> Vec<(u64, Option<u64>)> {
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
    }

    fn clobber(words: &mut Words, (k, end): (u64, Option<u64>)) {
        words.retain(|off, _| *off < k || end.is_some_and(|e| *off >= e));
    }

    /// What the SDK's small-symbol encoder writes into the frame it is
    /// handed, when its text is a literal: `Ok` at the pointer, the symbol
    /// a word on.
    fn encoder_words(&self, data: &BasicBlockData<'tcx>, arr: Local) -> Option<Vec<(u64, (String, Option<u64>))>> {
        let Some(Terminator { kind: TerminatorKind::Call { func, args, .. }, .. }) = &data.terminator else { return None };
        if !self.prev.encoders.contains(&self.callee_name(func)?) {
            return None;
        }
        let (out, text) = match &args[..] {
            [out, pos, len] => (out, self.spec.text_at(self.konst_u64(&pos.node)?, self.konst_u64(&len.node)?)?),
            // `(out, &&str)`: the text's position and length sit in rodata.
            [out, sref] => {
                let p = self.konst_u64(&sref.node)?;
                (out, self.spec.text_at(self.spec.u32_at(p)? as u64, self.spec.u32_at(p + 4)? as u64)?)
            }
            _ => return None,
        };
        let (x, k) = self.array_behind_at(&out.node, 0)?;
        if x != arr {
            return None;
        }
        let sym = match self.spec.union_case(&text) {
            Some(case) => format!("Symbol({text:?}) /* {case} */"),
            None => format!("Symbol({text:?})"),
        };
        Some(vec![(k, ("0".into(), Some(0))), (k + 8, (sym, None))])
    }

    /// A frame: an array of words, Vals or integers.
    /// A vec built from a frame with a length that is a constant per arm --
    /// a derive whose cases carry different payload counts, merged into one
    /// call: the vec's shape under each arm, from the words stored under it.
    pub(super) fn vec_arms(&self, bb: BasicBlock, arr: Local, base: u64, len: &Operand<'tcx>) -> Option<Vec<(Vec<Cond>, String)>> {
        let l = self.source_local(len)?;
        // The length local is assigned a `U32Val` constant in each arm,
        // possibly through a copy or a `Val(..)` of another local.
        let mut lens: Vec<(Vec<Cond>, u64)> = Vec::new();
        self.const_assigns(l, 0, &mut lens)?;
        if lens.is_empty() {
            return None;
        }
        let words = self.words_at(bb, self.body.basic_blocks[bb].statements.len(), arr);
        let mut out = Vec::new();
        for (c, k) in lens {
            let parts: Vec<String> = (0..k)
                .map(|j| {
                    let vs: Vec<String> = words
                        .get(&(base + 8 * j))
                        .map(|v| v.iter().filter(|(ec, ..)| ec.is_empty() || ec.ends_with(&c)).map(|(_, s, _)| s.clone()).collect())
                        .unwrap_or_default();
                    match vs.len() {
                        0 => "_".to_string(),
                        1 => vs[0].clone(),
                        _ => alternatives(vs),
                    }
                })
                .collect();
            out.push((c, self.vec_case(parts)));
        }
        Some(out)
    }

    /// Every `U32Val` constant assigned to `l` (through copies and `Val(..)`
    /// wrappers), with the arms of the block that assigns it; the zero a
    /// local starts at does not count. None when any assignment is not one.
    fn const_assigns(&self, l: Local, depth: u8, out: &mut Vec<(Vec<Cond>, u64)>) -> Option<()> {
        if depth > 4 {
            return None;
        }
        for (b, data) in self.body.basic_blocks.iter_enumerated() {
            for st in &data.statements {
                let StatementKind::Assign(a) = &st.kind else { continue };
                if a.0.as_local() != Some(l) {
                    continue;
                }
                let op = match &a.1 {
                    Rvalue::Use(op) => op,
                    Rvalue::Aggregate(k, fs) if matches!(**k, AggregateKind::Adt(d, ..) if d == self.env.val_def) => fs.iter().next()?,
                    _ => return None,
                };
                match op {
                    Operand::Constant(_) => match self.konst_u64(op) {
                        Some(k) if k & 0xff == 4 => out.push((self.conds_of(b), k >> 32)),
                        Some(_) => {}
                        None => return None,
                    },
                    Operand::Copy(p) | Operand::Move(p) => self.const_assigns(p.as_local()?, depth + 1, out)?,
                    _ => return None,
                }
            }
        }
        Some(())
    }

    pub(super) fn is_frame(&self, l: Local) -> bool {
        matches!(self.body.local_decls[l].ty.kind(), ty::Array(e, _) if *e == self.env.val || e.is_integral())
    }

    /// The length a host call is told, as a constant.
    pub(super) fn len_arg(&self, callee: &str, args: &[Operand<'tcx>]) -> Option<u64> {
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
    pub(super) fn range_shape(&self, bb: BasicBlock, arr: Local, first: u64, len: u64) -> Option<Vec<(String, Option<Local>)>> {
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
            // A parameter stored as a word is that parameter, not `Val(a1)`.
            let e = match src.filter(|l| (1..=self.body.arg_count).contains(&l.as_usize())) {
                Some(p) => self.local(p),
                None => self.as_val_expr(&a.1).ok()?,
            };
            out[k as usize] = Some((e, src));
        }
        out.into_iter().collect()
    }
}
