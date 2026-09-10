//! LLVM IR -> `rustc_middle::mir::Body`, in the `Built` phase.
//!
//! One MIR local per SSA value and parameter, typed with rustc's `Ty`; one
//! basic block per LLVM block, split at calls because MIR ends a block there;
//! phis become copies in an edge block; `%Val` is the `Val` ADT, its
//! constructor an aggregate and its payload a field projection; a
//! `StorageType` literal is an enum variant, a runtime one a call to
//! `core::intrinsics::transmute`, which rustc lowers to its own `Transmute`
//! cast; a frame is a `[u64; N]` local whose raw address is taken. Every LLVM
//! operation that has no MIR equivalent is an error, never a guess.
//!
//! The body is handed to rustc as the function's `mir_built`, so rustc
//! borrow-checks it, validates it after every pass and optimizes it exactly
//! as it would MIR of its own making.
use std::collections::HashMap;

use inkwell::attributes::{Attribute, AttributeLoc};
use inkwell::basic_block::BasicBlock as LBlock;
use inkwell::types::BasicTypeEnum;
use inkwell::values::{
    AnyValue, AsValueRef, BasicValueEnum, CallSiteValue, FunctionValue, InstructionOpcode, InstructionValue,
    Operand as LOperand, PhiValue,
};
use inkwell::IntPredicate;
use rustc_abi::{FieldIdx, Size, VariantIdx};
use rustc_hir::def::DefKind;
use rustc_hir::def_id::DefId;
use rustc_index::IndexVec;
use rustc_middle::mir::interpret::{Pointer, Scalar};
use rustc_middle::mir::*;
use rustc_middle::ty::{self, List, Ty, TyCtxt};
use rustc_span::{sym, Spanned, Symbol, DUMMY_SP};

type R<T> = Result<T, String>;

/// What the stub crate gave us: the ABI types and a DefId per function and
/// static, looked up by the Rust name `rs_name` produces.
pub struct Env<'tcx> {
    pub tcx: TyCtxt<'tcx>,
    pub val: Ty<'tcx>,
    pub val_def: DefId,
    pub storage: Ty<'tcx>,
    pub storage_def: DefId,
    pub u8p: Ty<'tcx>,
    pub transmute: DefId,
    pub fns: HashMap<String, DefId>,
    pub statics: HashMap<String, DefId>,
}

impl<'tcx> Env<'tcx> {
    pub fn new(tcx: TyCtxt<'tcx>) -> Self {
        let items = tcx.hir_crate_items(());
        let (mut fns, mut statics) = (HashMap::new(), HashMap::new());
        let (mut val_def, mut storage_def) = (None, None);
        let all = items.free_items().map(|i| i.owner_id.to_def_id()).chain(items.foreign_items().map(|i| i.owner_id.to_def_id()));
        for d in all {
            let kind = tcx.def_kind(d);
            if !matches!(kind, DefKind::Struct | DefKind::Enum | DefKind::Fn | DefKind::Static { .. }) {
                continue; // e.g. the injected prelude `use`, which has no name
            }
            let n = tcx.item_name(d).to_string();
            match kind {
                DefKind::Struct if n == "Val" => val_def = Some(d),
                DefKind::Enum if n == "StorageType" => storage_def = Some(d),
                DefKind::Fn => {
                    fns.insert(n, d);
                }
                DefKind::Static { .. } => {
                    statics.insert(n, d);
                }
                _ => {}
            }
        }
        let val_def = val_def.expect("stub defines Val");
        let storage_def = storage_def.expect("stub defines StorageType");
        Env {
            tcx,
            val: Ty::new_adt(tcx, tcx.adt_def(val_def), List::empty()),
            val_def,
            storage: Ty::new_adt(tcx, tcx.adt_def(storage_def), List::empty()),
            storage_def,
            u8p: Ty::new_mut_ptr(tcx, tcx.types.u8),
            transmute: tcx.get_diagnostic_item(sym::transmute).expect("core::intrinsics::transmute"),
            fns,
            statics,
        }
    }

