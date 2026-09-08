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
use std::collections::HashMap;
use std::fmt::Write as _;

use inkwell::basic_block::BasicBlock;
use inkwell::builder::Builder;
use inkwell::context::Context;
use inkwell::module::Module;
use inkwell::types::{BasicMetadataTypeEnum, BasicTypeEnum, IntType, StructType};
use inkwell::values::{BasicValueEnum, FunctionValue, PointerValue, ValueKind};
use inkwell::IntPredicate;
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

/// The decode, as an LLVM-safe SSA name. inkwell emits no comments, so the
/// meaning rides on the value name instead -- which is strictly better: it is
/// machine-readable and survives optimisation passes.
fn val_name(payload: u64) -> String {
    let mut s = String::from("v_");
    for c in explain_val(payload).chars() {
        s.push(if c.is_ascii_alphanumeric() { c } else { '_' });
    }
    s.truncate(40);
    s
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

/// The declared conversion and bottom functions, plus the Val type.
struct Rt<'ctx> {
    val: StructType<'ctx>,
    i64t: IntType<'ctx>,
    from_payload: FunctionValue<'ctx>,
    payload: FunctionValue<'ctx>,
    unknown_val: FunctionValue<'ctx>,
    unknown_i64: FunctionValue<'ctx>,
}

impl<'ctx> Rt<'ctx> {
    fn new(ctx: &'ctx Context, m: &Module<'ctx>) -> Self {
        let i64t = ctx.i64_type();
        let val = ctx.opaque_struct_type("Val");
        val.set_body(&[i64t.into()], false);
        let vm: BasicMetadataTypeEnum = val.into();
        let im: BasicMetadataTypeEnum = i64t.into();
        Rt {
            val,
            i64t,
            from_payload: m.add_function("soroban.val.from_payload", val.fn_type(&[im], false), None),
            payload: m.add_function("soroban.val.payload", i64t.fn_type(&[vm], false), None),
            unknown_val: m.add_function("ponytail.unknown", val.fn_type(&[], false), None),
            unknown_i64: m.add_function("ponytail.unknown.i64", i64t.fn_type(&[], false), None),
        }
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

    fn terminated(&self) -> bool {
        self.b
            .get_insert_block()
            .and_then(|bb| bb.get_terminator())
            .is_some()
    }

    fn br(&mut self, to: BasicBlock<'ctx>) {
        if !self.terminated() {
            self.b.build_unconditional_branch(to).expect("br");
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

    /// The single Val<->i64 crossing. Because the result is a typed inkwell
    /// value handed to `build_direct_call`, a mismatch is caught by
    /// `module.verify()` rather than by an assertion of mine.
    fn use_as(&mut self, v: SV<'ctx>, want: VT) -> BasicValueEnum<'ctx> {
        let wants_val = want == VT::Val;
        match v {
            SV::Const(c) => {
                let k = self.rt.i64t.const_int(c as u64, false);
                if wants_val {
                    let n = val_name(c as u64);
                    self.call1(self.rt.from_payload, &[k.into()], &n)
                } else {
                    k.into()
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
        match op {
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
                let c = fun.pop();
                let ci = fun.use_int(c);
                let nz = fun
                    .b
                    .build_int_compare(IntPredicate::NE, ci, rt.i64t.const_zero(), "if")
                    .expect("icmp");
                let then_bb = fun.blk("then");
                let else_bb = fun.blk("else");
                let cont = fun.blk("ic");
                if !fun.terminated() {
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
                match eb {
                    Some(bb) => fun.b.position_at_end(bb),
                    None => {
                        let d = fun.blk("dead");
                        fun.b.position_at_end(d);
                    }
                }
                fun.stack.clear();
            }
            Operator::End => {
                let Some(fr) = fun.labels.pop() else { continue };
                if fr.cont == exit {
                    fun.labels.push(fr);
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
                fun.br(t);
                let d = fun.blk("dead");
                fun.b.position_at_end(d);
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
                let dead = fun.blk("dead");
                fun.b.position_at_end(dead);
            }
            Operator::Return => {
                if !fun.terminated() {
                    if n_results == 0 {
                        fun.b.build_return(None).expect("ret");
                    } else {
                        let v = fun.pop();
                        let rv = fun.use_as(v, if val_abi { VT::Val } else { VT::Raw64 });
                        fun.b.build_return(Some(&rv)).expect("ret");
                    }
                }
                let d = fun.blk("dead");
                fun.b.position_at_end(d);
            }
            Operator::Unreachable => {
                if !fun.terminated() {
                    fun.b.build_unreachable().expect("unreachable");
                }
                let d = fun.blk("dead");
                fun.b.position_at_end(d);
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
                    let r = fun.call1(callee, &args, h.code);
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
            // Anything unmodelled yields bottom, never a plausible value.
            _ => fun.stack.push(SV::Unknown),
        }
    }

    // Every block must end in a terminator. Sweeping for it here is more robust
    // than tracking a flag, and any block we never reached returns bottom.
    fun.b.position_at_end(exit);
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
        eprintln!("usage: ponytail-wasm <contract.wasm> [export|--all]");
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
fn lower_module(wasm: &[u8], only: Option<&str>) -> Result<String, String> {
    let by_code: HashMap<(&str, &str), &HostFn> =
        HOST_FNS.iter().map(|h| ((h.module, h.code), h)).collect();

    let mut imports: HashMap<u32, &'static HostFn> = HashMap::new();
    let mut n_imports = 0u32;
    let mut bodies: Vec<(usize, Vec<Operator>)> = Vec::new();
    let mut exports: Vec<(String, u32)> = Vec::new();
    let mut sigs: Vec<(usize, usize)> = Vec::new();
    let mut func_types: Vec<u32> = Vec::new();

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
            _ => {}
        }
    }

    let ctx = Context::create();
    let m = ctx.create_module("ponytail");
    let rt = Rt::new(&ctx, &m);

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
        m.add_function(h.name, t, None);
    }

    let mut local_sigs: HashMap<u32, (usize, usize)> = HashMap::new();
    for (i, t) in func_types.iter().enumerate() {
        if let Some(s) = sigs.get(*t as usize) {
            local_sigs.insert(n_imports + i as u32, *s);
        }
    }

    // The interesting code is usually NOT in an export: the SDK dispatch
    // wrapper delegates, and constants and jump tables live in helpers.
    let all = only == Some("--all");
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
            &ctx, &m, &rt, f, np, nr, *n_locals, ops, &imports, &local_sigs, val_abi,
        ) {
            let _ = writeln!(notes, "; FAILED to lower {}: {e}", f.get_name().to_string_lossy());
        }
    }

    // The real check, and the reason for inkwell: a Val/i64 confusion at a call
    // site is a verifier error here. In hand-written text it never can be.
    m.verify().map_err(|e| e.to_string())?;
    Ok(format!("{}{}", notes, m.print_to_string().to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn build(ops: Vec<Operator>, nr: usize) -> Result<String, String> {
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
            &ctx, &m, &rt, f, 0, nr, 0, &ops, &HashMap::new(), &HashMap::new(), true,
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
    fn samples_lower_and_verify() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("samples");
        let mut n = 0;
        for e in std::fs::read_dir(&dir).expect("samples/ exists").flatten() {
            let p = e.path();
            if p.extension().map(|x| x != "wasm").unwrap_or(true) {
                continue;
            }
            let wasm = std::fs::read(&p).expect("read sample");
            for all in [false, true] {
                let out = lower_module(&wasm, if all { Some("--all") } else { None });
                assert!(
                    out.is_ok(),
                    "{} (--all={all}) failed to verify: {}",
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
