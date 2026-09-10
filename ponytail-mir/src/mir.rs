//! LLVM IR -> `rustc_middle::mir::Body`, in the `Built` phase.
//!
//! One MIR local per SSA value and parameter, typed with rustc's `Ty`; one
//! basic block per LLVM block, split at calls because MIR ends a block there;
//! phis become copies in an edge block; `%Val` is the `Val` ADT, its
//! constructor an aggregate and its payload a field projection; a
//! `StorageType` literal is an enum variant, a runtime one a call to
//! `core::intrinsics::transmute`, which rustc lowers to its own `Transmute`
//! cast; a frame is a `[u64; N]` local, its slots array elements and its
//! address `&raw mut`. Parameters and returns take the types `infer` found
//! for them -- `*mut u8`, `Val`, `StorageType` or `u64` -- and every crossing
//! between those and the model's integers is an explicit cast or projection.
//! Every LLVM operation that has no MIR equivalent is an error, never a guess.
//!
//! The body is handed to rustc as the function's `mir_built`, so rustc
//! borrow-checks it, validates it after every pass and optimizes it exactly
//! as it would MIR of its own making.
use std::collections::HashMap;

use inkwell::attributes::{Attribute, AttributeLoc};
use inkwell::basic_block::BasicBlock as LBlock;
use inkwell::types::BasicTypeEnum;
use inkwell::values::{
    AnyValue, AsValueRef, BasicValue, BasicValueEnum, CallSiteValue, FunctionValue, InstructionOpcode,
    InstructionValue, Operand as LOperand, PhiValue,
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

use crate::infer::{PTy, Sigs};

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

    /// The MIR type of an inferred parameter or return type.
    pub fn pty(&self, t: PTy) -> Ty<'tcx> {
        match t {
            PTy::Int => self.tcx.types.u64,
            PTy::Ptr => self.u8p,
            PTy::Val => self.val,
            PTy::Storage => self.storage,
        }
    }

    /// The inferred kind a MIR type stands for.
    fn kind_of_ty(&self, t: Ty<'tcx>) -> PTy {
        if t == self.val {
            PTy::Val
        } else if t == self.storage {
            PTy::Storage
        } else if t.is_raw_ptr() {
            PTy::Ptr
        } else {
            PTy::Int
        }
    }

    /// The function's return type: LLVM `noreturn` is Rust `!`.
    pub fn ret_ty(&self, f: FunctionValue, sigs: &Sigs) -> R<Ty<'tcx>> {
        if noreturn(f) {
            return Ok(self.tcx.types.never);
        }
        let name = f.get_name().to_string_lossy().into_owned();
        match (f.get_type().get_return_type(), sigs.ret(&name)) {
            (None, _) => Ok(self.tcx.types.unit),
            (Some(_), Some(k)) => Ok(self.pty(k)),
            (Some(t), None) => self.ty(t),
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

fn value_operand<'a>(i: InstructionValue<'a>, k: u32) -> Option<BasicValueEnum<'a>> {
    match i.get_operand(k) {
        Some(LOperand::Value(v)) => Some(v),
        _ => None,
    }
}

fn const_of(v: BasicValueEnum) -> Option<u64> {
    match v {
        BasicValueEnum::IntValue(i) if i.is_constant_int() => i.get_zero_extended_constant(),
        _ => None,
    }
}

struct B<'a, 'tcx> {
    env: &'a Env<'tcx>,
    sigs: &'a Sigs,
    locals: IndexVec<Local, LocalDecl<'tcx>>,
    map: HashMap<usize, Local>,
    /// Locals whose MIR type is not the model's integer: inferred parameters
    /// and results of calls to functions with an inferred return type.
    kinds: HashMap<Local, PTy>,
    /// Frame allocas: the `[u64; N]` local and N.
    frames: HashMap<usize, (Local, u64)>,
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

