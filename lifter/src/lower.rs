//! One wasm function -> one LLVM function: the operand stack, labels, frames, locals, operators.
use std::collections::HashMap;
use inkwell::attributes::{Attribute, AttributeLoc};
use inkwell::basic_block::BasicBlock;
use inkwell::builder::Builder;
use inkwell::context::Context;
use inkwell::module::{Linkage, Module};
use inkwell::types::{BasicMetadataTypeEnum, BasicTypeEnum, IntType, StructType};
use inkwell::values::{
    BasicValue, BasicValueEnum, FunctionValue, IntValue, PointerValue, ValueKind,
};
use inkwell::{AddressSpace, IntPredicate};
use wasmparser::Operator;

use crate::*;

/// A value on the abstract wasm operand stack.
#[derive(Clone, Copy)]
pub(crate) enum SV<'ctx> {
    /// A wasm constant, not yet committed to a type. The consumer decides,
    /// from the host ABI -- never guessed.
    Const(i64),
    /// An emitted LLVM value. Its type is carried by the value itself, so there
    /// is no separate tag that could disagree with reality.
    Reg(BasicValueEnum<'ctx>),
    /// An address in this function's shadow-stack frame, `frame + off`. The
    /// frame is an `alloca`, so an access here is a typed access to
    /// function-local memory, which LLVM then cleans up like any local.
    Frame(i64),
    /// Bottom.
    Unknown,
}

#[derive(Clone)]
pub(crate) struct Lbl<'ctx> {
    /// Where a `br` to this depth goes: a loop header, or a continuation.
    target: BasicBlock<'ctx>,
    /// Where `End` falls through to. Differs from `target` only for a loop.
    cont: BasicBlock<'ctx>,
    /// An `if`'s else arm, until `Else` claims it. Left `Some` at `End` means
    /// the arm is empty and still needs a block, because the conditional branch
    /// already names it.
    else_bb: Option<BasicBlock<'ctx>>,
    /// The result of a typed `block`/`if`/`loop`, as an entry-block alloca:
    /// every path that reaches the label stores its value, the continuation
    /// loads it, and mem2reg makes the phi. A `br` to a loop carries nothing.
    slot: Option<PointerValue<'ctx>>,
    /// The operand stack below this block when it opened. What the block
    /// pushes is its own; what was there before is still there after `end`.
    saved: Vec<SV<'ctx>>,
    is_loop: bool,
}

/// How many values a block type yields. Soroban contracts yield at most one;
/// a multi-value block keeps the old behaviour and its result is bottom.
pub(crate) fn block_results(bt: &wasmparser::BlockType, types: &Types) -> usize {
    match bt {
        wasmparser::BlockType::Empty => 0,
        wasmparser::BlockType::Type(_) => 1,
        wasmparser::BlockType::FuncType(t) => match types.0.get(*t as usize).map(|s| &s.composite_type.inner) {
            Some(wasmparser::CompositeInnerType::Func(ft)) => ft.results().len(),
            _ => 0,
        },
    }
}

/// Only what `Operator::operator_arity` needs to size the fallback in `lower`:
/// the type section, for `call_indirect`. Labels and direct calls are lowered
/// explicitly, so the rest is never consulted.
#[derive(Default)]
pub(crate) struct Types(pub(crate) Vec<wasmparser::SubType>);

#[derive(Default)]
pub(crate) struct Mod {
    pub(crate) types: Types,
    pub(crate) mem: Mem,
    /// The wasm value types of every function's params and results, by
    /// function index: the one type fact the binary states outright. On
    /// wasm32 a pointer is always `i32` and a Val always `i64`.
    pub(crate) wasm_sigs: HashMap<u32, (Vec<&'static str>, Vec<&'static str>)>,
    /// Function index -> (identifier, demangled path) for every helper whose
    /// fingerprint matched a known SDK function.
    pub(crate) fnames: HashMap<u32, (String, String)>,
    /// The function table's slots, for `call_indirect`: function indices.
    pub(crate) table: Vec<Option<u32>>,
}

/// A helper's name: what the fingerprints say it is, else `fN`.
pub(crate) fn fn_name(md: &Mod, fi: u32) -> String {
    md.fnames.get(&fi).map(|(id, _)| id.clone()).unwrap_or_else(|| format!("f{fi}"))
}

pub(crate) fn valtype_name(v: wasmparser::ValType) -> &'static str {
    match v {
        wasmparser::ValType::I32 => "i32",
        wasmparser::ValType::I64 => "i64",
        wasmparser::ValType::F32 => "f32",
        wasmparser::ValType::F64 => "f64",
        wasmparser::ValType::V128 => "v128",
        wasmparser::ValType::Ref(_) => "ref",
    }
}

/// Record the wasm signature on the LLVM function, one string attribute per
/// parameter and one on the return, so it survives whatever LLVM does to the
/// signature later (dead-argument elimination keeps attributes with their
/// argument) and the MIR stage can seed its type inference from it.
pub(crate) fn wasm_type_attrs(ctx: &Context, f: FunctionValue, fi: u32, md: &Mod) {
    if let Some((_, full)) = md.fnames.get(&fi) {
        f.add_attribute(AttributeLoc::Function, ctx.create_string_attribute("sdk.name", full));
    }
    let Some((params, results)) = md.wasm_sigs.get(&fi) else { return };
    for (i, t) in params.iter().enumerate() {
        f.add_attribute(AttributeLoc::Param(i as u32), ctx.create_string_attribute("wasm.type", t));
    }
    if let Some(t) = results.first() {
        f.add_attribute(AttributeLoc::Return, ctx.create_string_attribute("wasm.type", t));
    }
}

/// A wasm load or store, reduced to what the i64-wide model needs.
pub(crate) enum Acc {
    Load { bits: u32, signed: bool, off: u64 },
    Store { bits: u32, off: u64 },
}

pub(crate) fn mem_access(op: &Operator) -> Option<Acc> {
    use Operator::*;
    let (bits, signed, store, m) = match op {
        I32Load { memarg } | I64Load32U { memarg } => (32, false, false, memarg),
        I64Load32S { memarg } => (32, true, false, memarg),
        I64Load { memarg } => (64, false, false, memarg),
        I32Load8U { memarg } | I64Load8U { memarg } => (8, false, false, memarg),
        I32Load8S { memarg } | I64Load8S { memarg } => (8, true, false, memarg),
        I32Load16U { memarg } | I64Load16U { memarg } => (16, false, false, memarg),
        I32Load16S { memarg } | I64Load16S { memarg } => (16, true, false, memarg),
        I32Store { memarg } | I64Store32 { memarg } => (32, false, true, memarg),
        I64Store { memarg } => (64, false, true, memarg),
        I32Store8 { memarg } | I64Store8 { memarg } => (8, false, true, memarg),
        I32Store16 { memarg } | I64Store16 { memarg } => (16, false, true, memarg),
        _ => return None,
    };
    Some(if store {
        Acc::Store { bits, off: m.offset }
    } else {
        Acc::Load { bits, signed, off: m.offset }
    })
}

/// The memory helpers: declared always, defined by `--inline`.
pub(crate) const LOADS: [(&str, u32, bool); 7] = [
    ("load8u", 8, false),
    ("load8s", 8, true),
    ("load16u", 16, false),
    ("load16s", 16, true),
    ("load32u", 32, false),
    ("load32s", 32, true),
    ("load64", 64, false),
];

pub(crate) const STORES: [(&str, u32); 4] = [("store8", 8), ("store16", 16), ("store32", 32), ("store64", 64)];