    pub fn ty(&self, t: BasicTypeEnum) -> R<Ty<'tcx>> {
        let tcx = self.tcx;
        Ok(match t {
            BasicTypeEnum::IntType(i) => match i.get_bit_width() {
                1 => tcx.types.bool,
                8 => tcx.types.u8,
                16 => tcx.types.u16,
                32 => tcx.types.u32,
                64 => tcx.types.u64,
                w => return Err(format!("i{w} has no MIR type here")),
            },
            BasicTypeEnum::StructType(s) if s.get_name().map(|n| n.to_bytes() == b"Val").unwrap_or(false) => self.val,
            BasicTypeEnum::PointerType(_) => self.u8p,
            other => return Err(format!("no MIR type for {other:?}")),
        })
    }

    /// The function's return type: LLVM `noreturn` is Rust `!`.
    pub fn ret_ty(&self, f: FunctionValue) -> R<Ty<'tcx>> {
        if noreturn(f) {
            return Ok(self.tcx.types.never);
        }
        match f.get_type().get_return_type() {
            Some(t) => self.ty(t),
            None => Ok(self.tcx.types.unit),
        }
    }

    fn signed(&self, t: Ty<'tcx>) -> Ty<'tcx> {
        let tcx = self.tcx;
        match t.kind() {
            ty::Uint(ty::UintTy::U8) => tcx.types.i8,
            ty::Uint(ty::UintTy::U16) => tcx.types.i16,
            ty::Uint(ty::UintTy::U32) => tcx.types.i32,
            _ => tcx.types.i64,
        }
    }
}

pub fn noreturn(f: FunctionValue) -> bool {
    f.get_enum_attribute(AttributeLoc::Function, Attribute::get_named_enum_kind_id("noreturn")).is_some()
}

fn key(v: impl AsValueRef) -> usize {
    v.as_value_ref() as usize
}

fn insts(bb: LBlock) -> Vec<InstructionValue> {
    let mut v = Vec::new();
    let mut cur = bb.get_first_instruction();
    while let Some(i) = cur {
        v.push(i);
        cur = i.get_next_instruction();
    }
    v
}

fn callee_name(i: InstructionValue) -> Option<String> {
    let cs = CallSiteValue::try_from(i).ok()?;
    Some(cs.get_called_fn_value()?.get_name().to_string_lossy().into_owned())
}

struct B<'a, 'tcx> {
    env: &'a Env<'tcx>,
    locals: IndexVec<Local, LocalDecl<'tcx>>,
    map: HashMap<usize, Local>,
    blocks: IndexVec<BasicBlock, BasicBlockData<'tcx>>,
    bbmap: HashMap<usize, BasicBlock>,
    debug: Vec<VarDebugInfo<'tcx>>,
    si: SourceInfo,
}

type Stmts<'tcx> = Vec<Statement<'tcx>>;

