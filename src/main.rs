//! Soroban wasm -> typed LLVM IR, built through inkwell.
//!
//! Three invariants, each one killing a decompiler bug class found in the wild:
//!
//! 1. `%Val` is a named struct type, NOT `i64`, and every Val<->i64 crossing is
//!    an explicit call to a declared conversion. Because the call site's
//!    function type is pinned to the callee's declaration (that is what
//!    `build_direct_call` does), passing an integer where a Val is declared is
//!    a `module.verify()` error. Hand-written `.ll` text cannot check this: the
//!    parser derives the call-site type from whatever was written, so a wrong
//!    type is written twice and stays self-consistent.
//! 2. Branch targets are `BasicBlock` handles resolved against the full
//!    enclosing label stack. An out-of-range depth is a hard error, and a
//!    `switch` names a real block for every case plus the default, so no
//!    `br_table` arm can be dropped.
//! 3. `Unknown` is bottom: it materialises only as a call to
//!    `@ponytail.unknown`. There is no literal for a pass to substitute.
//!
//! `--inline` then hands the module to LLVM: helpers become internal, O1's
//! inliner folds the SDK's plumbing into the export, and reads of the data
//! segment become the constants they are, so each syscall shows its
//! arguments. Nothing is guessed there; every step is an LLVM transformation
//! of a faithful module.
use std::collections::HashMap;
use std::fmt::Write as _;

use inkwell::attributes::{Attribute, AttributeLoc};
use inkwell::basic_block::BasicBlock;
use inkwell::builder::Builder;
use inkwell::context::Context;
use inkwell::module::{Linkage, Module};
use inkwell::passes::PassBuilderOptions;
use inkwell::targets::{CodeModel, InitializationConfig, RelocMode, Target, TargetMachine};
use inkwell::types::{AnyTypeEnum, BasicMetadataTypeEnum, BasicTypeEnum, IntType, StructType};
use inkwell::values::{
    AnyValue, AsValueRef, BasicValue, BasicValueEnum, CallSiteValue, FunctionValue, InstructionOpcode,
    InstructionValue, IntValue, Operand, PointerValue, ValueKind,
};
use inkwell::{IntPredicate, OptimizationLevel};
use wasmparser::{ExternalKind, Operator, Parser, Payload};

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum VT {
    /// A tagged 64-bit Soroban value. Lowers to `%Val`.
    Val,
    /// A raw machine integer crossing the host boundary. Lowers to `i64`.
    Raw64,
    /// `StorageType`: a direct-marshalled enum, 0/1/2. Lowers to `i64`.
    Storage,
}

pub struct HostFn {
    pub module: &'static str,
    pub code: &'static str,
    pub name: &'static str,
    pub args: &'static [VT],
    pub arg_tys: &'static [&'static str],
    pub ret: VT,
    pub ret_ty: &'static str,
}

include!(concat!(env!("OUT_DIR"), "/hostfns.rs"));

const SMALL_TAGS: [&str; 15] = [
    "False", "True", "Void", "Error", "U32Val", "I32Val", "U64Small", "I64Small", "TimepointSmall",
    "DurationSmall", "U128Small", "I128Small", "U256Small", "I256Small", "SymbolSmall",
];

fn decode_symbol_small(body: u64) -> Option<String> {
    let mut s = String::new();
    for i in (0..9).rev() {
        let c = ((body >> (i * 6)) & 0x3f) as u8;
        if c == 0 {
            continue;
        }
        s.push(match c {
            1 => '_',
            2..=11 => (b'0' + c - 2) as char,
            12..=37 => (b'A' + c - 12) as char,
            38..=63 => (b'a' + c - 38) as char,
            _ => return None,
        });
    }
    (!s.is_empty()).then_some(s)
}

/// What a `Val`-typed constant actually means.
pub fn explain_val(payload: u64) -> String {
    let tag = (payload & 0xff) as usize;
    let body = payload >> 8;
    match tag {
        0 => "false".into(),
        1 => "true".into(),
        2 => "void".into(),
        3 => format!("Error(type {}, code {})", body & 0xff_ffff, body >> 24),
        4 => format!("u32 {}", body >> 24),
        5 => format!("i32 {}", (body >> 24) as i32),
        14 => decode_symbol_small(body & 0x3f_ffff_ffff_ffff)
            .map(|s| format!("Symbol({s:?})"))
            .unwrap_or_else(|| "SymbolSmall(?)".into()),
        t if t < 15 => format!("{} {}", SMALL_TAGS[t], body),
        t if (64..79).contains(&t) => format!("object handle {} (frame-relative)", body >> 24),
        t => format!("BAD tag {t}"),
    }
}

/// Text as an LLVM-safe SSA name.
fn ident(s: &str) -> String {
    let mut o: String = s.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '_' }).collect();
    o.truncate(40);
    o
}

/// The decode, as an LLVM-safe SSA name. inkwell emits no comments, so the
/// meaning rides on the value name instead -- which is strictly better: it is
/// machine-readable and survives optimisation passes.
fn val_name(payload: u64) -> String {
    ident(&format!("v_{}", explain_val(payload)))
}

/// A value on the abstract wasm operand stack.
#[derive(Clone, Copy)]
enum SV<'ctx> {
    /// A wasm constant, not yet committed to a type. The consumer decides,
    /// from the host ABI -- never guessed.
    Const(i64),
    /// An emitted LLVM value. Its type is carried by the value itself, so there
    /// is no separate tag that could disagree with reality.
    Reg(BasicValueEnum<'ctx>),
    /// Bottom.
    Unknown,
}

#[derive(Clone, Copy)]
struct Lbl<'ctx> {
    /// Where a `br` to this depth goes: a loop header, or a continuation.
    target: BasicBlock<'ctx>,
    /// Where `End` falls through to. Differs from `target` only for a loop.
    cont: BasicBlock<'ctx>,
    /// An `if`'s else arm, until `Else` claims it. Left `Some` at `End` means
    /// the arm is empty and still needs a block, because the conditional branch
    /// already names it.
    else_bb: Option<BasicBlock<'ctx>>,
}

