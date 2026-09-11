//! Values: locals, places, constants and rvalues as Rust; Val payloads, tags, enums.
use rustc_middle::mir::interpret::{GlobalAlloc, Scalar};
use rustc_middle::mir::*;
use rustc_middle::ty::{self};

use super::*;

impl<'a, 'tcx> Fn_<'a, 'tcx> {
    /// The Rust type a local is declared with: `Val` for a payload local,
    /// `[Val; N]` for a frame the host reads Vals from.
    pub(super) fn local_ty(&self, l: Local) -> String {
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
    pub(super) fn val_source(&self, o: &Operand<'tcx>) -> Option<Local> {
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
    pub(super) fn source_local(&self, o: &Operand<'tcx>) -> Option<Local> {
        self.val_source(o).or_else(|| match o {
            Operand::Copy(p) | Operand::Move(p) => p.as_local(),
            _ => None,
        })
    }

    pub(super) fn line(&mut self, s: impl Into<String>) {
        self.out.push((self.depth, s.into()));
    }

    pub(super) fn raw_name(&self, l: Local) -> String {
        self.names.get(&l).cloned().unwrap_or_else(|| format!("_{}", l.as_usize()))
    }

    pub(super) fn local(&self, l: Local) -> String {
        if let Some((e, _)) = self.folded.get(&l) {
            return e.clone();
        }
        self.raw_name(l)
    }

    pub(super) fn place(&self, p: &Place<'tcx>) -> String {
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

    pub(super) fn konst(&self, c: &ConstOperand<'tcx>) -> R<String> {
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

    pub(super) fn operand(&self, o: &Operand<'tcx>) -> R<String> {
        match o {
            // A slot of a Val frame read as the integer it also is.
            Operand::Copy(p) | Operand::Move(p) if self.is_val_slot(p) => Ok(format!("{}.0", self.place(p))),
            Operand::Copy(p) | Operand::Move(p) => Ok(self.place(p)),
            Operand::Constant(c) => self.konst(c),
            Operand::RuntimeChecks(_) => Err("runtime-checks operand".into()),
        }
    }

    /// Display names of this function's parameters, in order.
    pub(super) fn param_names(&self) -> Vec<String> {
        self.body.args_iter().map(|l| self.local(l)).collect()
    }

    pub(super) fn rvalue(&self, rv: &Rvalue<'tcx>) -> R<String> {
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
                                // The tag consts are u64; an i32-wide tag compares as u32.
                                b = if ab.0.ty(&self.body.local_decls, self.tcx) == self.tcx.types.u32 { format!("Tag::{n} as u32") } else { format!("Tag::{n}") };
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
    pub(super) fn folded_rv(&self, o: &Operand<'tcx>) -> Option<&Rvalue<'tcx>> {
        match o {
            Operand::Copy(p) | Operand::Move(p) => self.folded.get(&p.as_local()?).map(|(_, rv)| rv),
            _ => None,
        }
    }

    /// Is this place a slot of a frame the host reads Vals from?
    pub(super) fn is_val_slot(&self, pl: &Place<'tcx>) -> bool {
        self.val_arrays.contains_key(&pl.local) && matches!(pl.projection.as_slice(), [PlaceElem::ConstantIndex { .. }])
    }

    /// The right-hand side of an assignment as Rust. A destination that holds
    /// a Val -- a payload local, a Val frame slot -- gets the value as a Val.
    pub(super) fn assign_expr(&self, pl: &Place<'tcx>, rv: &Rvalue<'tcx>) -> R<String> {
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
    pub(super) fn val_of_payload_place(&self, p: &Place<'tcx>) -> Option<String> {
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
    pub(super) fn as_val_expr(&self, rv: &Rvalue<'tcx>) -> R<String> {
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
    pub(super) fn val_of_expr(&self, rv: &Rvalue<'tcx>) -> R<String> {
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
    pub(super) fn val_str(&self, bits: u64) -> String {
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
    pub(super) fn def_of(&self, o: &Operand<'tcx>) -> Option<&Rvalue<'tcx>> {
        let l = match o {
            Operand::Copy(p) | Operand::Move(p) => p.as_local()?,
            _ => return None,
        };
        self.folded.get(&l).map(|(_, rv)| rv).or_else(|| self.single_def.get(&l))
    }

    /// If this operand is the payload of an exported parameter (`param.0`,
    /// possibly through a copy), that parameter's index.
    pub(super) fn payload_of_param(&self, o: &Operand<'tcx>) -> Option<usize> {
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
    pub(super) fn enum_of(&self, o: &Operand<'tcx>) -> Option<&str> {
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
    pub(super) fn is_tag(&self, o: &Operand<'tcx>) -> bool {
        let rv = match o {
            Operand::Copy(p) | Operand::Move(p) => p.as_local().and_then(|l| self.folded.get(&l).map(|(_, rv)| rv).or_else(|| self.single_def.get(&l))),
            _ => None,
        };
        matches!(rv, Some(Rvalue::BinaryOp(BinOp::BitAnd, ab)) if self.konst_u64(&ab.1) == Some(0xff))
    }

    pub(super) fn konst_u64(&self, o: &Operand<'tcx>) -> Option<u64> {
        match o {
            Operand::Constant(c) => c.const_.try_to_scalar_int().map(|i| i.to_bits(i.size()) as u64),
            _ => None,
        }
    }
}