impl<'a, 'tcx> B<'a, 'tcx> {
    fn tcx(&self) -> TyCtxt<'tcx> {
        self.env.tcx
    }

    fn temp(&mut self, ty: Ty<'tcx>) -> Local {
        self.locals.push(LocalDecl::new(ty, DUMMY_SP))
    }

    fn new_block(&mut self) -> BasicBlock {
        self.blocks.push(BasicBlockData::new(None, false))
    }

    fn assign(&self, st: &mut Stmts<'tcx>, place: Place<'tcx>, rv: Rvalue<'tcx>) {
        st.push(Statement::new(self.si, StatementKind::Assign(Box::new((place, rv)))));
    }

    /// End the current block with `kind`; nothing more can go in it.
    fn terminate(&mut self, cur: &mut Option<BasicBlock>, st: &mut Stmts<'tcx>, kind: TerminatorKind<'tcx>) {
        if let Some(b) = *cur {
            self.blocks[b].statements = std::mem::take(st);
            self.blocks[b].terminator = Some(Terminator { source_info: self.si, kind });
        }
        *cur = None;
    }

    /// A call ends a MIR block: emit it and continue in a fresh one, or in
    /// none if the callee never returns.
    fn call(
        &mut self,
        cur: &mut Option<BasicBlock>,
        st: &mut Stmts<'tcx>,
        func: Operand<'tcx>,
        args: Vec<Operand<'tcx>>,
        destination: Place<'tcx>,
        diverges: bool,
    ) {
        let next = if diverges { None } else { Some(self.new_block()) };
        let args = args.into_iter().map(|node| Spanned { node, span: DUMMY_SP }).collect();
        let kind = TerminatorKind::Call {
            func,
            args,
            destination,
            target: next,
            unwind: UnwindAction::Unreachable,
            call_source: CallSource::Normal,
            fn_span: DUMMY_SP,
        };
        self.terminate(cur, st, kind);
        *cur = next;
    }

    fn konst(&self, bits: u128, ty: Ty<'tcx>) -> Operand<'tcx> {
        let tcx = self.tcx();
        let scalar = if ty.is_bool() {
            Scalar::from_bool(bits != 0)
        } else if ty.is_raw_ptr() {
            Scalar::from_target_usize(bits as u64, &tcx)
        } else {
            let size = tcx
                .layout_of(ty::TypingEnv::fully_monomorphized().as_query_input(ty))
                .map(|l| l.size)
                .unwrap_or(Size::from_bits(64));
            Scalar::from_uint(bits, size)
        };
        Operand::Constant(Box::new(ConstOperand { span: DUMMY_SP, user_ty: None, const_: Const::from_scalar(tcx, scalar, ty) }))
    }

    /// The address of a wasm global, as rustc represents a static's address.
    fn static_ptr(&mut self, def_id: DefId, st: &mut Stmts<'tcx>) -> Operand<'tcx> {
        let tcx = self.tcx();
        let alloc = tcx.reserve_and_set_static_alloc(def_id);
        let ptr_ty = Ty::new_mut_ptr(tcx, tcx.types.u64);
        let ptr = Scalar::from_pointer(Pointer::new(alloc.into(), Size::ZERO), &tcx);
        let op = Operand::Constant(Box::new(ConstOperand { span: DUMMY_SP, user_ty: None, const_: Const::from_scalar(tcx, ptr, ptr_ty) }));
        self.cast(op, CastKind::PtrToPtr, self.env.u8p, st)
    }

    fn cast(&mut self, op: Operand<'tcx>, kind: CastKind, ty: Ty<'tcx>, st: &mut Stmts<'tcx>) -> Operand<'tcx> {
        let t = self.temp(ty);
        self.assign(st, Place::from(t), Rvalue::Cast(kind, op, ty));
        Operand::Copy(Place::from(t))
    }

    fn operand(&mut self, v: BasicValueEnum<'a>, st: &mut Stmts<'tcx>) -> R<Operand<'tcx>> {
        if let Some(&l) = self.map.get(&key(v)) {
            return Ok(Operand::Copy(Place::from(l)));
        }
        let ty = self.env.ty(v.get_type())?;
        match v {
            BasicValueEnum::IntValue(i) if i.is_constant_int() => {
                Ok(self.konst(i.get_zero_extended_constant().unwrap_or(0) as u128, ty))
            }
            BasicValueEnum::IntValue(i) if i.is_undef() => Ok(self.konst(0, ty)),
            BasicValueEnum::PointerValue(p) if p.is_null() => Ok(self.konst(0, ty)),
            BasicValueEnum::PointerValue(p) if p.is_const() => {
                if let Some(a) = const_addr(p) {
                    return Ok(self.konst(a as u128, ty));
                }
                let n = p.get_name().to_string_lossy().to_uppercase();
                match self.env.statics.get(&n).copied() {
                    Some(d) => Ok(self.static_ptr(d, st)),
                    None => Err(format!("unsupported constant pointer {}", p.print_to_string())),
                }
            }
            BasicValueEnum::StructValue(s) if s.is_const() => {
                let bits = match s.get_field_at_index(0) {
                    Some(BasicValueEnum::IntValue(i)) if i.is_constant_int() => i.get_zero_extended_constant().unwrap_or(0),
                    _ => 0, // zeroinitializer, undef, poison
                };
                let t = self.temp(self.env.val);
                let k = self.konst(bits as u128, self.tcx().types.u64);
                self.assign(st, Place::from(t), self.val_of(k));
                Ok(Operand::Copy(Place::from(t)))
            }
            other => Err(format!("unsupported operand {}", other.print_to_string())),
        }
    }

    fn val_of(&self, payload: Operand<'tcx>) -> Rvalue<'tcx> {
        let kind = AggregateKind::Adt(self.env.val_def, VariantIdx::ZERO, List::empty(), None, None);
        let mut fields = IndexVec::new();
        fields.push(payload);
        Rvalue::Aggregate(Box::new(kind), fields)
    }

    fn op(&mut self, i: InstructionValue<'a>, k: u32, st: &mut Stmts<'tcx>) -> R<Operand<'tcx>> {
        match i.get_operand(k) {
            Some(LOperand::Value(v)) => self.operand(v, st),
            _ => Err(format!("operand {k} of {} is not a value", i.print_to_string())),
        }
    }

    fn opty(&self, i: InstructionValue<'a>, k: u32) -> R<Ty<'tcx>> {
        match i.get_operand(k) {
            Some(LOperand::Value(v)) => self.env.ty(v.get_type()),
            _ => Err("operand is not a value".into()),
        }
    }

    fn target(&self, i: InstructionValue<'a>, k: u32) -> R<LBlock<'a>> {
        match i.get_operand(k) {
            Some(LOperand::Block(b)) => Ok(b),
            _ => Err("operand is not a block".into()),
        }
    }

    fn res(&self, i: InstructionValue<'a>) -> Place<'tcx> {
        Place::from(self.map[&key(i)])
    }

    fn res_ty(&self, i: InstructionValue<'a>) -> Ty<'tcx> {
        self.locals[self.map[&key(i)]].ty
    }

    /// `*(p as *mut ty)`, as a place. Every pointer the model carries is
    /// `*mut u8`, so a byte access needs no cast.
    fn deref(&mut self, p: Operand<'tcx>, ty: Ty<'tcx>, st: &mut Stmts<'tcx>) -> Place<'tcx> {
        let tcx = self.tcx();
        let byte = ty == tcx.types.u8;
        let place = match p {
            Operand::Copy(pl) | Operand::Move(pl) if byte => pl,
            p => {
                let pty = Ty::new_mut_ptr(tcx, ty);
                let t = self.temp(pty);
                let rv = if byte { Rvalue::Use(p) } else { Rvalue::Cast(CastKind::PtrToPtr, p, pty) };
                self.assign(st, Place::from(t), rv);
                Place::from(t)
            }
        };
        tcx.mk_place_deref(place)
    }

    /// The block for an edge `from -> to`: `to` itself, or a fresh block that
    /// performs `to`'s phi copies for this edge first.
    fn edge(&mut self, from: LBlock<'a>, to: LBlock<'a>) -> R<BasicBlock> {
        let mut st = Vec::new();
        for i in insts(to) {
            let Ok(phi) = PhiValue::try_from(i) else { break };
            for k in 0..phi.count_incoming() {
                if let Some((v, b)) = phi.get_incoming(k) {
                    if b == from {
                        let op = self.operand(v, &mut st)?;
                        let dst = self.res(i);
                        self.assign(&mut st, dst, Rvalue::Use(op));
                    }
                }
            }
        }
        let target = self.bbmap[&(to.as_mut_ptr() as usize)];
        if st.is_empty() {
            return Ok(target);
        }
        let e = self.new_block();
        self.blocks[e].statements = st;
        self.blocks[e].terminator = Some(Terminator { source_info: self.si, kind: TerminatorKind::Goto { target } });
        Ok(e)
    }

    fn binop(&mut self, i: InstructionValue<'a>, op: BinOp, signed: bool, st: &mut Stmts<'tcx>) -> R<()> {
        let (mut a, mut b) = (self.op(i, 0, st)?, self.op(i, 1, st)?);
        let ty = self.opty(i, 0)?;
        let sty = self.env.signed(ty);
        if signed {
            a = self.cast(a, CastKind::IntToInt, sty, st);
            b = self.cast(b, CastKind::IntToInt, sty, st);
        }
        let rv = Rvalue::BinaryOp(op, Box::new((a, b)));
        let dst = self.res(i);
        if signed && !matches!(op, BinOp::Lt | BinOp::Le | BinOp::Gt | BinOp::Ge | BinOp::Eq | BinOp::Ne) {
            // Back to the unsigned type the model carries.
            let t = self.temp(sty);
            self.assign(st, Place::from(t), rv);
            self.assign(st, dst, Rvalue::Cast(CastKind::IntToInt, Operand::Copy(Place::from(t)), ty));
        } else {
            self.assign(st, dst, rv);
        }
        Ok(())
    }

    /// An integer where the ABI says `StorageType`: `transmute::<u64, StorageType>`,
    /// the one conversion Rust has for it. rustc lowers the call to its own
    /// `Transmute` cast in runtime MIR.
    fn to_storage(&mut self, cur: &mut Option<BasicBlock>, st: &mut Stmts<'tcx>, op: Operand<'tcx>, from: Ty<'tcx>) -> Operand<'tcx> {
        let tcx = self.tcx();
        let t = self.temp(self.env.storage);
        let f = Operand::function_handle(tcx, self.env.transmute, [from.into(), self.env.storage.into()], DUMMY_SP);
        self.call(cur, st, f, vec![op], Place::from(t), false);
        Operand::Copy(Place::from(t))
    }

    fn block(&mut self, lb: LBlock<'a>) -> R<()> {
        let tcx = self.tcx();
        let mut cur = Some(self.bbmap[&(lb.as_mut_ptr() as usize)]);
        let mut st: Stmts<'tcx> = Vec::new();
        for i in insts(lb) {
            if cur.is_none() {
                break; // after a diverging call
            }
            use InstructionOpcode::*;
            match i.get_opcode() {
                Phi => {}
                Alloca => {
                    // A frame, as words: 8-aligned, so the naturally aligned
                    // accesses Rust-compiled wasm makes are aligned here too.
                    let bytes = match i.get_allocated_type() {
                        Ok(BasicTypeEnum::ArrayType(a)) => a.len() as u64,
                        Ok(BasicTypeEnum::IntType(t)) => (t.get_bit_width() / 8) as u64,
                        _ => return Err("alloca shape".into()),
                    };
                    let words = bytes.div_ceil(8).max(1);
                    let arr_ty = Ty::new_array(tcx, tcx.types.u64, words);
                    let arr = self.temp(arr_ty);
                    let zero = self.konst(0, tcx.types.u64);
                    self.assign(&mut st, Place::from(arr), Rvalue::Repeat(zero, ty::Const::from_target_usize(tcx, words)));
                    let raw = self.temp(Ty::new_mut_ptr(tcx, arr_ty));
                    self.assign(&mut st, Place::from(raw), Rvalue::RawPtr(RawPtrKind::Mut, Place::from(arr)));
                    let dst = self.res(i);
                    self.assign(&mut st, dst, Rvalue::Cast(CastKind::PtrToPtr, Operand::Copy(Place::from(raw)), self.env.u8p));
                }
                Load => {
                    let ty = self.res_ty(i);
                    let p = self.op(i, 0, &mut st)?;
                    let src = self.deref(p, ty, &mut st);
                    let dst = self.res(i);
                    self.assign(&mut st, dst, Rvalue::Use(Operand::Copy(src)));
                }
                Store => {
                    let v = self.op(i, 0, &mut st)?;
                    let ty = self.opty(i, 0)?;
                    let p = self.op(i, 1, &mut st)?;
                    let dst = self.deref(p, ty, &mut st);
                    self.assign(&mut st, dst, Rvalue::Use(v));
                }
                GetElementPtr => {
                    if i.get_num_operands() != 2 {
                        return Err(format!("gep shape: {}", i.print_to_string()));
                    }
                    let p = self.op(i, 0, &mut st)?;
                    let k = self.op(i, 1, &mut st)?;
                    let k = self.cast(k, CastKind::IntToInt, tcx.types.isize, &mut st);
                    let dst = self.res(i);
                    self.assign(&mut st, dst, Rvalue::BinaryOp(BinOp::Offset, Box::new((p, k))));
                }
                Add => self.binop(i, BinOp::Add, false, &mut st)?,
                Sub => self.binop(i, BinOp::Sub, false, &mut st)?,
                Mul => self.binop(i, BinOp::Mul, false, &mut st)?,
                UDiv => self.binop(i, BinOp::Div, false, &mut st)?,
                URem => self.binop(i, BinOp::Rem, false, &mut st)?,
                SDiv => self.binop(i, BinOp::Div, true, &mut st)?,
                SRem => self.binop(i, BinOp::Rem, true, &mut st)?,
                And => self.binop(i, BinOp::BitAnd, false, &mut st)?,
                Or => self.binop(i, BinOp::BitOr, false, &mut st)?,
                Xor => self.binop(i, BinOp::BitXor, false, &mut st)?,
                Shl => self.binop(i, BinOp::Shl, false, &mut st)?,
                LShr => self.binop(i, BinOp::Shr, false, &mut st)?,
                AShr => self.binop(i, BinOp::Shr, true, &mut st)?,
                ICmp => {
                    let p = i.get_icmp_predicate().ok_or("icmp without predicate")?;
                    let (op, signed) = match p {
                        IntPredicate::EQ => (BinOp::Eq, false),
                        IntPredicate::NE => (BinOp::Ne, false),
                        IntPredicate::UGT => (BinOp::Gt, false),
                        IntPredicate::UGE => (BinOp::Ge, false),
                        IntPredicate::ULT => (BinOp::Lt, false),
                        IntPredicate::ULE => (BinOp::Le, false),
                        IntPredicate::SGT => (BinOp::Gt, true),
                        IntPredicate::SGE => (BinOp::Ge, true),
                        IntPredicate::SLT => (BinOp::Lt, true),
                        IntPredicate::SLE => (BinOp::Le, true),
                    };
                    self.binop(i, op, signed, &mut st)?;
                }
                // MIR has no int -> bool cast: `trunc to i1` is the low bit.
                Trunc if self.res_ty(i).is_bool() => {
                    let a = self.op(i, 0, &mut st)?;
                    let from = self.opty(i, 0)?;
                    let one = self.konst(1, from);
                    let low = self.temp(from);
                    self.assign(&mut st, Place::from(low), Rvalue::BinaryOp(BinOp::BitAnd, Box::new((a, one))));
                    let zero = self.konst(0, from);
                    let dst = self.res(i);
                    self.assign(&mut st, dst, Rvalue::BinaryOp(BinOp::Ne, Box::new((Operand::Copy(Place::from(low)), zero))));
                }
                ZExt | Trunc => {
                    let a = self.op(i, 0, &mut st)?;
                    let (dst, ty) = (self.res(i), self.res_ty(i));
                    self.assign(&mut st, dst, Rvalue::Cast(CastKind::IntToInt, a, ty));
                }
                SExt => {
                    let a = self.op(i, 0, &mut st)?;
                    let from = self.opty(i, 0)?;
                    let (dst, ty) = (self.res(i), self.res_ty(i));
                    if from.is_bool() {
                        // sext i1: all ones or zero, i.e. -(b as iN).
                        let sty = self.env.signed(ty);
                        let z = self.cast(a, CastKind::IntToInt, sty, &mut st);
                        let neg = self.temp(sty);
                        self.assign(&mut st, Place::from(neg), Rvalue::UnaryOp(UnOp::Neg, z));
                        self.assign(&mut st, dst, Rvalue::Cast(CastKind::IntToInt, Operand::Copy(Place::from(neg)), ty));
                    } else {
                        let s = self.env.signed(from);
                        let a = self.cast(a, CastKind::IntToInt, s, &mut st);
                        self.assign(&mut st, dst, Rvalue::Cast(CastKind::IntToInt, a, ty));
                    }
                }
                PtrToInt => {
                    let p = self.op(i, 0, &mut st)?;
                    let u = self.cast(p, CastKind::PointerExposeProvenance, tcx.types.usize, &mut st);
                    let (dst, ty) = (self.res(i), self.res_ty(i));
                    self.assign(&mut st, dst, Rvalue::Cast(CastKind::IntToInt, u, ty));
                }
                IntToPtr => {
                    let a = self.op(i, 0, &mut st)?;
                    let u = self.cast(a, CastKind::IntToInt, tcx.types.usize, &mut st);
                    let dst = self.res(i);
                    self.assign(&mut st, dst, Rvalue::Cast(CastKind::PointerWithExposedProvenance, u, self.env.u8p));
                }
                BitCast | Freeze => {
                    let a = self.op(i, 0, &mut st)?;
                    let dst = self.res(i);
                    self.assign(&mut st, dst, Rvalue::Use(a));
                }
                Select => {
                    let c = self.op(i, 0, &mut st)?;
                    let (a, b) = (self.op(i, 1, &mut st)?, self.op(i, 2, &mut st)?);
                    let (then_bb, else_bb, join) = (self.new_block(), self.new_block(), self.new_block());
                    let kind = TerminatorKind::SwitchInt { discr: c, targets: SwitchTargets::static_if(0, else_bb, then_bb) };
                    self.terminate(&mut cur, &mut st, kind);
                    let dst = self.res(i);
                    for (bb, v) in [(then_bb, a), (else_bb, b)] {
                        let mut s = Vec::new();
                        self.assign(&mut s, dst, Rvalue::Use(v));
                        self.blocks[bb].statements = s;
                        self.blocks[bb].terminator = Some(Terminator { source_info: self.si, kind: TerminatorKind::Goto { target: join } });
                    }
                    cur = Some(join);
                }
                Call => {
                    let name = callee_name(i).ok_or("indirect call")?;
                    let cs = CallSiteValue::try_from(i).map_err(|_| "call")?;
                    let nargs = cs.count_arguments();
                    match name.as_str() {
                        n if n.starts_with("llvm.lifetime") || n == "llvm.assume" => {}
                        "soroban.val.from_payload" => {
                            let a = self.op(i, 0, &mut st)?;
                            let dst = self.res(i);
                            let rv = self.val_of(a);
                            self.assign(&mut st, dst, rv);
                        }
                        "soroban.val.payload" => {
                            let a = self.op(i, 0, &mut st)?;
                            let place = match a {
                                Operand::Copy(p) | Operand::Move(p) => p,
                                _ => return Err("payload of a constant".into()),
                            };
                            let field = tcx.mk_place_field(place, FieldIdx::ZERO, tcx.types.u64);
                            let dst = self.res(i);
                            self.assign(&mut st, dst, Rvalue::Use(Operand::Copy(field)));
                        }
                        "soroban.storage_type" => {
                            let lit = match i.get_operand(0) {
                                Some(LOperand::Value(BasicValueEnum::IntValue(v))) if v.is_constant_int() => v.get_zero_extended_constant(),
                                _ => None,
                            };
                            let dst = self.res(i);
                            match lit {
                                Some(c @ 0..=2) => {
                                    let kind = AggregateKind::Adt(self.env.storage_def, VariantIdx::from_u32(c as u32), List::empty(), None, None);
                                    self.assign(&mut st, dst, Rvalue::Aggregate(Box::new(kind), IndexVec::new()));
                                }
                                _ => {
                                    let a = self.op(i, 0, &mut st)?;
                                    let from = self.opty(i, 0)?;
                                    let v = self.to_storage(&mut cur, &mut st, a, from);
                                    self.assign(&mut st, dst, Rvalue::Use(v));
                                }
                            }
                        }
                        _ => {
                            let rname = crate::rs_name(&name);
                            let def_id = *self.env.fns.get(&rname).ok_or_else(|| format!("no declaration for {name}"))?;
                            let fsig = tcx.fn_sig(def_id).instantiate_identity().skip_binder();
                            let mut args = Vec::new();
                            for k in 0..nargs {
                                let a = self.op(i, k, &mut st)?;
                                let from = match &a {
                                    Operand::Copy(p) | Operand::Move(p) => p.ty(&self.locals, tcx).ty,
                                    Operand::Constant(c) => c.const_.ty(),
                                    _ => self.opty(i, k)?,
                                };
                                let to = *fsig.inputs().get(k as usize).ok_or("arity")?;
                                let a = if from == to {
                                    a
                                } else if to == self.env.storage && from.is_integral() {
                                    self.to_storage(&mut cur, &mut st, a, from)
                                } else {
                                    return Err(format!("argument of type {from} where {to} is declared"));
                                };
                                args.push(a);
                            }
                            let destination = if self.map.contains_key(&key(i)) {
                                self.res(i)
                            } else {
                                Place::from(self.temp(fsig.output()))
                            };
                            let f = Operand::function_handle(tcx, def_id, [], DUMMY_SP);
                            self.call(&mut cur, &mut st, f, args, destination, fsig.output().is_never());
                        }
                    }
                }
                Return => {
                    if i.get_num_operands() == 1 {
                        let v = self.op(i, 0, &mut st)?;
                        self.assign(&mut st, Place::from(Local::ZERO), Rvalue::Use(v));
                    }
                    self.terminate(&mut cur, &mut st, TerminatorKind::Return);
                }
                Unreachable => self.terminate(&mut cur, &mut st, TerminatorKind::Unreachable),
                // LLVM stores a conditional branch as [cond, false, true].
                Br if i.get_num_operands() == 3 => {
                    let c = self.op(i, 0, &mut st)?;
                    let (f, t) = (self.target(i, 1)?, self.target(i, 2)?);
                    let (fb, tb) = (self.edge(lb, f)?, self.edge(lb, t)?);
                    let kind = TerminatorKind::SwitchInt { discr: c, targets: SwitchTargets::static_if(0, fb, tb) };
                    self.terminate(&mut cur, &mut st, kind);
                }
                Br => {
                    let t = self.target(i, 0)?;
                    let target = self.edge(lb, t)?;
                    self.terminate(&mut cur, &mut st, TerminatorKind::Goto { target });
                }
                Switch => {
                    let d = self.op(i, 0, &mut st)?;
                    let otherwise = self.edge(lb, self.target(i, 1)?)?;
                    let mut cases = Vec::new();
                    let mut k = 2;
                    while k + 1 < i.get_num_operands() {
                        let Some(LOperand::Value(BasicValueEnum::IntValue(v))) = i.get_operand(k) else { return Err("switch case".into()) };
                        let val = v.get_zero_extended_constant().ok_or("switch case value")? as u128;
                        let t = self.target(i, k + 1)?;
                        cases.push((val, self.edge(lb, t)?));
                        k += 2;
                    }
                    let kind = TerminatorKind::SwitchInt { discr: d, targets: SwitchTargets::new(cases.into_iter(), otherwise) };
                    self.terminate(&mut cur, &mut st, kind);
                }
                op => return Err(format!("unsupported instruction {op:?}: {}", i.print_to_string())),
            }
        }
        // A block that fell off its end: only dead code does that.
        self.terminate(&mut cur, &mut st, TerminatorKind::Unreachable);
        Ok(())
    }
}

pub fn build<'a, 'tcx>(env: &'a Env<'tcx>, f: FunctionValue<'a>, def_id: DefId) -> R<Body<'tcx>> {
    let tcx = env.tcx;
    let si = SourceInfo::outermost(DUMMY_SP);
    let mut b = B { env, locals: IndexVec::new(), map: HashMap::new(), blocks: IndexVec::new(), bbmap: HashMap::new(), debug: Vec::new(), si };
    // _0, the parameters, then one local per SSA value.
    b.locals.push(LocalDecl::new(env.ret_ty(f)?, DUMMY_SP));
    for (n, p) in f.get_params().iter().enumerate() {
        let l = b.locals.push(LocalDecl::new(env.ty(p.get_type())?, DUMMY_SP));
        b.map.insert(key(*p), l);
        b.debug.push(VarDebugInfo {
            name: Symbol::intern(&format!("a{n}")),
            source_info: si,
            composite: None,
            value: VarDebugInfoContents::Place(Place::from(l)),
            argument_index: Some(n as u16 + 1),
        });
    }
    let arg_count = f.count_params() as usize;
    for lb in f.get_basic_blocks() {
        let mb = b.new_block();
        b.bbmap.insert(lb.as_mut_ptr() as usize, mb);
        for i in insts(lb) {
            let Ok(bt) = BasicTypeEnum::try_from(i.get_type()) else { continue };
            let ty = if callee_name(i).as_deref() == Some("soroban.storage_type") { env.storage } else { env.ty(bt)? };
            let l = b.locals.push(LocalDecl::new(ty, DUMMY_SP));
            b.map.insert(key(i), l);
            if let Some(n) = i.get_name().and_then(|n| n.to_str().ok()).filter(|n| !n.is_empty()) {
                b.debug.push(VarDebugInfo {
                    name: Symbol::intern(n),
                    source_info: si,
                    composite: None,
                    value: VarDebugInfoContents::Place(Place::from(l)),
                    argument_index: None,
                });
            }
        }
    }
    for lb in f.get_basic_blocks() {
        b.block(lb)?;
    }
    // A lint root lets rustc's MIR lints report against this function rather
    // than panic on a scope without one.
    let lint_root = tcx.local_def_id_to_hir_id(def_id.expect_local());
    let mut scopes: IndexVec<SourceScope, SourceScopeData<'tcx>> = IndexVec::new();
    scopes.push(SourceScopeData {
        span: DUMMY_SP,
        parent_scope: None,
        inlined: None,
        inlined_parent_scope: None,
        local_data: ClearCrossCrate::Set(SourceScopeLocalData { lint_root }),
    });
    Ok(Body::new(MirSource::item(def_id), b.blocks, scopes, b.locals, IndexVec::new(), arg_count, b.debug, DUMMY_SP, None, None))
}

/// `inttoptr (i64 K to ptr)` as a constant expression -> K.
fn const_addr(p: inkwell::values::PointerValue) -> Option<u64> {
    use inkwell::llvm_sys::core::*;
    use inkwell::llvm_sys::LLVMOpcode;
    unsafe {
        let r = p.as_value_ref();
        if LLVMIsAConstantExpr(r).is_null() || LLVMGetConstOpcode(r) != LLVMOpcode::LLVMIntToPtr {
            return None;
        }
        let k = LLVMGetOperand(r, 0);
        (!LLVMIsAConstantInt(k).is_null()).then(|| LLVMConstIntGetZExtValue(k))
    }
}