/// `StorageType` is not a `Val` -- it is a direct-marshalled u64 with three
/// legal values. Naming them is the difference between `i64 1` and `Persistent`.
fn storage_name(c: i64) -> String {
    match c {
        0 => "Temporary".into(),
        1 => "Persistent".into(),
        2 => "Instance".into(),
        // Not a value the host accepts; say so rather than inventing a name.
        n => format!("StorageType_invalid_{n}"),
    }
}

/// Only what `Operator::operator_arity` needs to size the fallback in `lower`:
/// the type section, for `call_indirect`. Labels and direct calls are lowered
/// explicitly, so the rest is never consulted.
#[derive(Default)]
struct Types(Vec<wasmparser::SubType>);

/// Linear memory as the binary declares it: the initialised data segments, the
/// wasm globals' initial values, and whether any store in the module targets a
/// segment at a constant address. A load from an unwritten segment at a
/// constant address IS a constant -- that is where `&true` and the static keys
/// behind every outlined `storage().set` live.
/// ponytail: a store through a pointer into a segment is invisible here. Rust
/// keeps mutable statics out of rodata, so this is the decompiler's usual bet;
/// `written` catches the direct `static mut` case.
#[derive(Default)]
struct Mem {
    segs: Vec<(u64, Vec<u8>)>,
    written: bool,
    /// (initial value, mutable), by global index.
    globals: Vec<(i64, bool)>,
}

impl Mem {
    fn bytes(&self, addr: u64, n: usize) -> Option<&[u8]> {
        if self.written {
            return None;
        }
        self.segs.iter().find_map(|(base, d)| {
            let off = addr.checked_sub(*base)? as usize;
            d.get(off..off.checked_add(n)?)
        })
    }

    /// A `bits`-wide load at a constant address, as the i64 the model carries.
    fn load(&self, addr: u64, bits: u32, signed: bool) -> Option<i64> {
        let b = self.bytes(addr, (bits / 8) as usize)?;
        let v = b.iter().enumerate().fold(0u64, |v, (i, x)| v | ((*x as u64) << (8 * i)));
        Some(if signed && bits < 64 { ((v << (64 - bits)) as i64) >> (64 - bits) } else { v as i64 })
    }
}

#[derive(Default)]
struct Mod {
    types: Types,
    mem: Mem,
}

/// A wasm load or store, reduced to what the i64-wide model needs.
enum Acc {
    Load { bits: u32, signed: bool, off: u64 },
    Store { bits: u32, off: u64 },
}

fn mem_access(op: &Operator) -> Option<Acc> {
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
const LOADS: [(&str, u32, bool); 7] = [
    ("load8u", 8, false),
    ("load8s", 8, true),
    ("load16u", 16, false),
    ("load16s", 16, true),
    ("load32u", 32, false),
    ("load32s", 32, true),
    ("load64", 64, false),
];
const STORES: [(&str, u32); 4] = [("store8", 8), ("store16", 16), ("store32", 32), ("store64", 64)];

/// LLVM `memory(...)` attribute encodings: none, and inaccessiblemem: readwrite.
const MEM_NONE: u64 = 0;
const MEM_INACCESSIBLE_RW: u64 = 12;

fn attr(ctx: &Context, name: &str, v: u64) -> Attribute {
    ctx.create_enum_attribute(Attribute::get_named_enum_kind_id(name), v)
}

fn int_ty(ctx: &Context, bits: u32) -> IntType<'_> {
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
struct Rt<'ctx> {
    val: StructType<'ctx>,
    i64t: IntType<'ctx>,
    from_payload: FunctionValue<'ctx>,
    payload: FunctionValue<'ctx>,
    /// Same trick as `from_payload`: gives a decoded constant a name slot,
    /// because LLVM has nowhere to hang a name on a literal operand.
    storage_type: FunctionValue<'ctx>,
    unknown_val: FunctionValue<'ctx>,
    unknown_i64: FunctionValue<'ctx>,
    /// wasm `unreachable` is a trap the host observes, not LLVM's "never
    /// happens": lowered bare, O1 turns the guard in front of it into an
    /// `llvm.assume` and the check vanishes from the output.
    trap: FunctionValue<'ctx>,
}

impl<'ctx> Rt<'ctx> {
    fn new(ctx: &'ctx Context, m: &Module<'ctx>) -> Self {
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
            unknown_val: m.add_function("ponytail.unknown", val.fn_type(&[], false), None),
            unknown_i64: m.add_function("ponytail.unknown.i64", i64t.fn_type(&[], false), None),
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

    fn ty(&self, v: VT) -> BasicTypeEnum<'ctx> {
        match v {
            VT::Val => self.val.into(),
            VT::Raw64 | VT::Storage => self.i64t.into(),
        }
    }
}

struct Fun<'ctx, 'a> {
    ctx: &'ctx Context,
    b: &'a Builder<'ctx>,
    rt: &'a Rt<'ctx>,
    f: FunctionValue<'ctx>,
    locals: Vec<PointerValue<'ctx>>,
    stack: Vec<SV<'ctx>>,
    labels: Vec<Lbl<'ctx>>,
    imports: &'a HashMap<u32, &'static HostFn>,
    n: usize,
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
        self.stack.pop().unwrap_or(SV::Unknown)
    }

    /// A linear-memory access. A constant address inside an unwritten data
    /// segment reads as the constant it is; everything else goes through the
    /// `soroban.load*`/`store*` helpers, which `--inline` defines as plain
    /// accesses to `@mem` so LLVM can forward stores to loads, and then
    /// `fold_data_loads` reads what inlining has just made constant.
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
                let ea = self.addr(a, off);
                let f = m.get_function(&format!("soroban.store{bits}")).expect("store helper");
                self.b.build_direct_call(f, &[ea.into(), vi.into()], "").expect("call");
            }
        }
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

    fn binop(&mut self, op: &str) {
        let b = self.pop();
        let a = self.pop();
        let (x, y) = (self.use_int(a), self.use_int(b));
        let r = match op {
            "add" => self.b.build_int_add(x, y, "add"),
            "sub" => self.b.build_int_sub(x, y, "sub"),
            "mul" => self.b.build_int_mul(x, y, "mul"),
            "and" => self.b.build_and(x, y, "and"),
            "or" => self.b.build_or(x, y, "or"),
            "xor" => self.b.build_xor(x, y, "xor"),
            "shl" => self.b.build_left_shift(x, y, "shl"),
            "lshr" => self.b.build_right_shift(x, y, false, "lshr"),
            _ => self.b.build_right_shift(x, y, true, "ashr"),
        }
        .expect("binop");
        self.stack.push(SV::Reg(r.into()));
    }

    fn cmp(&mut self, p: IntPredicate) {
        let b = self.pop();
        let a = self.pop();
        let (x, y) = (self.use_int(a), self.use_int(b));
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
        let n = self.labels.len();
        let d = depth as usize;
        if d >= n {
            return Err(format!("branch depth {d} exceeds label stack {n}"));
        }
        Ok(self.labels[n - 1 - d].target)
    }
}