    /// The place an operand denotes, copying a constant into a temp if needed.
    fn as_place(&mut self, op: Operand<'tcx>, ty: Ty<'tcx>, st: &mut Stmts<'tcx>) -> Place<'tcx> {
        match op {
            Operand::Copy(p) | Operand::Move(p) => p,
            other => {
                let t = self.temp(ty);
                self.assign(st, Place::from(t), Rvalue::Use(other));
                Place::from(t)
            }
        }
    }

    /// `op`, of inferred kind `from`, as the model's `u64`.
    fn to_int(&mut self, op: Operand<'tcx>, from: PTy, st: &mut Stmts<'tcx>) -> Operand<'tcx> {
        let tcx = self.tcx();
        match from {
            PTy::Int => op,
            PTy::Ptr => self.cast(op, CastKind::PointerExposeProvenance, tcx.types.u64, st),
            PTy::Val => {
                let p = self.as_place(op, self.env.val, st);
                Operand::Copy(tcx.mk_place_field(p, FieldIdx::ZERO, tcx.types.u64))
            }
            PTy::Storage => {
                let p = self.as_place(op, self.env.storage, st);
                let t = self.temp(tcx.types.u64);
                self.assign(st, Place::from(t), Rvalue::Discriminant(p));
                Operand::Copy(Place::from(t))
            }
        }
    }