/// LLVM `memory(...)` attribute encodings: none, and inaccessiblemem: readwrite.
pub(crate) const MEM_NONE: u64 = 0;

pub(crate) const MEM_INACCESSIBLE_RW: u64 = 12;

pub(crate) fn attr(ctx: &Context, name: &str, v: u64) -> Attribute {
    ctx.create_enum_attribute(Attribute::get_named_enum_kind_id(name), v)
}

pub(crate) fn int_ty(ctx: &Context, bits: u32) -> IntType<'_> {
    match bits {
        8 => ctx.i8_type(),
        16 => ctx.i16_type(),
        32 => ctx.i32_type(),
        _ => ctx.i64_type(),
    }
}

impl wasmparser::ModuleArity for Types {
    fn sub_type_at(&self, i: u32) -> Option<&wasmparser::SubType> {
        self.0.get(i as usize)
    }
    fn tag_type_arity(&self, _: u32) -> Option<(u32, u32)> {
        None
    }
    fn type_index_of_function(&self, _: u32) -> Option<u32> {
        None
    }
    fn func_type_of_cont_type(&self, _: &wasmparser::ContType) -> Option<&wasmparser::FuncType> {
        None
    }
    fn sub_type_of_ref_type(&self, _: &wasmparser::RefType) -> Option<&wasmparser::SubType> {
        None
    }
    fn control_stack_height(&self) -> u32 {
        0
    }
    fn label_block(&self, _: u32) -> Option<(wasmparser::BlockType, wasmparser::FrameKind)> {
        None
    }
}

/// The declared conversion and bottom functions, plus the Val type.
pub(crate) struct Rt<'ctx> {
    pub(crate) val: StructType<'ctx>,
    pub(crate) i64t: IntType<'ctx>,
    pub(crate) from_payload: FunctionValue<'ctx>,
    pub(crate) payload: FunctionValue<'ctx>,
    /// Same trick as `from_payload`: gives a decoded constant a name slot,
    /// because LLVM has nowhere to hang a name on a literal operand.
    pub(crate) storage_type: FunctionValue<'ctx>,
    pub(crate) unknown_val: FunctionValue<'ctx>,
    pub(crate) unknown_i64: FunctionValue<'ctx>,
    /// wasm `unreachable` is a trap the host observes, not LLVM's "never
    /// happens": lowered bare, O1 turns the guard in front of it into an
    /// `llvm.assume` and the check vanishes from the output.
    pub(crate) trap: FunctionValue<'ctx>,
}

impl<'ctx> Rt<'ctx> {
    pub(crate) fn new(ctx: &'ctx Context, m: &Module<'ctx>) -> Self {
        let i64t = ctx.i64_type();
        let val = ctx.opaque_struct_type("Val");
        val.set_body(&[i64t.into()], false);
        let vm: BasicMetadataTypeEnum = val.into();
        let im: BasicMetadataTypeEnum = i64t.into();
        let rt = Rt {
            val,
            i64t,
            from_payload: m.add_function("soroban.val.from_payload", val.fn_type(&[im], false), None),
            payload: m.add_function("soroban.val.payload", i64t.fn_type(&[vm], false), None),
            storage_type: m.add_function("soroban.storage_type", i64t.fn_type(&[im], false), None),
            unknown_val: m.add_function("diver.unknown", val.fn_type(&[], false), None),
            unknown_i64: m.add_function("diver.unknown.i64", i64t.fn_type(&[], false), None),
            trap: m.add_function("soroban.trap", ctx.void_type().fn_type(&[], false), None),
        };
        rt.trap.add_attribute(AttributeLoc::Function, attr(ctx, "noreturn", 0));
        // The conversions are pure, so LLVM may fold and merge them. Bottom is
        // NOT: two unknowns merged into one would make `x == x` true. It gets
        // side effects on memory LLVM cannot see, which also keeps stack-slot
        // forwarding across it legal.
        for f in [rt.from_payload, rt.payload, rt.storage_type] {
            for a in [attr(ctx, "memory", MEM_NONE), attr(ctx, "nounwind", 0), attr(ctx, "willreturn", 0)] {
                f.add_attribute(AttributeLoc::Function, a);
            }
        }
        for f in [rt.unknown_val, rt.unknown_i64] {
            f.add_attribute(AttributeLoc::Function, attr(ctx, "memory", MEM_INACCESSIBLE_RW));
        }
        for (n, _, _) in LOADS {
            m.add_function(&format!("soroban.{n}"), i64t.fn_type(&[im], false), None);
        }
        for (n, _) in STORES {
            m.add_function(&format!("soroban.{n}"), ctx.void_type().fn_type(&[im, im], false), None);
        }
        rt
    }

    pub(crate) fn ty(&self, v: VT) -> BasicTypeEnum<'ctx> {
        match v {
            VT::Val => self.val.into(),
            VT::Raw64 | VT::Storage => self.i64t.into(),
        }
    }
}

pub(crate) struct Fun<'ctx, 'a> {
    ctx: &'ctx Context,
    b: &'a Builder<'ctx>,
    rt: &'a Rt<'ctx>,
    f: FunctionValue<'ctx>,
    locals: Vec<PointerValue<'ctx>>,
    stack: Vec<SV<'ctx>>,
    labels: Vec<Lbl<'ctx>>,
    imports: &'a HashMap<u32, &'static HostFn>,
    n: usize,
    /// The recovered shadow-stack frame (alloca, size) and the wasm local that
    /// holds its base, when the function opens one the way LLVM's wasm
    /// backend does.
    frame: Option<(PointerValue<'ctx>, u64)>,
    frame_local: Option<u32>,
    /// Bytes of the frame below the prologue's stack pointer: what the body
    /// pushes part-way (`global.get 0; i32.const k; i32.sub; global.set 0`
    /// around one call); and where the stack pointer is now, as a frame
    /// offset, while it is known.
    bias: i64,
    sp: Option<i64>,
    /// Locals assigned once, with an address in the frame: reading one is
    /// that address, not an integer that lost its provenance.
    frame_alias: HashMap<u32, i64>,
}

impl<'ctx, 'a> Fun<'ctx, 'a> {
    fn blk(&mut self, tag: &str) -> BasicBlock<'ctx> {
        self.n += 1;
        self.ctx.append_basic_block(self.f, &format!("{tag}{}", self.n))
    }

    /// The block the builder sits in can be reached: it is the entry, or a
    /// live block branches to it. Branches are only ever emitted from live
    /// blocks, so by induction "has a use" is exactly "reachable" -- LLVM's
    /// use-list answers it, no reachability pass needed.
    fn live(&self) -> bool {
        match self.b.get_insert_block() {
            Some(bb) => Some(bb) == self.f.get_first_basic_block() || bb.get_first_use().is_some(),
            None => false,
        }
    }

    /// Nothing more may be emitted here: the block already ends, or no path
    /// reaches it. wasm permits dead code after `br`/`return`/`unreachable`;
    /// writing it out would fill blocks the prune then removes.
    fn terminated(&self) -> bool {
        !self.live()
            || self
                .b
                .get_insert_block()
                .and_then(|bb| bb.get_terminator())
                .is_some()
    }

    fn br(&mut self, to: BasicBlock<'ctx>) {
        if !self.terminated() {
            self.b.build_unconditional_branch(to).expect("br");
        }
    }

