//! Frames: Val arrays, literal arrays, words read through pointer parameters and the arms they decide.
use std::collections::{HashMap, HashSet};
use rustc_middle::mir::*;
use rustc_middle::ty::{self};

use super::*;

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
    /// overwritten -- from that pointer's offset on. diver: a callee
    /// writing below the pointer it was given is not Rust; not considered.
    pub(super) fn frame_words(&self, bb: BasicBlock, o: &Operand<'tcx>) -> HashMap<u64, (String, Option<u64>)> {
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
            out[k as usize] = Some((self.as_val_expr(&a.1).ok()?, src));
        }
        out.into_iter().collect()
    }
}