    /// `op`, of kind `from`, as kind `to`. Every crossing is one explicit
    /// cast or projection; an integer becoming a StorageType is the one that
    /// needs a call (`transmute`), which ends the block.
    fn coerce(&mut self, cur: &mut Option<BasicBlock>, st: &mut Stmts<'tcx>, op: Operand<'tcx>, from: PTy, to: PTy) -> Operand<'tcx> {
        if from == to {
            return op;
        }
        let tcx = self.tcx();
        let i = self.to_int(op, from, st);
        match to {
            PTy::Int => i,
            PTy::Ptr => {
                let u = self.cast(i, CastKind::IntToInt, tcx.types.usize, st);
                self.cast(u, CastKind::PointerWithExposedProvenance, self.env.u8p, st)
            }
            PTy::Val => {
                let t = self.temp(self.env.val);
                let rv = self.val_of(i);
                self.assign(st, Place::from(t), rv);
                Operand::Copy(Place::from(t))
            }
            PTy::Storage => {
                let t = self.temp(self.env.storage);
                let f = Operand::function_handle(tcx, self.env.transmute, [tcx.types.u64.into(), self.env.storage.into()], DUMMY_SP);
                self.call(cur, st, f, vec![i], Place::from(t), false);
                Operand::Copy(Place::from(t))
            }
        }
    }

    /// The inferred kind of an LLVM value: a refined local's, or its type's.
    fn kind_of(&self, v: BasicValueEnum<'a>) -> R<PTy> {
        if let Some(l) = self.map.get(&key(v)) {
            if let Some(k) = self.kinds.get(l) {
                return Ok(*k);
            }
            return Ok(self.env.kind_of_ty(self.locals[*l].ty));
        }
        Ok(self.env.kind_of_ty(self.env.ty(v.get_type())?))
    }

    /// An LLVM value as a MIR operand in its own type, with that type's kind.
    fn raw(&mut self, v: BasicValueEnum<'a>, st: &mut Stmts<'tcx>) -> R<(Operand<'tcx>, PTy)> {
        if let Some(&l) = self.map.get(&key(v)) {
            let k = self.kinds.get(&l).copied().unwrap_or_else(|| self.env.kind_of_ty(self.locals[l].ty));
            return Ok((Operand::Copy(Place::from(l)), k));
        }
        let ty = self.env.ty(v.get_type())?;
        let op = match v {
            BasicValueEnum::IntValue(i) if i.is_constant_int() => self.konst(i.get_zero_extended_constant().unwrap_or(0) as u128, ty),
            BasicValueEnum::IntValue(i) if i.is_undef() => self.konst(0, ty),
            BasicValueEnum::PointerValue(p) if p.is_null() => self.konst(0, ty),
            BasicValueEnum::PointerValue(p) if p.is_const() => {
                if let Some(a) = const_addr(p) {
                    self.konst(a as u128, ty)
                } else {
                    let n = p.get_name().to_string_lossy().to_uppercase();
                    match self.env.statics.get(&n).copied() {
                        Some(d) => self.static_ptr(d, st),
                        None => return Err(format!("unsupported constant pointer {}", p.print_to_string())),
                    }
                }
            }
            BasicValueEnum::StructValue(s) if s.is_const() => {
                let bits = match s.get_field_at_index(0) {
                    Some(BasicValueEnum::IntValue(i)) if i.is_constant_int() => i.get_zero_extended_constant().unwrap_or(0),
                    _ => 0, // zeroinitializer, undef, poison
                };
                let t = self.temp(self.env.val);
                let k = self.konst(bits as u128, self.tcx().types.u64);
                let rv = self.val_of(k);
                self.assign(st, Place::from(t), rv);
                Operand::Copy(Place::from(t))
            }
            other => return Err(format!("unsupported operand {}", other.print_to_string())),
        };
        Ok((op, self.env.kind_of_ty(ty)))
    }

    /// An LLVM value as the model's integer, or as itself when it is not one
    /// of the four inferred kinds (`%Val`, bool, narrow ints).
    fn operand(&mut self, v: BasicValueEnum<'a>, st: &mut Stmts<'tcx>) -> R<Operand<'tcx>> {
        let (op, kind) = self.raw(v, st)?;
        let refined = self.map.get(&key(v)).is_some_and(|l| self.kinds.contains_key(l));
        Ok(if refined { self.to_int(op, kind, st) } else { op })
    }

    fn val_of(&self, payload: Operand<'tcx>) -> Rvalue<'tcx> {
        let kind = AggregateKind::Adt(self.env.val_def, VariantIdx::ZERO, List::empty(), None, None);
        let mut fields = IndexVec::new();
        fields.push(payload);
        Rvalue::Aggregate(Box::new(kind), fields)
    }

    fn op(&mut self, i: InstructionValue<'a>, k: u32, st: &mut Stmts<'tcx>) -> R<Operand<'tcx>> {
        match value_operand(i, k) {
            Some(v) => self.operand(v, st),
            None => Err(format!("operand {k} of {} is not a value", i.print_to_string())),
        }
    }

    fn opty(&self, i: InstructionValue<'a>, k: u32) -> R<Ty<'tcx>> {
        match value_operand(i, k) {
            Some(v) => self.env.ty(v.get_type()),
            None => Err("operand is not a value".into()),
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

    /// A frame slot named by an address operand: the alloca itself, or a
    /// constant `gep` off it, when the access is a whole aligned word.
    fn frame_slot(&self, addr: BasicValueEnum<'a>, width: Ty<'tcx>) -> Option<Place<'tcx>> {
        if width != self.tcx().types.u64 {
            return None;
        }
        let i = addr.as_instruction_value()?;
        let (base, off) = match i.get_opcode() {
            InstructionOpcode::Alloca => (i, 0),
            InstructionOpcode::GetElementPtr if i.get_num_operands() == 2 => {
                let b = value_operand(i, 0)?.as_instruction_value()?;
                (b, const_of(value_operand(i, 1)?)?)
            }
            _ => return None,
        };
        let (arr, words) = *self.frames.get(&key(base))?;
        if off % 8 != 0 || off / 8 >= words {
            return None;
        }
        let elem = PlaceElem::ConstantIndex { offset: off / 8, min_length: words, from_end: false };
        Some(Place::from(arr).project_deeper(&[elem], self.tcx()))
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

    /// The pointer operand of an `inttoptr`: a pointer-typed value stays a
    /// pointer, `p + k` off one is an offset, anything else is exposed.
    fn addr(&mut self, cur: &mut Option<BasicBlock>, st: &mut Stmts<'tcx>, src: BasicValueEnum<'a>) -> R<Operand<'tcx>> {
        let tcx = self.tcx();
        let (op, kind) = self.raw(src, st)?;
        if kind == PTy::Ptr {
            return Ok(op);
        }
        if let Some(add) = src.as_instruction_value().filter(|i| i.get_opcode() == InstructionOpcode::Add) {
            for (pk, ok) in [(0, 1), (1, 0)] {
                let Some(pv) = value_operand(add, pk) else { continue };
                if self.kind_of(pv)? != PTy::Ptr {
                    continue;
                }
                let (p, _) = self.raw(pv, st)?;
                let k = self.op(add, ok, st)?;
                let k = self.cast(k, CastKind::IntToInt, tcx.types.isize, st);
                let t = self.temp(self.env.u8p);
                self.assign(st, Place::from(t), Rvalue::BinaryOp(BinOp::Offset, Box::new((p, k))));
                return Ok(Operand::Copy(Place::from(t)));
            }
        }
        Ok(self.coerce(cur, st, op, kind, PTy::Ptr))
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
                    self.frames.insert(key(i), (arr, words));
                    let zero = self.konst(0, tcx.types.u64);
                    self.assign(&mut st, Place::from(arr), Rvalue::Repeat(zero, ty::Const::from_target_usize(tcx, words)));
                    let raw = self.temp(Ty::new_mut_ptr(tcx, arr_ty));
                    self.assign(&mut st, Place::from(raw), Rvalue::RawPtr(RawPtrKind::Mut, Place::from(arr)));
                    let dst = self.res(i);
                    self.assign(&mut st, dst, Rvalue::Cast(CastKind::PtrToPtr, Operand::Copy(Place::from(raw)), self.env.u8p));
                }
                Load => {
                    let ty = self.res_ty(i);
                    let dst = self.res(i);
                    let addr = value_operand(i, 0).ok_or("load address")?;
                    let src = match self.frame_slot(addr, ty) {
                        Some(slot) => slot,
                        None => {
                            let p = self.op(i, 0, &mut st)?;
                            self.deref(p, ty, &mut st)
                        }
                    };
                    self.assign(&mut st, dst, Rvalue::Use(Operand::Copy(src)));
                }
                Store => {
                    let v = self.op(i, 0, &mut st)?;
                    let ty = self.opty(i, 0)?;
                    let addr = value_operand(i, 1).ok_or("store address")?;
                    let dst = match self.frame_slot(addr, ty) {
                        Some(slot) => slot,
                        None => {
                            let p = self.op(i, 1, &mut st)?;
                            self.deref(p, ty, &mut st)
                        }
                    };
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
                    let (dst, ty) = (self.res(i), self.res_ty(i));
                    self.assign(&mut st, dst, Rvalue::Cast(CastKind::PointerExposeProvenance, p, ty));
                }
                IntToPtr => {
                    let src = value_operand(i, 0).ok_or("inttoptr operand")?;
                    let p = self.addr(&mut cur, &mut st, src)?;
                    let dst = self.res(i);
                    self.assign(&mut st, dst, Rvalue::Use(p));
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
                            let v = value_operand(i, 0).ok_or("payload operand")?;
                            let (a, from) = self.raw(v, &mut st)?;
                            let a = self.coerce(&mut cur, &mut st, a, from, PTy::Val);
                            let dst = self.res(i);
                            self.assign(&mut st, dst, Rvalue::Use(a));
                        }
                        "soroban.val.payload" => {
                            let v = value_operand(i, 0).ok_or("payload operand")?;
                            let (a, from) = self.raw(v, &mut st)?;
                            let a = self.to_int(a, from, &mut st);
                            let dst = self.res(i);
                            self.assign(&mut st, dst, Rvalue::Use(a));
                        }
                        "soroban.storage_type" => {
                            let lit = value_operand(i, 0).and_then(const_of);
                            let dst = self.res(i);
                            match lit {
                                Some(c @ 0..=2) => {
                                    let kind = AggregateKind::Adt(self.env.storage_def, VariantIdx::from_u32(c as u32), List::empty(), None, None);
                                    self.assign(&mut st, dst, Rvalue::Aggregate(Box::new(kind), IndexVec::new()));
                                }
                                _ => {
                                    let v = value_operand(i, 0).ok_or("storage operand")?;
                                    let (a, from) = self.raw(v, &mut st)?;
                                    let a = self.coerce(&mut cur, &mut st, a, from, PTy::Storage);
                                    self.assign(&mut st, dst, Rvalue::Use(a));
                                }
                            }
                        }
                        _ => {
                            let rname = crate::rs_name(&name);
                            let def_id = *self.env.fns.get(&rname).ok_or_else(|| format!("no declaration for {name}"))?;
                            let fsig = tcx.fn_sig(def_id).instantiate_identity().skip_binder();
                            let mut args = Vec::new();
                            for k in 0..nargs {
                                let v = value_operand(i, k).ok_or("call operand")?;
                                let (a, from) = self.raw(v, &mut st)?;
                                let to = *fsig.inputs().get(k as usize).ok_or("arity")?;
                                let to_kind = self.env.kind_of_ty(to);
                                let a = self.coerce(&mut cur, &mut st, a, from, to_kind);
                                // Narrow integer positions (u8, bool) of intrinsics.
                                let a = if to_kind == PTy::Int && to != tcx.types.u64 && from == PTy::Int && to.is_integral() {
                                    self.cast(a, CastKind::IntToInt, to, &mut st)
                                } else {
                                    a
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
                        let v = value_operand(i, 0).ok_or("return operand")?;
                        let (a, from) = self.raw(v, &mut st)?;
                        let to = self.env.kind_of_ty(self.locals[Local::ZERO].ty);
                        let a = self.coerce(&mut cur, &mut st, a, from, to);
                        self.assign(&mut st, Place::from(Local::ZERO), Rvalue::Use(a));
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
                        let val = value_operand(i, k).and_then(const_of).ok_or("switch case value")? as u128;
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

pub fn build<'a, 'tcx>(env: &'a Env<'tcx>, f: FunctionValue<'a>, def_id: DefId, sigs: &'a Sigs) -> R<Body<'tcx>> {
    let tcx = env.tcx;
    let si = SourceInfo::outermost(DUMMY_SP);
    let fname = f.get_name().to_string_lossy().into_owned();
    let mut b = B {
        env,
        sigs,
        locals: IndexVec::new(),
        map: HashMap::new(),
        kinds: HashMap::new(),
        frames: HashMap::new(),
        blocks: IndexVec::new(),
        bbmap: HashMap::new(),
        debug: Vec::new(),
        si,
    };
    // _0, the parameters, then one local per SSA value.
    b.locals.push(LocalDecl::new(env.ret_ty(f, sigs)?, DUMMY_SP));
    for (n, p) in f.get_params().iter().enumerate() {
        let kind = sigs.param(&fname, n);
        let ty = match kind {
            Some(k) => env.pty(k),
            None => env.ty(p.get_type())?,
        };
        let l = b.locals.push(LocalDecl::new(ty, DUMMY_SP));
        b.map.insert(key(*p), l);
        // An i64 parameter inferred to be something else is read through a
        // conversion at each use; a `%Val` one already is what it says.
        if let Some(k) = kind.filter(|k| *k != PTy::Int && env.ty(p.get_type()).ok() != Some(env.pty(*k))) {
            b.kinds.insert(l, k);
        }
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
            let callee = callee_name(i);
            // A call's result takes the callee's inferred return type.
            let ret_kind = callee.as_deref().and_then(|c| b.sigs.ret(c)).filter(|k| *k != PTy::Int);
            let ty = match (callee.as_deref(), ret_kind) {
                (Some("soroban.storage_type"), _) => env.storage,
                (_, Some(k)) => env.pty(k),
                _ => env.ty(bt)?,
            };
            let l = b.locals.push(LocalDecl::new(ty, DUMMY_SP));
            b.map.insert(key(i), l);
            if let Some(k) = ret_kind.filter(|k| env.ty(bt).ok() != Some(env.pty(*k))) {
                b.kinds.insert(l, k);
            }
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