    /// A wasm `return`. Also what the body's final `end` and a `br` to the
    /// function's own label are: the top of stack, typed by the ABI, handed
    /// back. Soroban functions have at most one result.
    fn ret(&mut self, n_results: usize, val_abi: bool) {
        if self.terminated() {
            return;
        }
        if n_results == 0 {
            self.b.build_return(None).expect("ret");
        } else {
            let v = self.pop();
            let rv = self.use_as(v, if val_abi { VT::Val } else { VT::Raw64 });
            self.b.build_return(Some(&rv)).expect("ret");
        }
    }

    fn call1(&mut self, f: FunctionValue<'ctx>, args: &[BasicValueEnum<'ctx>], n: &str) -> BasicValueEnum<'ctx> {
        let a: Vec<_> = args.iter().map(|v| (*v).into()).collect();
        self.b
            .build_direct_call(f, &a, n)
            .expect("call")
            .try_as_basic_value()
            .basic()
            .expect("value-returning call")
    }

    fn pop(&mut self) -> SV<'ctx> {
        self.stack.pop().unwrap_or_else(|| {
            why("underflow");
            SV::Unknown
        })
    }

    /// A linear-memory access. A constant address inside an unwritten data
    /// segment reads as the constant it is; an address inside this function's
    /// recovered frame is a typed access to the frame alloca; everything else
    /// goes through the `soroban.load*`/`store*` helpers, which `--inline`
    /// defines as `inttoptr` accesses, so an escaped frame address folds back
    /// to its alloca and `fold_data_loads` can read what became constant.
    fn mem(&mut self, acc: Acc, m: &Module<'ctx>, mem: &Mem) {
        match acc {
            Acc::Load { bits, signed, off } => {
                let a = self.pop();
                if let SV::Const(c) = a {
                    if let Some(v) = mem.load((c as u32 as u64).wrapping_add(off), bits, signed) {
                        self.stack.push(SV::Const(v));
                        return;
                    }
                }
                if let Some(p) = self.frame_slot(a, off, bits) {
                    let v = self.b.build_load(int_ty(self.ctx, bits), p, "ld").expect("load");
                    let _ = v.as_instruction_value().expect("inst").set_alignment(1);
                    let v = v.into_int_value();
                    let w = if bits == 64 {
                        v
                    } else if signed {
                        self.b.build_int_s_extend(v, self.rt.i64t, "sx").expect("sext")
                    } else {
                        self.b.build_int_z_extend(v, self.rt.i64t, "zx").expect("zext")
                    };
                    self.stack.push(SV::Reg(w.into()));
                    return;
                }
                let ea = self.addr(a, off);
                let sfx = if bits == 64 { "" } else if signed { "s" } else { "u" };
                let f = m.get_function(&format!("soroban.load{bits}{sfx}")).expect("load helper");
                let r = self.call1(f, &[ea.into()], "ld");
                self.stack.push(SV::Reg(r));
            }
            Acc::Store { bits, off } => {
                let v = self.pop();
                let a = self.pop();
                let vi = self.use_int(v);
                if let Some(p) = self.frame_slot(a, off, bits) {
                    let t = if bits == 64 {
                        vi
                    } else {
                        self.b.build_int_truncate(vi, int_ty(self.ctx, bits), "t").expect("trunc")
                    };
                    let _ = self.b.build_store(p, t).expect("store").set_alignment(1);
                    return;
                }
                let ea = self.addr(a, off);
                let f = m.get_function(&format!("soroban.store{bits}")).expect("store helper");
                self.b.build_direct_call(f, &[ea.into(), vi.into()], "").expect("call");
            }
        }
    }

    /// `frame + off` as a pointer, when the whole access lies inside the frame.
    fn frame_slot(&mut self, a: SV<'ctx>, off: u64, bits: u32) -> Option<PointerValue<'ctx>> {
        let (SV::Frame(fo), Some((fr, size))) = (a, self.frame) else { return None };
        let o = fo.checked_add(off as i64)?.checked_add(self.bias)?;
        let end = (o as u64).checked_add((bits / 8) as u64)?;
        (o >= 0 && end <= size).then(|| self.frame_ptr(fr, o))
    }

    fn frame_ptr(&mut self, fr: PointerValue<'ctx>, o: i64) -> PointerValue<'ctx> {
        if o == 0 {
            return fr;
        }
        let k = self.rt.i64t.const_int(o as u64, true);
        unsafe { self.b.build_gep(self.ctx.i8_type(), fr, &[k], &format!("slot{o}")) }.expect("gep")
    }

    fn addr(&mut self, a: SV<'ctx>, off: u64) -> IntValue<'ctx> {
        let ai = self.use_int(a);
        if off == 0 {
            ai
        } else {
            self.b.build_int_add(ai, self.rt.i64t.const_int(off, false), "ea").expect("add")
        }
    }

    /// The single Val<->i64 crossing. Because the result is a typed inkwell
    /// value handed to `build_direct_call`, a mismatch is caught by
    /// `module.verify()` rather than by an assertion of mine.
    fn use_as(&mut self, v: SV<'ctx>, want: VT) -> BasicValueEnum<'ctx> {
        let wants_val = want == VT::Val;
        match v {
            SV::Const(c) => {
                let k = self.rt.i64t.const_int(c as u64, false);
                match want {
                    VT::Val => {
                        let n = val_name(c as u64);
                        self.call1(self.rt.from_payload, &[k.into()], &n)
                    }
                    // A `StorageType` operand is one of three named constants.
                    VT::Storage => {
                        let n = storage_name(c);
                        self.call1(self.rt.storage_type, &[k.into()], &n)
                    }
                    VT::Raw64 => k.into(),
                }
            }
            SV::Reg(r) => match (r.is_struct_value(), wants_val) {
                (true, true) | (false, false) => r,
                (false, true) => self.call1(self.rt.from_payload, &[r], "to_val"),
                (true, false) => self.call1(self.rt.payload, &[r], "payload"),
            },
            // A frame address that escapes -- passed to a call, stored, compared
            // -- is the integer `ptrtoint(frame + off)`. After inlining,
            // `inttoptr(ptrtoint(frame) + k)` folds back to the alloca.
            SV::Frame(o) => {
                let v = match self.frame {
                    Some((fr, _)) => {
                        let p = self.frame_ptr(fr, o + self.bias);
                        SV::Reg(self.b.build_ptr_to_int(p, self.rt.i64t, "fp").expect("ptrtoint").into())
                    }
                    None => {
                        why("frame address without a frame");
                        SV::Unknown
                    }
                };
                self.use_as(v, want)
            }
            SV::Unknown => {
                let f = if wants_val {
                    self.rt.unknown_val
                } else {
                    self.rt.unknown_i64
                };
                self.call1(f, &[], "bottom")
            }
        }
    }

    fn use_int(&mut self, v: SV<'ctx>) -> inkwell::values::IntValue<'ctx> {
        self.use_as(v, VT::Raw64).into_int_value()
    }

    /// The value model is i64-wide. An i32 operation is done in i32 -- its
    /// operands truncated, its result zero-extended -- so a wrapped value
    /// never leaks its high bits into a compare, a shift or a division. LLVM
    /// folds the width casts that turn out redundant.
    fn narrow(&mut self, v: inkwell::values::IntValue<'ctx>) -> inkwell::values::IntValue<'ctx> {
        let i32t = self.rt.i64t.get_context().i32_type();
        self.b.build_int_truncate(v, i32t, "t").expect("trunc")
    }

    fn widen(&mut self, v: inkwell::values::IntValue<'ctx>) -> inkwell::values::IntValue<'ctx> {
        self.b.build_int_z_extend(v, self.rt.i64t, "z").expect("zext")
    }

    fn binop(&mut self, op: &str, w32: bool) {
        let b = self.pop();
        let a = self.pop();
        // Frame arithmetic stays symbolic: `frame + 8` is a slot, not an int.
        match (op, a, b) {
            ("add", SV::Frame(o), SV::Const(k)) | ("add", SV::Const(k), SV::Frame(o)) => {
                return self.stack.push(SV::Frame(o.wrapping_add(k)));
            }
            ("sub", SV::Frame(o), SV::Const(k)) => return self.stack.push(SV::Frame(o.wrapping_sub(k))),
            _ => {}
        }
        let (mut x, mut y) = (self.use_int(a), self.use_int(b));
        if w32 {
            x = self.narrow(x);
            y = self.narrow(y);
        }
        // diver: wasm traps on division by zero; LLVM's udiv/sdiv leave it undefined.
        let r = match op {
            "add" => self.b.build_int_add(x, y, "add"),
            "sub" => self.b.build_int_sub(x, y, "sub"),
            "mul" => self.b.build_int_mul(x, y, "mul"),
            "and" => self.b.build_and(x, y, "and"),
            "or" => self.b.build_or(x, y, "or"),
            "xor" => self.b.build_xor(x, y, "xor"),
            "shl" => self.b.build_left_shift(x, y, "shl"),
            "lshr" => self.b.build_right_shift(x, y, false, "lshr"),
            "udiv" => self.b.build_int_unsigned_div(x, y, "udiv"),
            "sdiv" => self.b.build_int_signed_div(x, y, "sdiv"),
            "urem" => self.b.build_int_unsigned_rem(x, y, "urem"),
            "srem" => self.b.build_int_signed_rem(x, y, "srem"),
            _ => self.b.build_right_shift(x, y, true, "ashr"),
        }
        .expect("binop");
        let r = if w32 { self.widen(r) } else { r };
        self.stack.push(SV::Reg(r.into()));
    }

    fn cmp(&mut self, p: IntPredicate, w32: bool) {
        let b = self.pop();
        let a = self.pop();
        let (mut x, mut y) = (self.use_int(a), self.use_int(b));
        if w32 {
            x = self.narrow(x);
            y = self.narrow(y);
        }
        let c = self.b.build_int_compare(p, x, y, "cmp").expect("cmp");
        let z = self
            .b
            .build_int_z_extend(c, self.rt.i64t, "zext")
            .expect("zext");
        self.stack.push(SV::Reg(z.into()));
    }

    /// Resolve a relative branch depth against the full label stack. Out of
    /// range is malformed wasm, not something to skip past.
    fn target(&self, depth: u32) -> Result<BasicBlock<'ctx>, String> {
        Ok(self.labels[self.label(depth)?].target)
    }

    fn label(&self, depth: u32) -> Result<usize, String> {
        let n = self.labels.len();
        let d = depth as usize;
        if d >= n {
            return Err(format!("branch depth {d} exceeds label stack {n}"));
        }
        Ok(n - 1 - d)
    }

    /// A branch to a typed label carries the top of stack as the label's
    /// result: store it in the label's slot. `keep` leaves it on the stack
    /// for the path that does not take the branch (`br_if`).
    fn store_result(&mut self, idx: usize, keep: bool) {
        let Some(slot) = self.labels[idx].slot else { return };
        if self.labels[idx].is_loop || self.terminated() {
            return;
        }
        let v = if keep { self.stack.last().copied().unwrap_or(SV::Unknown) } else { self.pop() };
        let iv = self.use_int(v);
        self.b.build_store(slot, iv).expect("store");
    }
}

/// The function table as a constant array of function pointers, made once
/// per module: `call_indirect` loads its slot and calls by the type it names.
/// A slot holding an import or nothing is null.
pub(crate) fn table_global<'ctx>(ctx: &'ctx Context, m: &Module<'ctx>, md: &Mod, local_sigs: &HashMap<u32, (usize, usize)>, rt: &Rt<'ctx>) -> Option<inkwell::values::GlobalValue<'ctx>> {
    if md.table.is_empty() {
        return None;
    }
    if let Some(g) = m.get_global("__table") {
        return Some(g);
    }
    let pt = ctx.ptr_type(AddressSpace::default());
    let elems: Vec<PointerValue<'ctx>> = md
        .table
        .iter()
        .map(|slot| {
            let Some(fi) = slot else { return pt.const_null() };
            let Some((np, nr)) = local_sigs.get(fi).copied() else { return pt.const_null() };
            let fname = fn_name(md, *fi);
            let f = m.get_function(&fname).unwrap_or_else(|| {
                let ps: Vec<BasicMetadataTypeEnum> = (0..np).map(|_| rt.i64t.into()).collect();
                let t = if nr == 0 { ctx.void_type().fn_type(&ps, false) } else { rt.i64t.fn_type(&ps, false) };
                let f = m.add_function(&fname, t, None);
                wasm_type_attrs(ctx, f, *fi, md);
                f
            });
            f.as_global_value().as_pointer_value()
        })
        .collect();
    let g = m.add_global(pt.array_type(elems.len() as u32), None, "__table");
    g.set_initializer(&pt.const_array(&elems));
    g.set_constant(true);
    g.set_linkage(Linkage::Internal);
    Some(g)
}

/// Why a bottom was made, when asked (`DIVER_WHY_UNKNOWN`): the lowering's
/// own gaps, counted over a corpus.
pub(crate) fn why(what: &str) {
    if std::env::var_os("DIVER_WHY_UNKNOWN").is_some() {
        eprintln!("unknown: {what}");
    }
}

pub(crate) fn pair_ends(ops: &[Operator]) -> HashMap<usize, usize> {
    let mut open: Vec<usize> = Vec::new();
    let mut pairs = HashMap::new();
    for (i, op) in ops.iter().enumerate() {
        match op {
            Operator::Block { .. } | Operator::Loop { .. } | Operator::If { .. } => open.push(i),
            Operator::End => {
                if let Some(s) = open.pop() {
                    pairs.insert(s, i);
                }
            }
            _ => {}
        }
    }
    pairs
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn lower<'ctx>(
    ctx: &'ctx Context,
    m: &Module<'ctx>,
    rt: &Rt<'ctx>,
    f: FunctionValue<'ctx>,
    n_params: usize,
    n_results: usize,
    n_locals: usize,
    ops: &[Operator],
    imports: &HashMap<u32, &'static HostFn>,
    local_sigs: &HashMap<u32, (usize, usize)>,
    md: &Mod,
    // True only for an exported contract function, whose wasm i64 params ARE
    // Soroban Vals. A helper's params are plain i64 with no declared meaning,
    // and typing them as Val is what inkwell caught the text emitter hiding.
    val_abi: bool,
) -> Result<(), String> {
    let _ = pair_ends(ops);
    let b = ctx.create_builder();
    let entry = ctx.append_basic_block(f, "entry");
    b.position_at_end(entry);

    let mut fun = Fun {
        ctx,
        b: &b,
        rt,
        f,
        locals: Vec::new(),
        stack: Vec::new(),
        labels: Vec::new(),
        imports,
        n: 0,
        frame: None,
        frame_local: None,
        bias: 0,
        sp: Some(0),
        frame_alias: HashMap::new(),
    };

    // Locals in allocas; `mem2reg` promotes them to SSA with real phis. Doing
    // that by hand would be re-implementing mem2reg.
    for i in 0..(n_params + n_locals) {
        let p = b
            .build_alloca(rt.i64t, &format!("l{i}"))
            .expect("alloca");
        fun.locals.push(p);
    }
    for i in 0..n_params {
        let a = f.get_nth_param(i as u32).expect("param");
        let raw = if val_abi {
            fun.call1(rt.payload, &[a], "arg_payload")
        } else {
            a
        };
        b.build_store(fun.locals[i], raw).expect("store");
    }
    for i in n_params..(n_params + n_locals) {
        b.build_store(fun.locals[i], rt.i64t.const_zero())
            .expect("store");
    }

    // LLVM's wasm backend opens a frame with exactly this sequence, keeps the
    // base in one local it never reassigns, and closes it by adding the size
    // back to the stack pointer. Recovered as an alloca, the frame is the
    // function-local memory it really is: dead stores go, and the SP traffic
    // through @g0 with them. Anything else touching @g0 is lowered as is.
    let mut set_counts: HashMap<u32, usize> = HashMap::new();
    for o in ops {
        if let Operator::LocalSet { local_index } | Operator::LocalTee { local_index } = o {
            *set_counts.entry(*local_index).or_default() += 1;
        }
    }
    let mut skip = 0;
    // `i32.sub N`, or `i32.add -N` from older LLVMs: the same frame.
    let prologue = match ops {
        [Operator::GlobalGet { global_index: 0 }, Operator::I32Const { value: n }, Operator::I32Sub, Operator::LocalTee { local_index: l }, Operator::GlobalSet { global_index: 0 }, ..] if *n > 0 => {
            Some((*n as u64, *l))
        }
        [Operator::GlobalGet { global_index: 0 }, Operator::I32Const { value: n }, Operator::I32Add, Operator::LocalTee { local_index: l }, Operator::GlobalSet { global_index: 0 }, ..] if *n < 0 => {
            Some((n.unsigned_abs() as u64, *l))
        }
        _ => None,
    };
    let adopt = prologue.is_some_and(|(_, l)| set_counts.get(&l).copied() == Some(1));
    // What the body pushes on the shadow stack part-way, below that frame:
    // the deepest push. diver: pushes are taken as sequential, not nested.
    let mut extra = 0u64;
    for (i, w) in ops.windows(4).enumerate() {
        if adopt && i == 0 {
            continue;
        }
        let k = match w {
            [Operator::GlobalGet { global_index: 0 }, Operator::I32Const { value: n }, Operator::I32Sub, _]
            | [Operator::GlobalGet { global_index: 0 }, Operator::LocalTee { .. }, Operator::I32Const { value: n }, Operator::I32Sub]
                if *n > 0 =>
            {
                *n as u64
            }
            [Operator::GlobalGet { global_index: 0 }, Operator::I32Const { value: n }, Operator::I32Add, _]
            | [Operator::GlobalGet { global_index: 0 }, Operator::LocalTee { .. }, Operator::I32Const { value: n }, Operator::I32Add]
                if *n < 0 =>
            {
                n.unsigned_abs() as u64
            }
            _ => continue,
        };
        extra = extra.max(k);
    }
    let n = if adopt { prologue.map_or(0, |(n, _)| n) } else { 0 };
    if n + extra > 0 {
        let fr = b.build_alloca(ctx.i8_type().array_type((n + extra) as u32), "frame").expect("alloca");
        fun.frame = Some((fr, n + extra));
        fun.bias = extra as i64;
        if let Some((_, l)) = prologue.filter(|_| adopt) {
            fun.frame_local = Some(l);
            skip = 5;
        }
    }

    // One entry-block slot per typed label, handed out as labels open.
    let mut slots: Vec<PointerValue> = ops
        .iter()
        .filter_map(|op| match op {
            Operator::Block { blockty } | Operator::Loop { blockty } | Operator::If { blockty } => Some(blockty),
            _ => None,
        })
        .filter(|bt| block_results(bt, &md.types) == 1)
        .map(|_| b.build_alloca(rt.i64t, "blk").expect("alloca"))
        .collect();
    slots.reverse();
    let mut slot_for = |bt: &wasmparser::BlockType| if block_results(bt, &md.types) == 1 { slots.pop() } else { None };

    let exit = ctx.append_basic_block(f, "exit");
    fun.labels.push(Lbl {
        target: exit,
        cont: exit,
        else_bb: None,
        slot: None,
        is_loop: false,
        saved: Vec::new(),
    });

    for (i, op) in ops.iter().enumerate().skip(skip) {
        // Dead code only needs its labels kept balanced; nothing in it runs.
        if fun.terminated()
            && !matches!(
                op,
                Operator::Block { .. } | Operator::Loop { .. } | Operator::If { .. } | Operator::Else | Operator::End
            )
        {
            continue;
        }
        if let Some(acc) = mem_access(op) {
            fun.mem(acc, m, &md.mem);
            continue;
        }
        match op {
            // The stack pointer, while it points into the frame, is that offset.
            Operator::GlobalGet { global_index: 0 } if fun.frame.is_some() && fun.sp.is_some() => {
                fun.stack.push(SV::Frame(fun.sp.unwrap_or(0)));
            }
            Operator::GlobalGet { global_index } => match m.get_global(&format!("g{global_index}")) {
                Some(g) => {
                    let v = fun.b.build_load(rt.i64t, g.as_pointer_value(), &format!("g{global_index}")).expect("load");
                    fun.stack.push(SV::Reg(v));
                }
                None => {
                    why("global");
                    fun.stack.push(SV::Unknown)
                }
            },
            Operator::GlobalSet { global_index } => {
                let v = fun.pop();
                // Moving the stack pointer within the frame: the frame is an
                // alloca now, so there is nothing to store, only where it is.
                if let SV::Frame(o) = v {
                    if *global_index == 0 {
                        fun.sp = Some(o);
                    }
                    continue;
                }
                if *global_index == 0 {
                    fun.sp = None;
                }
                let iv = fun.use_int(v);
                if let Some(g) = m.get_global(&format!("g{global_index}")) {
                    fun.b.build_store(g.as_pointer_value(), iv).expect("store");
                }
            }
            Operator::Block { blockty } => {
                let cont = fun.blk("c");
                let saved = fun.stack.clone();
                fun.labels.push(Lbl { target: cont, cont, else_bb: None, slot: slot_for(blockty), is_loop: false, saved });
            }
            Operator::Loop { blockty } => {
                let h = fun.blk("h");
                fun.br(h);
                fun.b.position_at_end(h);
                let cont = fun.blk("lc");
                let saved = fun.stack.clone();
                fun.labels.push(Lbl { target: h, cont, else_bb: None, slot: slot_for(blockty), is_loop: true, saved });
            }
            Operator::If { blockty } => {
                let slot = slot_for(blockty);
                let then_bb = fun.blk("then");
                let else_bb = fun.blk("else");
                let cont = fun.blk("ic");
                if !fun.terminated() {
                    let c = fun.pop();
                    let ci = fun.use_int(c);
                    let nz = fun
                        .b
                        .build_int_compare(IntPredicate::NE, ci, rt.i64t.const_zero(), "if")
                        .expect("icmp");
                    fun.b
                        .build_conditional_branch(nz, then_bb, else_bb)
                        .expect("condbr");
                }
                let saved = fun.stack.clone();
                fun.labels.push(Lbl { target: cont, cont, else_bb: Some(else_bb), slot, is_loop: false, saved });
                fun.b.position_at_end(then_bb);
                let _ = i;
            }
            Operator::Else => {
                let (cont, eb, saved) = match fun.labels.last_mut() {
                    Some(l) => (l.cont, l.else_bb.take(), l.saved.clone()),
                    None => return Err("else with no frame".into()),
                };
                // The then arm's value is the if's result on this path.
                let last = fun.labels.len() - 1;
                fun.store_result(last, false);
                fun.br(cont);
                if let Some(bb) = eb {
                    fun.b.position_at_end(bb);
                }
                // The else arm starts from the stack the `if` was entered with.
                fun.stack = saved;
            }
            Operator::End => {
                let Some(fr) = fun.labels.pop() else { continue };
                if fr.cont == exit {
                    // The body's own `end`: falling off it returns the top of
                    // stack. Not doing so made every fall-through export
                    // return bottom while the wasm plainly said `i64.const 2`.
                    fun.labels.push(fr);
                    fun.ret(n_results, val_abi);
                    continue;
                }
                // Falling off the end: the top of stack is the label's result.
                if let Some(slot) = fr.slot {
                    if !fun.terminated() {
                        let v = fun.pop();
                        let iv = fun.use_int(v);
                        fun.b.build_store(slot, iv).expect("store");
                    }
                }
                fun.br(fr.cont);
                // An `if` with no `else`: the branch already names that block,
                // so it must exist and reach the continuation.
                if let Some(bb) = fr.else_bb {
                    fun.b.position_at_end(bb);
                    fun.br(fr.cont);
                }
                fun.b.position_at_end(fr.cont);
                // What the block pushed is gone with it; what was below it is
                // still there. A typed label's one result comes through its
                // slot, and locals go through allocas: mem2reg builds the phis.
                fun.stack = fr.saved;
                if let Some(slot) = fr.slot {
                    let v = fun.b.build_load(rt.i64t, slot, "blk").expect("load");
                    fun.stack.push(SV::Reg(v));
                }
            }
            Operator::Br { relative_depth } => {
                let idx = fun.label(*relative_depth)?;
                let t = fun.labels[idx].target;
                if t == exit {
                    fun.ret(n_results, val_abi);
                } else {
                    fun.store_result(idx, false);
                    fun.br(t);
                }
            }
            Operator::BrIf { relative_depth } => {
                let idx = fun.label(*relative_depth)?;
                let t = fun.labels[idx].target;
                let c = fun.pop();
                let ci = fun.use_int(c);
                if t != exit {
                    fun.store_result(idx, true);
                }
                let nz = fun
                    .b
                    .build_int_compare(IntPredicate::NE, ci, rt.i64t.const_zero(), "brif")
                    .expect("icmp");
                let fall = fun.blk("fall");
                if !fun.terminated() {
                    fun.b
                        .build_conditional_branch(nz, t, fall)
                        .expect("condbr");
                }
                fun.b.position_at_end(fall);
            }
            Operator::BrTable { targets } => {
                // Every case and the default name a real BasicBlock handle.
                // There is no index into a list that could fall off the end.
                let sel = fun.pop();
                let si = fun.use_int(sel);
                let s32 = fun
                    .b
                    .build_int_truncate(si, ctx.i32_type(), "sel")
                    .expect("trunc");
                let deflt = fun.target(targets.default())?;
                let mut cases = Vec::new();
                let mut labels = vec![fun.label(targets.default())?];
                for (idx, d) in targets.targets().enumerate() {
                    let d = d.map_err(|e| e.to_string())?;
                    labels.push(fun.label(d)?);
                    cases.push((ctx.i32_type().const_int(idx as u64, false), fun.target(d)?));
                }
                // Every target gets the same value; all typed targets share
                // one type, so the store repeats per distinct slot.
                labels.sort();
                labels.dedup();
                let carried = labels.iter().any(|i| fun.labels[*i].slot.is_some() && !fun.labels[*i].is_loop);
                for i in labels {
                    fun.store_result(i, true);
                }
                if carried {
                    fun.pop();
                }
                if !fun.terminated() {
                    fun.b.build_switch(s32, deflt, &cases).expect("switch");
                }
            }
            Operator::Return => {
                fun.ret(n_results, val_abi);            }
            Operator::Unreachable => {
                if !fun.terminated() {
                    fun.b.build_direct_call(rt.trap, &[], "").expect("call");
                    fun.b.build_unreachable().expect("unreachable");
                }
            }
            Operator::I32Const { value } => fun.stack.push(SV::Const(*value as i64)),
            Operator::I64Const { value } => fun.stack.push(SV::Const(*value)),
            Operator::LocalGet { local_index } => {
                if fun.frame_local == Some(*local_index) {
                    fun.stack.push(SV::Frame(0));
                    continue;
                }
                if let Some(o) = fun.frame_alias.get(local_index) {
                    fun.stack.push(SV::Frame(*o));
                    continue;
                }
                let Some(p) = fun.locals.get(*local_index as usize).copied() else {
                    why("local");
                    fun.stack.push(SV::Unknown);
                    continue;
                };
                let v = fun.b.build_load(rt.i64t, p, "get").expect("load");
                fun.stack.push(SV::Reg(v));
            }
            Operator::LocalSet { local_index } | Operator::LocalTee { local_index } => {
                let v = fun.pop();
                if let SV::Frame(o) = v {
                    if set_counts.get(local_index).copied() == Some(1) {
                        fun.frame_alias.insert(*local_index, o);
                    }
                }
                let iv = fun.use_int(v);
                if let Some(p) = fun.locals.get(*local_index as usize).copied() {
                    fun.b.build_store(p, iv).expect("store");
                }
                if matches!(op, Operator::LocalTee { .. }) {
                    fun.stack.push(if matches!(v, SV::Frame(_)) { v } else { SV::Reg(iv.into()) });
                }
            }
            Operator::Drop => {
                fun.pop();
            }
            Operator::Call { function_index } => {
                if let Some(h) = fun.imports.get(function_index).copied() {
                    // Host call: the ABI decides every argument's type, and the
                    // declaration is what the verifier checks against.
                    let callee = m.get_function(h.name).expect("declared host fn");
                    let mut a: Vec<SV> = (0..h.args.len()).map(|_| fun.pop()).collect();
                    a.reverse();
                    let mut args = Vec::new();
                    for (v, want) in a.into_iter().zip(h.args.iter().copied()) {
                        args.push(fun.use_as(v, want));
                    }
                    // Name the result after the syscall, not its one-character
                    // import code: `%has_contract_data`, never `%0`.
                    let short = h.name.rsplit('.').next().unwrap_or(h.name);
                    let r = fun.call1(callee, &args, short);
                    fun.stack.push(SV::Reg(r));
                } else if let Some((np, nr)) = local_sigs.get(function_index).copied() {
                    let fname = fn_name(md, *function_index);
                    let callee = m.get_function(&fname).unwrap_or_else(|| {
                        let ps: Vec<BasicMetadataTypeEnum> =
                            (0..np).map(|_| rt.i64t.into()).collect();
                        let t = if nr == 0 {
                            ctx.void_type().fn_type(&ps, false)
                        } else {
                            rt.i64t.fn_type(&ps, false)
                        };
                        let f = m.add_function(&fname, t, None);
                        wasm_type_attrs(ctx, f, *function_index, md);
                        f
                    });
                    let mut a: Vec<SV> = (0..np).map(|_| fun.pop()).collect();
                    a.reverse();
                    // Coerce to the callee's DECLARED parameter types rather
                    // than assuming i64. A wasm function can be both exported
                    // (Val ABI) and called internally, and assuming made the
                    // text emitter write a self-consistently wrong call site.
                    let want: Vec<VT> = callee
                        .get_type()
                        .get_param_types()
                        .iter()
                        .map(|t| if t.is_struct_type() { VT::Val } else { VT::Raw64 })
                        .collect();
                    let args: Vec<BasicValueEnum> = a
                        .into_iter()
                        .zip(want.into_iter().chain(std::iter::repeat(VT::Raw64)))
                        .map(|(v, w)| fun.use_as(v, w))
                        .collect();
                    let am: Vec<_> = args.iter().map(|v| (*v).into()).collect();
                    let cs = fun.b.build_direct_call(callee, &am, "lc").expect("call");
                    if let ValueKind::Basic(v) = cs.try_as_basic_value() {
                        fun.stack.push(SV::Reg(v));
                    }
                } else {
                    why("call to an unknown function");
                    fun.stack.push(SV::Unknown);
                }
            }
            Operator::I64Add => fun.binop("add", false),
            Operator::I64Sub => fun.binop("sub", false),
            Operator::I64Mul => fun.binop("mul", false),
            Operator::I64And => fun.binop("and", false),
            Operator::I64Or => fun.binop("or", false),
            Operator::I64Xor => fun.binop("xor", false),
            Operator::I64Shl => fun.binop("shl", false),
            Operator::I64ShrU => fun.binop("lshr", false),
            Operator::I64ShrS => fun.binop("ashr", false),
            Operator::I64DivU => fun.binop("udiv", false),
            Operator::I64DivS => fun.binop("sdiv", false),
            Operator::I64RemU => fun.binop("urem", false),
            Operator::I64RemS => fun.binop("srem", false),
            Operator::I32Add => fun.binop("add", true),
            Operator::I32Sub => fun.binop("sub", true),
            Operator::I32Mul => fun.binop("mul", true),
            Operator::I32And => fun.binop("and", true),
            Operator::I32Or => fun.binop("or", true),
            Operator::I32Xor => fun.binop("xor", true),
            Operator::I32Shl => fun.binop("shl", true),
            Operator::I32ShrU => fun.binop("lshr", true),
            Operator::I32ShrS => fun.binop("ashr", true),
            Operator::I32DivU => fun.binop("udiv", true),
            Operator::I32DivS => fun.binop("sdiv", true),
            Operator::I32RemU => fun.binop("urem", true),
            Operator::I32RemS => fun.binop("srem", true),
            Operator::I64Eq => fun.cmp(IntPredicate::EQ, false),
            Operator::I64Ne => fun.cmp(IntPredicate::NE, false),
            Operator::I64LtU => fun.cmp(IntPredicate::ULT, false),
            Operator::I64GtU => fun.cmp(IntPredicate::UGT, false),
            Operator::I64LeU => fun.cmp(IntPredicate::ULE, false),
            Operator::I64GeU => fun.cmp(IntPredicate::UGE, false),
            Operator::I64LtS => fun.cmp(IntPredicate::SLT, false),
            Operator::I64GtS => fun.cmp(IntPredicate::SGT, false),
            Operator::I64LeS => fun.cmp(IntPredicate::SLE, false),
            Operator::I64GeS => fun.cmp(IntPredicate::SGE, false),
            Operator::I32Eq => fun.cmp(IntPredicate::EQ, true),
            Operator::I32Ne => fun.cmp(IntPredicate::NE, true),
            Operator::I32LtU => fun.cmp(IntPredicate::ULT, true),
            Operator::I32GtU => fun.cmp(IntPredicate::UGT, true),
            Operator::I32LeU => fun.cmp(IntPredicate::ULE, true),
            Operator::I32GeU => fun.cmp(IntPredicate::UGE, true),
            Operator::I32LtS => fun.cmp(IntPredicate::SLT, true),
            Operator::I32GtS => fun.cmp(IntPredicate::SGT, true),
            Operator::I32LeS => fun.cmp(IntPredicate::SLE, true),
            Operator::I32GeS => fun.cmp(IntPredicate::SGE, true),
            Operator::I64Eqz | Operator::I32Eqz => {
                let v = fun.pop();
                let mut iv = fun.use_int(v);
                if matches!(op, Operator::I32Eqz) {
                    iv = fun.narrow(iv);
                }
                let zero = iv.get_type().const_zero();
                let c = fun.b.build_int_compare(IntPredicate::EQ, iv, zero, "eqz").expect("icmp");
                let z = fun.b.build_int_z_extend(c, rt.i64t, "zext").expect("zext");
                fun.stack.push(SV::Reg(z.into()));
            }
            // `select`: the condition is an i32; the values are whatever they are.
            Operator::Select | Operator::TypedSelect { .. } => {
                let c = fun.pop();
                let v2 = fun.pop();
                let v1 = fun.pop();
                let ci = fun.use_int(c);
                let ci = fun.narrow(ci);
                let nz = fun.b.build_int_compare(IntPredicate::NE, ci, ci.get_type().const_zero(), "sel").expect("icmp");
                let (x, y) = (fun.use_int(v1), fun.use_int(v2));
                let r = fun.b.build_select(nz, x, y, "select").expect("select");
                fun.stack.push(SV::Reg(r));
            }
            Operator::I64Clz | Operator::I32Clz | Operator::I64Ctz | Operator::I32Ctz | Operator::I64Popcnt | Operator::I32Popcnt => {
                let v = fun.pop();
                let mut iv = fun.use_int(v);
                let w32 = matches!(op, Operator::I32Clz | Operator::I32Ctz | Operator::I32Popcnt);
                if w32 {
                    iv = fun.narrow(iv);
                }
                let (name, zero_is_poison) = match op {
                    Operator::I64Clz | Operator::I32Clz => ("llvm.ctlz", true),
                    Operator::I64Ctz | Operator::I32Ctz => ("llvm.cttz", true),
                    _ => ("llvm.ctpop", false),
                };
                let intr = inkwell::intrinsics::Intrinsic::find(name)
                    .and_then(|i| i.get_declaration(m, &[iv.get_type().into()]))
                    .expect("bit intrinsic");
                let mut args: Vec<inkwell::values::BasicMetadataValueEnum> = vec![iv.into()];
                if zero_is_poison {
                    args.push(ctx.bool_type().const_zero().into());
                }
                let cs = fun.b.build_call(intr, &args, "bits").expect("call");
                if let ValueKind::Basic(r) = cs.try_as_basic_value() {
                    let r = r.into_int_value();
                    let r = if w32 { fun.widen(r) } else { r };
                    fun.stack.push(SV::Reg(r.into()));
                }
            }
            // Width casts, in an i64-wide model: a wrap is nothing (the i32
            // operations narrow what they use); the extends are real.
            Operator::I32WrapI64 => {}
            // A frame address has no high bits to clear: it stays the frame
            // address, so the slot folds still see it.
            Operator::I64ExtendI32U => match fun.pop() {
                v @ SV::Frame(_) => fun.stack.push(v),
                SV::Const(k) => fun.stack.push(SV::Const(k & 0xffff_ffff)),
                v => {
                    let iv = fun.use_int(v);
                    let iv = fun.narrow(iv);
                    let r = fun.widen(iv);
                    fun.stack.push(SV::Reg(r.into()));
                }
            },
            Operator::I64ExtendI32S | Operator::I64Extend32S | Operator::I64Extend8S | Operator::I64Extend16S | Operator::I32Extend8S | Operator::I32Extend16S => {
                let v = fun.pop();
                let iv = fun.use_int(v);
                let bits = match op {
                    Operator::I64Extend8S | Operator::I32Extend8S => 8,
                    Operator::I64Extend16S | Operator::I32Extend16S => 16,
                    _ => 32,
                };
                let small_t = match bits {
                    8 => ctx.i8_type(),
                    16 => ctx.i16_type(),
                    _ => ctx.i32_type(),
                };
                let small = fun.b.build_int_truncate(iv, small_t, "t").expect("trunc");
                let r = if matches!(op, Operator::I32Extend8S | Operator::I32Extend16S) {
                    let s32 = fun.b.build_int_s_extend(small, ctx.i32_type(), "s").expect("sext");
                    fun.widen(s32)
                } else {
                    fun.b.build_int_s_extend(small, rt.i64t, "s").expect("sext")
                };
                fun.stack.push(SV::Reg(r.into()));
            }
            // Through the table: a load of the function pointer, a call by type.
            Operator::CallIndirect { type_index, .. } => {
                let (np, nr) = md
                    .types
                    .0
                    .get(*type_index as usize)
                    .and_then(|st| match &st.composite_type.inner {
                        wasmparser::CompositeInnerType::Func(ft) => Some((ft.params().len(), ft.results().len())),
                        _ => None,
                    })
                    .unwrap_or((0, 0));
                let idx = fun.pop();
                let mut a: Vec<SV> = (0..np).map(|_| fun.pop()).collect();
                a.reverse();
                let Some(tbl) = table_global(ctx, m, md, local_sigs, rt) else {
                    why("call_indirect without a table");
                    if nr > 0 {
                        fun.stack.push(SV::Unknown);
                    }
                    continue;
                };
                let ii = fun.use_int(idx);
                let pt = ctx.ptr_type(AddressSpace::default());
                let arr_t = pt.array_type(md.table.len() as u32);
                let slot = unsafe { fun.b.build_in_bounds_gep(arr_t, tbl.as_pointer_value(), &[rt.i64t.const_zero(), ii], "tbl") }.expect("gep");
                let fp = fun.b.build_load(pt, slot, "fp").expect("load").into_pointer_value();
                let ps: Vec<BasicMetadataTypeEnum> = (0..np).map(|_| rt.i64t.into()).collect();
                let fty = if nr == 0 { ctx.void_type().fn_type(&ps, false) } else { rt.i64t.fn_type(&ps, false) };
                let args: Vec<inkwell::values::BasicMetadataValueEnum> = a.into_iter().map(|v| fun.use_as(v, VT::Raw64).into()).collect();
                let cs = fun.b.build_indirect_call(fty, fp, &args, "ic").expect("call");
                if let ValueKind::Basic(v) = cs.try_as_basic_value() {
                    fun.stack.push(SV::Reg(v));
                }
            }
            // Anything unmodelled yields bottom, never a plausible value -- but
            // pops exactly what it consumes. A blanket push here left a
            // phantom on the stack, and the `global.set 0` in every Rust
            // epilogue then made `return` hand back the phantom, not the value.
            _ => {
                let (pops, pushes) = op.operator_arity(&md.types).unwrap_or((0, 1));
                for _ in 0..pops {
                    fun.pop();
                }
                for _ in 0..pushes {
                    why(&format!("{op:?}").split(|c| c == ' ' || c == '{').next().unwrap_or("op").to_string());
                    fun.stack.push(SV::Unknown);
                }
            }
        }
    }

    // Drop blocks nothing can reach: continuations every path left early, and
    // labels opened inside dead code. Leaving them in would inflate the bottom
    // count with returns no execution reaches -- the same dishonest metric this
    // tool is a reaction to. A block's uses ARE its predecessors, so LLVM
    // answers this for us; iterate, because deleting one can orphan the next.
    loop {
        let mut dropped = false;
        for bb in f.get_basic_blocks() {
            if bb == entry || bb.get_first_use().is_some() {
                continue;
            }
            if bb.remove_from_function().is_ok() {
                dropped = true;
            }
        }
        if !dropped {
            break;
        }
    }

    // Every surviving block must end in a terminator. The body's own `end`
    // returns its value above, so the one candidate left is `exit`, reached by
    // a `br_if`/`br_table` aimed at the function's own label.
    // diver: that value is not threaded to `exit`, so a conditional return
    // is bottom -- honest; thread it through an alloca if a corpus shows one.
    let blocks = f.get_basic_blocks();
    for bb in blocks {
        if bb.get_terminator().is_some() {
            continue;
        }
        fun.b.position_at_end(bb);
        if n_results == 0 {
            fun.b.build_return(None).expect("ret");
        } else {
            let uf = if val_abi { rt.unknown_val } else { rt.unknown_i64 };
            let v = fun.call1(uf, &[], "bottom");
            fun.b.build_return(Some(&v)).expect("ret");
        }
    }
    Ok(())
}

/// Parse a contract and lower it. Returns the IR, or the verifier's complaint.
pub(crate) fn const_expr(e: &wasmparser::ConstExpr) -> Option<i64> {
    match e.get_operators_reader().read().ok()? {
        Operator::I32Const { value } => Some(value as i64),
        Operator::I64Const { value } => Some(value),
        _ => None,
    }
}

/// Linear memory for the optimiser. An address is an integer and an access is
/// `inttoptr` of it. A frame address is `ptrtoint` of the frame alloca, so
/// `inttoptr(ptrtoint(frame) + k)` folds back to the alloca and the optimiser
/// sees function-local memory; every other address is an opaque pointer, and
/// two of those may alias, which is the truth.
pub(crate) fn define_memory<'ctx>(ctx: &'ctx Context, m: &Module<'ctx>, rt: &Rt<'ctx>) {
    let pt = ctx.ptr_type(AddressSpace::default());
    let b = ctx.create_builder();
    let inl = attr(ctx, "alwaysinline", 0);
    for (name, bits, signed) in LOADS {
        let f = m.get_function(&format!("soroban.{name}")).expect("declared");
        f.add_attribute(AttributeLoc::Function, inl);
        f.set_linkage(Linkage::Internal);
        let a = f.get_first_param().expect("addr").into_int_value();
        b.position_at_end(ctx.append_basic_block(f, "entry"));
        let p = b.build_int_to_ptr(a, pt, "p").expect("inttoptr");
        let v = b.build_load(int_ty(ctx, bits), p, "v").expect("load");
        let _ = v.as_instruction_value().expect("inst").set_alignment(1);
        let v = v.into_int_value();
        let w = if bits == 64 {
            v
        } else if signed {
            b.build_int_s_extend(v, rt.i64t, "sx").expect("sext")
        } else {
            b.build_int_z_extend(v, rt.i64t, "zx").expect("zext")
        };
        b.build_return(Some(&w)).expect("ret");
    }
    for (name, bits) in STORES {
        let f = m.get_function(&format!("soroban.{name}")).expect("declared");
        f.add_attribute(AttributeLoc::Function, inl);
        f.set_linkage(Linkage::Internal);
        let a = f.get_nth_param(0).expect("addr").into_int_value();
        let v = f.get_nth_param(1).expect("val").into_int_value();
        b.position_at_end(ctx.append_basic_block(f, "entry"));
        let t = if bits == 64 {
            v
        } else {
            b.build_int_truncate(v, int_ty(ctx, bits), "t").expect("trunc")
        };
        let p = b.build_int_to_ptr(a, pt, "p").expect("inttoptr");
        let _ = b.build_store(p, t).expect("store").set_alignment(1);
        b.build_return(None).expect("ret");
    }
}