fn pair_ends(ops: &[Operator]) -> HashMap<usize, usize> {
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
fn lower<'ctx>(
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

    let exit = ctx.append_basic_block(f, "exit");
    fun.labels.push(Lbl {
        target: exit,
        cont: exit,
        else_bb: None,
    });

    for (i, op) in ops.iter().enumerate() {
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
            Operator::GlobalGet { global_index } => match m.get_global(&format!("g{global_index}")) {
                Some(g) => {
                    let v = fun.b.build_load(rt.i64t, g.as_pointer_value(), &format!("g{global_index}")).expect("load");
                    fun.stack.push(SV::Reg(v));
                }
                None => fun.stack.push(SV::Unknown),
            },
            Operator::GlobalSet { global_index } => {
                let v = fun.pop();
                let iv = fun.use_int(v);
                if let Some(g) = m.get_global(&format!("g{global_index}")) {
                    fun.b.build_store(g.as_pointer_value(), iv).expect("store");
                }
            }
            Operator::Block { .. } => {
                let cont = fun.blk("c");
                fun.labels.push(Lbl { target: cont, cont, else_bb: None });
            }
            Operator::Loop { .. } => {
                let h = fun.blk("h");
                fun.br(h);
                fun.b.position_at_end(h);
                let cont = fun.blk("lc");
                fun.labels.push(Lbl { target: h, cont, else_bb: None });
            }
            Operator::If { .. } => {
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
                fun.labels.push(Lbl { target: cont, cont, else_bb: Some(else_bb) });
                fun.b.position_at_end(then_bb);
                let _ = i;
            }
            Operator::Else => {
                let (cont, eb) = match fun.labels.last_mut() {
                    Some(l) => (l.cont, l.else_bb.take()),
                    None => return Err("else with no frame".into()),
                };
                fun.br(cont);
                if let Some(bb) = eb {
                    fun.b.position_at_end(bb);
                }
                fun.stack.clear();
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
                fun.br(fr.cont);
                // An `if` with no `else`: the branch already names that block,
                // so it must exist and reach the continuation.
                if let Some(bb) = fr.else_bb {
                    fun.b.position_at_end(bb);
                    fun.br(fr.cont);
                }
                fun.b.position_at_end(fr.cont);
                // ponytail: no cross-block operand-stack threading; locals go
                // through allocas and mem2reg builds the phis.
                fun.stack.clear();
            }
            Operator::Br { relative_depth } => {
                let t = fun.target(*relative_depth)?;
                if t == exit {
                    fun.ret(n_results, val_abi);
                } else {
                    fun.br(t);
                }
            }
            Operator::BrIf { relative_depth } => {
                let t = fun.target(*relative_depth)?;
                let c = fun.pop();
                let ci = fun.use_int(c);
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
                for (idx, d) in targets.targets().enumerate() {
                    let d = d.map_err(|e| e.to_string())?;
                    cases.push((ctx.i32_type().const_int(idx as u64, false), fun.target(d)?));
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
                let Some(p) = fun.locals.get(*local_index as usize).copied() else {
                    fun.stack.push(SV::Unknown);
                    continue;
                };
                let v = fun.b.build_load(rt.i64t, p, "get").expect("load");
                fun.stack.push(SV::Reg(v));
            }
            Operator::LocalSet { local_index } | Operator::LocalTee { local_index } => {
                let v = fun.pop();
                let iv = fun.use_int(v);
                if let Some(p) = fun.locals.get(*local_index as usize).copied() {
                    fun.b.build_store(p, iv).expect("store");
                }
                if matches!(op, Operator::LocalTee { .. }) {
                    fun.stack.push(SV::Reg(iv.into()));
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
                    let fname = format!("f{function_index}");
                    let callee = m.get_function(&fname).unwrap_or_else(|| {
                        let ps: Vec<BasicMetadataTypeEnum> =
                            (0..np).map(|_| rt.i64t.into()).collect();
                        let t = if nr == 0 {
                            ctx.void_type().fn_type(&ps, false)
                        } else {
                            rt.i64t.fn_type(&ps, false)
                        };
                        m.add_function(&fname, t, None)
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
                    fun.stack.push(SV::Unknown);
                }
            }
            Operator::I64Add | Operator::I32Add => fun.binop("add"),
            Operator::I64Sub | Operator::I32Sub => fun.binop("sub"),
            Operator::I64Mul | Operator::I32Mul => fun.binop("mul"),
            Operator::I64And | Operator::I32And => fun.binop("and"),
            Operator::I64Or | Operator::I32Or => fun.binop("or"),
            Operator::I64Xor | Operator::I32Xor => fun.binop("xor"),
            Operator::I64Shl | Operator::I32Shl => fun.binop("shl"),
            Operator::I64ShrU | Operator::I32ShrU => fun.binop("lshr"),
            Operator::I64ShrS | Operator::I32ShrS => fun.binop("ashr"),
            Operator::I64Eq | Operator::I32Eq => fun.cmp(IntPredicate::EQ),
            Operator::I64Ne | Operator::I32Ne => fun.cmp(IntPredicate::NE),
            Operator::I64LtU | Operator::I32LtU => fun.cmp(IntPredicate::ULT),
            Operator::I64GtU | Operator::I32GtU => fun.cmp(IntPredicate::UGT),
            Operator::I64LtS | Operator::I32LtS => fun.cmp(IntPredicate::SLT),
            Operator::I64GtS | Operator::I32GtS => fun.cmp(IntPredicate::SGT),
            Operator::I64Eqz | Operator::I32Eqz => {
                let v = fun.pop();
                let iv = fun.use_int(v);
                let c = fun
                    .b
                    .build_int_compare(IntPredicate::EQ, iv, rt.i64t.const_zero(), "eqz")
                    .expect("icmp");
                let z = fun.b.build_int_z_extend(c, rt.i64t, "zext").expect("zext");
                fun.stack.push(SV::Reg(z.into()));
            }
            // ponytail: the value model is i64-wide, so width casts are identity.
            Operator::I32WrapI64
            | Operator::I64ExtendI32U
            | Operator::I64ExtendI32S
            | Operator::I64Extend32S
            | Operator::I32Extend8S
            | Operator::I32Extend16S => {}
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
    // ponytail: that value is not threaded to `exit`, so a conditional return
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

fn main() {
    let mut args = std::env::args().skip(1);
    let Some(path) = args.next() else {
        eprintln!("usage: ponytail-wasm <contract.wasm> [export|--all|--inline]");
        std::process::exit(2);
    };
    let only = args.next();
    let wasm = std::fs::read(&path).expect("read wasm");
    match lower_module(&wasm, only.as_deref()) {
        Ok(ir) => print!("{ir}"),
        Err(e) => {
            eprintln!("ponytail-wasm: module does not verify:\n{e}");
            std::process::exit(1);
        }
    }
}

/// Parse a contract and lower it. Returns the IR, or the verifier's complaint.
fn const_expr(e: &wasmparser::ConstExpr) -> Option<i64> {
    match e.get_operators_reader().read().ok()? {
        Operator::I32Const { value } => Some(value as i64),
        Operator::I64Const { value } => Some(value),
        _ => None,
    }
}

/// Does any store in the module target a data segment at a constant address?
/// Constants are tracked through straight-line code only; a control-flow
/// operator clears what is known. Enough to catch a `static mut` counter,
/// which is how Rust actually writes its own data segment.
fn writes_data(
    bodies: &[(usize, Vec<Operator>)],
    md: &Mod,
    imports: &HashMap<u32, &'static HostFn>,
    local_sigs: &HashMap<u32, (usize, usize)>,
) -> bool {
    for (_, ops) in bodies {
        let mut st: Vec<Option<u64>> = Vec::new();
        for op in ops {
            if let Some(Acc::Store { off, .. }) = mem_access(op) {
                st.pop();
                if let Some(Some(a)) = st.pop() {
                    if md.mem.bytes(a.wrapping_add(off), 1).is_some() {
                        return true;
                    }
                }
                continue;
            }
            let (pops, pushes) = match op {
                Operator::I32Const { value } => {
                    st.push(Some(*value as u32 as u64));
                    continue;
                }
                Operator::Call { function_index } => imports
                    .get(function_index)
                    .map(|h| (h.args.len() as u32, 1))
                    .or_else(|| local_sigs.get(function_index).map(|(p, r)| (*p as u32, *r as u32)))
                    .unwrap_or((0, 0)),
                Operator::Block { .. }
                | Operator::Loop { .. }
                | Operator::If { .. }
                | Operator::Else
                | Operator::End
                | Operator::Br { .. }
                | Operator::BrIf { .. }
                | Operator::BrTable { .. }
                | Operator::Return
                | Operator::Unreachable => {
                    st.clear();
                    continue;
                }
                _ => op.operator_arity(&md.types).unwrap_or((0, 0)),
            };
            for _ in 0..pops {
                st.pop();
            }
            for _ in 0..pushes {
                st.push(None);
            }
        }
    }
    false
}

/// Linear memory for the optimiser: `@mem`, the whole address space, contents
/// unknown. The helpers become plain byte-addressed accesses to it, so BasicAA
/// sees `sp-24` and `sp-32` as distinct slots and GVN forwards stores to loads
/// across the inlined SDK plumbing.
fn define_memory<'ctx>(ctx: &'ctx Context, m: &Module<'ctx>, rt: &Rt<'ctx>) {
    let i8t = ctx.i8_type();
    let memg = m.add_global(i8t, None, "mem").as_pointer_value();
    let b = ctx.create_builder();
    let inl = attr(ctx, "alwaysinline", 0);
    for (name, bits, signed) in LOADS {
        let f = m.get_function(&format!("soroban.{name}")).expect("declared");
        f.add_attribute(AttributeLoc::Function, inl);
        f.set_linkage(Linkage::Internal);
        let a = f.get_first_param().expect("addr").into_int_value();
        b.position_at_end(ctx.append_basic_block(f, "entry"));
        let p = unsafe { b.build_gep(i8t, memg, &[a], "p") }.expect("gep");
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
        let p = unsafe { b.build_gep(i8t, memg, &[a], "p") }.expect("gep");
        let _ = b.build_store(p, t).expect("store").set_alignment(1);
        b.build_return(None).expect("ret");
    }
}

/// LLVM does the interpretation: inlining collapses the SDK's plumbing into
/// the export and constants reach the syscalls. O1 and not higher: O2's
/// simplifycfg turns a `switch` into a lookup table, hiding the very arms this
/// tool exists to keep.
fn optimize(m: &Module, mem: &Mem) -> Result<(), String> {
    Target::initialize_native(&InitializationConfig::default())?;
    let triple = TargetMachine::get_default_triple();
    let tm = Target::from_triple(&triple)
        .map_err(|e| e.to_string())?
        .create_target_machine(&triple, "generic", "", OptimizationLevel::Less, RelocMode::Default, CodeModel::Default)
        .ok_or("no target machine")?;
    m.set_data_layout(&tm.get_target_data().get_data_layout());
    let run = |p: &str| m.run_passes(p, &tm, PassBuilderOptions::create()).map_err(|e| e.to_string());
    run("default<O1>")?;
    // A data-segment constant can feed a Val, a branch, or another address:
    // fold, let LLVM propagate, repeat until nothing new is constant.
    for _ in 0..4 {
        if fold_data_loads(m, mem) == 0 {
            break;
        }
        run("instcombine,gvn,simplifycfg,dce")?;
    }
    Ok(())
}

/// A load from `@mem` whose address inlining has made constant is a read of
/// the data segment, if the address falls in one: replace it with the bytes.
/// LLVM has folded such an address into a constant `getelementptr`
/// expression, which inkwell does not unpack, so this reads it via the C API.
fn fold_data_loads(m: &Module, mem: &Mem) -> usize {
    let Some(memg) = m.get_global("mem") else { return 0 };
    let base = memg.as_pointer_value().as_value_ref();
    let mut n = 0;
    for f in m.get_functions() {
        for bb in f.get_basic_blocks() {
            let mut cur = bb.get_first_instruction();
            while let Some(i) = cur {
                cur = i.get_next_instruction();
                if i.get_opcode() != InstructionOpcode::Load {
                    continue;
                }
                let Some(Operand::Value(BasicValueEnum::PointerValue(p))) = i.get_operand(0) else { continue };
                let Some(addr) = const_gep_offset(p, base) else { continue };
                let AnyTypeEnum::IntType(t) = i.get_type() else { continue };
                let Some(v) = mem.load(addr, t.get_bit_width(), false) else { continue };
                i.as_any_value_enum().into_int_value().replace_all_uses_with(t.const_int(v as u64, false));
                i.erase_from_basic_block();
                n += 1;
            }
        }
    }
    n
}

/// `getelementptr (i8, ptr @mem, i64 K)` as a constant expression -> K.
fn const_gep_offset(p: PointerValue, base: inkwell::llvm_sys::prelude::LLVMValueRef) -> Option<u64> {
    use inkwell::llvm_sys::core::*;
    use inkwell::llvm_sys::LLVMOpcode;
    unsafe {
        let r = p.as_value_ref();
        if LLVMIsAConstantExpr(r).is_null()
            || LLVMGetConstOpcode(r) != LLVMOpcode::LLVMGetElementPtr
            || LLVMGetNumOperands(r) != 2
            || LLVMGetOperand(r, 0) != base
        {
            return None;
        }
        let k = LLVMGetOperand(r, 1);
        (!LLVMIsAConstantInt(k).is_null()).then(|| LLVMConstIntGetZExtValue(k))
    }
}

/// Names for what folding has just made constant: a `from_payload` of a
/// literal reads as the Val it is, a StorageType literal as its variant, and a
/// `*_from_linear_memory` call with constant position and length as the
/// symbol, string or Val list sitting in the data segment.
fn rename_decoded(m: &Module, mem: &Mem) {
    let b = m.get_context().create_builder();
    let st = m.get_function("soroban.storage_type").unwrap_or_else(|| {
        // O1 strips unused declarations; bring it back for the literals below.
        let i64t = m.get_context().i64_type();
        m.add_function("soroban.storage_type", i64t.fn_type(&[i64t.into()], false), None)
    });
    for f in m.get_functions() {
        for bb in f.get_basic_blocks() {
            let mut cur = bb.get_first_instruction();
            while let Some(i) = cur {
                cur = i.get_next_instruction();
                let Ok(cs) = CallSiteValue::try_from(i) else { continue };
                let Some(callee) = cs.get_called_fn_value() else { continue };
                let name = callee.get_name().to_string_lossy().into_owned();
                let args: Vec<Option<u64>> = (0..cs.count_arguments()).map(|k| const_arg(i, k)).collect();
                // A StorageType that inlining turned into a literal has no name
                // slot; give it the one emission uses.
                if let Some(h) = HOST_FNS.iter().find(|h| h.name == name) {
                    for (k, _) in h.args.iter().enumerate().filter(|(_, vt)| **vt == VT::Storage) {
                        let Some(Operand::Value(BasicValueEnum::IntValue(v))) = i.get_operand(k as u32) else { continue };
                        let Some(c) = args[k] else { continue };
                        b.position_before(&i);
                        let named = b.build_direct_call(st, &[v.into()], &storage_name(c as i64)).expect("call");
                        if let ValueKind::Basic(nv) = named.try_as_basic_value() {
                            i.set_operand(k as u32, nv);
                        }
                    }
                }
                let new = match name.as_str() {
                    "soroban.val.from_payload" => args.first().copied().flatten().map(val_name),
                    "soroban.storage_type" => args.first().copied().flatten().map(|c| storage_name(c as i64)),
                    n => decode_lm(n, &args, mem),
                };
                if let (Some(n), ValueKind::Basic(v)) = (new, cs.try_as_basic_value()) {
                    v.set_name(&n);
                }
            }
        }
    }
}

/// A call argument that is a constant, or a `%Val` made by `from_payload` of one.
fn const_arg(i: InstructionValue, k: u32) -> Option<u64> {
    match i.get_operand(k)? {
        Operand::Value(BasicValueEnum::IntValue(v)) if v.is_constant_int() => v.get_zero_extended_constant(),
        Operand::Value(BasicValueEnum::StructValue(s)) => {
            let def = s.as_instruction_value()?;
            let cs = CallSiteValue::try_from(def).ok()?;
            let from_payload = cs.get_called_fn_value()?.get_name().to_bytes() == b"soroban.val.from_payload";
            from_payload.then(|| const_arg(def, 0)).flatten()
        }
        _ => None,
    }
}

fn decode_lm(name: &str, args: &[Option<u64>], mem: &Mem) -> Option<String> {
    // Positions and lengths cross the boundary as U32Vals: tag 4, value in the top 32 bits.
    let u = |k: usize| args.get(k).copied().flatten().filter(|p| p & 0xff == 4).map(|p| p >> 32);
    let text = |k: usize| -> Option<String> {
        Some(String::from_utf8_lossy(mem.bytes(u(k)?, u(k + 1)? as usize)?).into_owned())
    };
    let vals = |pos: u64, len: u64| -> Option<Vec<String>> {
        (0..len).map(|i| mem.load(pos + 8 * i, 64, false).map(|v| explain_val(v as u64))).collect()
    };
    let s = match name {
        "buf.symbol_new_from_linear_memory" => format!("Symbol({:?})", text(0)?),
        "buf.string_new_from_linear_memory" => format!("String({:?})", text(0)?),
        "buf.bytes_new_from_linear_memory" => {
            let hex: String = mem.bytes(u(0)?, u(1)? as usize)?.iter().map(|b| format!("{b:02x}")).collect();
            format!("Bytes({hex})")
        }
        "vec.vec_new_from_linear_memory" => format!("Vec[{}]", vals(u(0)?, u(1)?)?.join(", ")),
        // Keys are Symbols in memory; the values are runtime Vals, not decoded here.
        "map.map_new_from_linear_memory" => format!("Map{{{}}}", vals(u(0)?, u(2)?)?.join(", ")),
        _ => return None,
    };
    Some(ident(&s))
}

fn lower_module(wasm: &[u8], only: Option<&str>) -> Result<String, String> {
    let by_code: HashMap<(&str, &str), &HostFn> =
        HOST_FNS.iter().map(|h| ((h.module, h.code), h)).collect();

    let mut imports: HashMap<u32, &'static HostFn> = HashMap::new();
    let mut n_imports = 0u32;
    let mut bodies: Vec<(usize, Vec<Operator>)> = Vec::new();
    let mut exports: Vec<(String, u32)> = Vec::new();
    let mut sigs: Vec<(usize, usize)> = Vec::new();
    let mut func_types: Vec<u32> = Vec::new();
    let mut types = Types(Vec::new());
    let mut mem = Mem::default();

    for p in Parser::new(0).parse_all(wasm) {
        match p.expect("parse") {
            Payload::TypeSection(r) => {
                for rg in r {
                    for st in rg.expect("rec group").into_types() {
                        if let wasmparser::CompositeInnerType::Func(ft) = &st.composite_type.inner {
                            sigs.push((ft.params().len(), ft.results().len()));
                        } else {
                            sigs.push((0, 0));
                        }
                        types.0.push(st);
                    }
                }
            }
            Payload::ImportSection(r) => {
                for group in r {
                    for im in group.expect("import group") {
                        let (_, im) = im.expect("import");
                        if let wasmparser::TypeRef::Func(_) = im.ty {
                            if let Some(h) = by_code.get(&(im.module, im.name)) {
                                imports.insert(n_imports, h);
                            }
                            n_imports += 1;
                        }
                    }
                }
            }
            Payload::FunctionSection(r) => {
                for t in r {
                    func_types.push(t.expect("functype"));
                }
            }
            Payload::ExportSection(r) => {
                for e in r {
                    let e = e.expect("export");
                    if e.kind == ExternalKind::Func {
                        exports.push((e.name.to_string(), e.index));
                    }
                }
            }
            Payload::CodeSectionEntry(body) => {
                let mut n_locals = 0usize;
                for l in body.get_locals_reader().expect("locals") {
                    let (c, _) = l.expect("local");
                    n_locals += c as usize;
                }
                let ops: Vec<Operator> = body
                    .get_operators_reader()
                    .expect("ops")
                    .into_iter()
                    .map(|o| o.expect("op"))
                    .collect();
                bodies.push((n_locals, ops));
            }
            Payload::DataSection(r) => {
                for d in r {
                    let d = d.expect("data");
                    if let wasmparser::DataKind::Active { offset_expr, .. } = d.kind {
                        if let Some(base) = const_expr(&offset_expr) {
                            mem.segs.push((base as u32 as u64, d.data.to_vec()));
                        }
                    }
                }
            }
            Payload::GlobalSection(r) => {
                for g in r {
                    let g = g.expect("global");
                    mem.globals.push((const_expr(&g.init_expr).unwrap_or(0), g.ty.mutable));
                }
            }
            _ => {}
        }
    }

    let mut local_sigs: HashMap<u32, (usize, usize)> = HashMap::new();
    for (i, t) in func_types.iter().enumerate() {
        if let Some(s) = sigs.get(*t as usize) {
            local_sigs.insert(n_imports + i as u32, *s);
        }
    }
    let mut md = Mod { types, mem };
    md.mem.written = writes_data(&bodies, &md, &imports, &local_sigs);

    let ctx = Context::create();
    let m = ctx.create_module("ponytail");
    let rt = Rt::new(&ctx, &m);
    for (i, (v, mutable)) in md.mem.globals.iter().enumerate() {
        let g = m.add_global(rt.i64t, None, &format!("g{i}"));
        g.set_initializer(&rt.i64t.const_int(*v as u64, false));
        g.set_constant(!mutable);
    }

    // Declare every host function the module imports, with its ABI types. This
    // declaration is what `module.verify()` checks argument types against.
    let mut declared: Vec<&HostFn> = imports.values().copied().collect();
    declared.sort_by_key(|h| h.name);
    declared.dedup_by_key(|h| h.name);
    for h in &declared {
        let ps: Vec<BasicMetadataTypeEnum> =
            h.args.iter().map(|a| rt.ty(*a).into()).collect();
        let t = match h.ret {
            VT::Val => rt.val.fn_type(&ps, false),
            _ => rt.i64t.fn_type(&ps, false),
        };
        let d = m.add_function(h.name, t, None);
        // Keep the IR traceable back to the binary: the wasm import is a
        // single letter and a code, which no reader would guess.
        d.add_attribute(
            AttributeLoc::Function,
            ctx.create_string_attribute("soroban.import", &format!("{}.{}", h.module, h.code)),
        );
        d.add_attribute(
            AttributeLoc::Function,
            ctx.create_string_attribute("soroban.sig", &format!("({}) -> {}", h.arg_tys.join(", "), h.ret_ty)),
        );
        // Host functions never touch linear memory, except the 13 whose names
        // say so. Stating it lets LLVM forward stack slots across the call in
        // --inline mode, and documents the ABI for the reader.
        if !h.name.contains("linear_memory") {
            d.add_attribute(AttributeLoc::Function, attr(&ctx, "memory", MEM_INACCESSIBLE_RW));
        }
    }

    // The interesting code is usually NOT in an export: the SDK dispatch
    // wrapper delegates, and constants and jump tables live in helpers.
    let inline = only == Some("--inline");
    let all = only == Some("--all") || inline;
    let mut targets: Vec<(String, u32)> = exports.clone();
    if all {
        let named: std::collections::HashSet<u32> = exports.iter().map(|(_, i)| *i).collect();
        for i in 0..bodies.len() as u32 {
            let fi = n_imports + i;
            if !named.contains(&fi) {
                targets.push((format!("f{fi}"), fi));
            }
        }
    }

    let exported: std::collections::HashSet<u32> = exports.iter().map(|(_, i)| *i).collect();

    // Declare every target first, so a call emitted while lowering one function
    // already sees the callee's real signature. Only an export carries the Val
    // ABI; a helper is plain i64.
    let mut plan: Vec<(FunctionValue, u32, usize, usize, bool)> = Vec::new();
    for (name, fidx) in &targets {
        if !all {
            if let Some(f) = only {
                if name != f {
                    continue;
                }
            }
        }
        let Some(local) = fidx.checked_sub(n_imports) else {
            continue;
        };
        let (np, nr) = func_types
            .get(local as usize)
            .and_then(|t| sigs.get(*t as usize))
            .copied()
            .unwrap_or((0, 0));
        let val_abi = exported.contains(fidx);
        let pty: BasicMetadataTypeEnum = if val_abi { rt.val.into() } else { rt.i64t.into() };
        let ps: Vec<BasicMetadataTypeEnum> = (0..np).map(|_| pty).collect();
        let fty = match (nr == 0, val_abi) {
            (true, _) => ctx.void_type().fn_type(&ps, false),
            (false, true) => rt.val.fn_type(&ps, false),
            (false, false) => rt.i64t.fn_type(&ps, false),
        };
        let f = match m.get_function(name) {
            Some(existing) if existing.count_basic_blocks() == 0 => existing,
            Some(_) => continue,
            None => m.add_function(name, fty, None),
        };
        plan.push((f, local, np, nr, val_abi));
    }

    let mut notes = String::new();
    for (f, local, np, nr, val_abi) in plan {
        let Some((n_locals, ops)) = bodies.get(local as usize) else {
            continue;
        };
        if let Err(e) = lower(
            &ctx, &m, &rt, f, np, nr, *n_locals, ops, &imports, &local_sigs, &md, val_abi,
        ) {
            let _ = writeln!(notes, "; FAILED to lower {}: {e}", f.get_name().to_string_lossy());
        }
    }

    // In exports mode a helper is only a declaration, and the syscalls hide
    // behind it: the SDK outlines `storage().set` at every opt level. Say what
    // each declared helper reaches, so `call void @f17()` reads as the
    // put_contract_data it is. A footprint -- a set, not a sequence.
    let mut reach: Vec<std::collections::BTreeSet<&str>> = vec![Default::default(); bodies.len()];
    loop {
        let mut grew = false;
        for i in 0..bodies.len() {
            for op in &bodies[i].1 {
                let Operator::Call { function_index } = op else { continue };
                let add: Vec<&str> = match (imports.get(function_index), function_index.checked_sub(n_imports)) {
                    (Some(h), _) => vec![h.name],
                    (None, Some(l)) => reach.get(l as usize).map(|s| s.iter().copied().collect()).unwrap_or_default(),
                    _ => vec![],
                };
                for a in add {
                    grew |= reach[i].insert(a);
                }
            }
        }
        if !grew {
            break;
        }
    }
    for f in m.get_functions() {
        if f.count_basic_blocks() > 0 {
            continue;
        }
        let name = f.get_name().to_string_lossy().into_owned();
        let Some(set) = name
            .strip_prefix('f')
            .and_then(|n| n.parse::<u32>().ok())
            .and_then(|i| i.checked_sub(n_imports))
            .and_then(|l| reach.get(l as usize))
        else {
            continue;
        };
        let s: Vec<&str> = set.iter().copied().collect();
        f.add_attribute(AttributeLoc::Function, ctx.create_string_attribute("soroban.calls", &s.join(",")));
    }

    if inline {
        define_memory(&ctx, &m, &rt);
        let ex: std::collections::HashSet<&str> = exports.iter().map(|(n, _)| n.as_str()).collect();
        // Helpers become internal and nothing more. That lets LLVM's cost-based
        // inliner take every single-call-site helper (a size win, so it always
        // does) and small shared ones, and drop what it inlined. Forcing
        // `alwaysinline` instead duplicates each shared helper into every call
        // site up the tree: 5.7 GB and no result on a 187-function contract.
        for f in m.get_functions() {
            let n = f.get_name().to_string_lossy().into_owned();
            if f.count_basic_blocks() == 0 || ex.contains(n.as_str()) || n.starts_with("soroban.") {
                continue;
            }
            f.set_linkage(Linkage::Internal);
        }
        optimize(&m, &md.mem)?;
    }
    rename_decoded(&m, &md.mem);

    // The real check, and the reason for inkwell: a Val/i64 confusion at a call
    // site is a verifier error here. In hand-written text it never can be.
    m.verify().map_err(|e| e.to_string())?;
    Ok(format!("{}{}", notes, m.print_to_string().to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn build(ops: Vec<Operator>, nr: usize) -> Result<String, String> {
        build_with(ops, nr, &Mod::default())
    }

    fn build_with(ops: Vec<Operator>, nr: usize, md: &Mod) -> Result<String, String> {
        let ctx = Context::create();
        let m = ctx.create_module("t");
        let rt = Rt::new(&ctx, &m);
        let fty = if nr == 0 {
            ctx.void_type().fn_type(&[], false)
        } else {
            rt.val.fn_type(&[], false)
        };
        let f = m.add_function("f", fty, None);
        lower(
            &ctx, &m, &rt, f, 0, nr, 0, &ops, &HashMap::new(), &HashMap::new(), md, true,
        )?;
        m.verify().map_err(|e| e.to_string())?;
        Ok(m.print_to_string().to_string())
    }

    #[test]
    fn host_table_generated_from_env_json() {
        assert_eq!(HOST_FN_COUNT, HOST_FNS.len());
        assert!(HOST_FN_COUNT >= 171, "got {HOST_FN_COUNT}");
        let put = HOST_FNS
            .iter()
            .find(|h| h.name == "ledger.put_contract_data")
            .expect("put_contract_data");
        assert_eq!(put.args, &[VT::Val, VT::Val, VT::Storage]);
    }

    #[test]
    fn val_payload_1_is_true_not_one() {
        assert_eq!(explain_val(1), "true");
        assert_eq!(explain_val(0), "false");
        assert_eq!(explain_val((1u64 << 32) | 4), "u32 1");
        assert_eq!(explain_val(0x100000003), "Error(type 0, code 1)");
        assert_eq!(explain_val(3867323444879862030), "Symbol(\"persisted\")");
    }

    #[test]
    fn unknown_never_becomes_a_literal() {
        let ir = build(vec![Operator::Return], 1).unwrap();
        assert!(ir.contains("@ponytail.unknown()"), "{ir}");
        assert!(!ir.contains("ret %Val zeroinitializer"));
    }

    #[test]
    fn branch_depth_out_of_range_is_an_error() {
        assert!(build(vec![Operator::Br { relative_depth: 99 }], 0).is_err());
    }

    /// Every sample must lower and verify, in both modes. This is the gate that
    /// would have caught the `--all` ABI mismatch inkwell found, and it needs no
    /// external corpus.
    #[test]
    fn falling_off_the_end_returns_the_value_not_bottom() {
        let ir = build(vec![Operator::I64Const { value: 2 }, Operator::End], 1).unwrap();
        assert!(ir.contains("ret %Val %v_void"), "{ir}");
        assert!(!ir.contains("bottom"), "{ir}");
    }

    #[test]
    fn unmodelled_ops_pop_what_they_consume() {
        // `memory.copy` consumes three and produces nothing; the 2 beneath is
        // the result. A phantom push would return bottom here.
        let ops = vec![
            Operator::I64Const { value: 2 },
            Operator::I64Const { value: 5 },
            Operator::I64Const { value: 6 },
            Operator::I64Const { value: 7 },
            Operator::MemoryCopy { dst_mem: 0, src_mem: 0 },
            Operator::End,
        ];
        let ir = build(ops, 1).unwrap();
        assert!(ir.contains("ret %Val %v_void"), "{ir}");
    }

    #[test]
    fn data_segment_constants_are_read() {
        let mut md = Mod::default();
        md.mem.segs.push((1048576, vec![1]));
        let ops = || {
            let memarg = wasmparser::MemArg { align: 0, max_align: 0, offset: 0, memory: 0 };
            vec![Operator::I32Const { value: 1048576 }, Operator::I32Load8U { memarg }, Operator::End]
        };
        // `&true` is a byte in the data segment: the load IS `true`...
        let ir = build_with(ops(), 1, &md).unwrap();
        assert!(ir.contains("ret %Val %v_true"), "{ir}");
        // ...unless something in the module writes the segment.
        md.mem.written = true;
        let ir = build_with(ops(), 1, &md).unwrap();
        assert!(ir.contains("@soroban.load8u(i64 1048576)"), "{ir}");
    }

    #[test]
    fn inline_mode_shows_set_flag_as_its_syscall() {
        let wasm = std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/samples/three_bugs.wasm")).unwrap();
        let ir = lower_module(&wasm, Some("--inline")).unwrap();
        let body = ir
            .lines()
            .skip_while(|l| !l.starts_with("define %Val @set_flag("))
            .take_while(|l| !l.starts_with('}'))
            .collect::<Vec<_>>()
            .join("\n");
        assert!(body.contains("@ledger.put_contract_data("), "{body}");
        assert!(body.contains("%v_true"), "{body}");
        assert!(body.contains("%Persistent"), "{body}");
        assert!(!body.contains("@f"), "helper calls remain: {body}");
    }

    #[test]
    fn helper_declarations_say_what_they_reach() {
        let wasm = std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/samples/three_bugs.wasm")).unwrap();
        let ir = lower_module(&wasm, Some("set_flag")).unwrap();
        // set_flag: `call 33; call 17; i64.const 2` -- the void is right there.
        assert!(ir.contains("ret %Val %v_void"), "{ir}");
        // f17 is the outlined storage().set; its declaration must say so.
        let calls = ir.lines().find(|l| l.contains("soroban.calls") && l.contains("ledger.put_contract_data"));
        assert!(calls.is_some(), "{ir}");
    }

    #[test]
    fn syscalls_read_as_syscalls() {
        let wasm = std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/samples/errors.wasm")).unwrap();
        let ir = lower_module(&wasm, None).unwrap();
        // The StorageType operand is a named constant, not a bare `i64 1`.
        assert!(ir.contains("%Persistent = call i64 @soroban.storage_type(i64 1)"), "{ir}");
        // The result is named after the syscall, not its import code `_`.
        assert!(ir.contains("%put_contract_data = call %Val @ledger.put_contract_data("), "{ir}");
        // And the declaration still says which wasm import it came from.
        assert!(ir.contains("\"soroban.import\"=\"l._\""), "{ir}");
    }

    #[test]
    fn samples_lower_and_verify() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("samples");
        let mut n = 0;
        for e in std::fs::read_dir(&dir).expect("samples/ exists").flatten() {
            let p = e.path();
            if p.extension().map(|x| x != "wasm").unwrap_or(true) {
                continue;
            }
            let wasm = std::fs::read(&p).expect("read sample");
            for mode in [None, Some("--all"), Some("--inline")] {
                let out = lower_module(&wasm, mode);
                assert!(
                    out.is_ok(),
                    "{} ({mode:?}) failed to verify: {}",
                    p.display(),
                    out.unwrap_err()
                );
            }
            n += 1;
        }
        assert!(n >= 3, "expected at least 3 samples, found {n}");
    }

    /// The whole reason for inkwell: LLVM rejects an integer where a Val is
    /// declared. `llvm-as` on equivalent hand-written text does not.
    #[test]
    fn llvm_rejects_int_where_val_declared() {
        let ctx = Context::create();
        let m = ctx.create_module("t");
        let rt = Rt::new(&ctx, &m);
        let put = m.add_function(
            "put",
            rt.val
                .fn_type(&[rt.val.into(), rt.i64t.into()], false),
            None,
        );
        let f = m.add_function("f", ctx.void_type().fn_type(&[], false), None);
        let b = ctx.create_builder();
        b.position_at_end(ctx.append_basic_block(f, "e"));
        let one = rt.i64t.const_int(1, false);
        // arg 0 is declared %Val; hand it an i64.
        b.build_direct_call(put, &[one.into(), one.into()], "bad")
            .expect("builder allows it");
        b.build_return(None).unwrap();
        assert!(m.verify().is_err(), "verifier should reject the mismatch");
    }
}
