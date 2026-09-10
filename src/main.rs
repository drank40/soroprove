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
use inkwell::{AddressSpace, IntPredicate, OptimizationLevel};
use wasmparser::{ExternalKind, Operator, Parser, Payload};

mod spec;

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
    /// An address in this function's shadow-stack frame, `frame + off`. The
    /// frame is an `alloca`, so an access here is a typed access to
    /// function-local memory, which LLVM then cleans up like any local.
    Frame(i64),
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
    /// The result of a typed `block`/`if`/`loop`, as an entry-block alloca:
    /// every path that reaches the label stores its value, the continuation
    /// loads it, and mem2reg makes the phi. A `br` to a loop carries nothing.
    slot: Option<PointerValue<'ctx>>,
    is_loop: bool,
}

/// How many values a block type yields. Soroban contracts yield at most one;
/// a multi-value block keeps the old behaviour and its result is bottom.
fn block_results(bt: &wasmparser::BlockType, types: &Types) -> usize {
    match bt {
        wasmparser::BlockType::Empty => 0,
        wasmparser::BlockType::Type(_) => 1,
        wasmparser::BlockType::FuncType(t) => match types.0.get(*t as usize).map(|s| &s.composite_type.inner) {
            Some(wasmparser::CompositeInnerType::Func(ft)) => ft.results().len(),
            _ => 0,
        },
    }
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
    /// The wasm value types of every function's params and results, by
    /// function index: the one type fact the binary states outright. On
    /// wasm32 a pointer is always `i32` and a Val always `i64`.
    wasm_sigs: HashMap<u32, (Vec<&'static str>, Vec<&'static str>)>,
    /// Function index -> (identifier, demangled path) for every helper whose
    /// fingerprint matched a known SDK function.
    fnames: HashMap<u32, (String, String)>,
}

/// A helper's name: what the fingerprints say it is, else `fN`.
fn fn_name(md: &Mod, fi: u32) -> String {
    md.fnames.get(&fi).map(|(id, _)| id.clone()).unwrap_or_else(|| format!("f{fi}"))
}

fn valtype_name(v: wasmparser::ValType) -> &'static str {
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
fn wasm_type_attrs(ctx: &Context, f: FunctionValue, fi: u32, md: &Mod) {
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

fn fnv(s: &str) -> u64 {
    s.bytes().fold(0xcbf29ce484222325u64, |h, b| (h ^ b as u64).wrapping_mul(0x100000001b3))
}

/// Two fingerprints per function. Exact: the code, hashed (FNV-1a) with what
/// varies between builds of the same source taken out -- a constant that is
/// a data address becomes `D`, a call to a lifted function becomes that
/// function's own fingerprint, one round deep, so a wrapper is told apart by
/// what it wraps. Shape: order-free -- the signature, the host functions
/// called, the constants, the number of calls and loops -- which survives
/// what wasm-opt and register allocation do to the same function: `if` for
/// `block/br_if`, values on the stack for locals.
fn fingerprints(
    bodies: &[(usize, Vec<Operator>)],
    sigs: &[String],
    n_imports: u32,
    imports: &HashMap<u32, &'static HostFn>,
    segs: &[(u64, Vec<u8>)],
) -> Vec<(u64, u64)> {
    let is_data = |v: i32| segs.iter().any(|(b, d)| (v as u32 as u64) >= *b && (v as u32 as u64) < b + d.len() as u64);
    let shape = |i: usize, ops: &[Operator]| -> u64 {
        let (mut hosts, mut consts, mut calls, mut loops) = (Vec::new(), Vec::new(), 0usize, 0usize);
        for op in ops {
            match op {
                Operator::I32Const { value } if !is_data(*value) => consts.push(*value as i64),
                Operator::I64Const { value } => consts.push(*value),
                Operator::Call { function_index } => match imports.get(function_index) {
                    Some(hf) => hosts.push(hf.name),
                    None => calls += 1,
                },
                Operator::Loop { .. } => loops += 1,
                _ => {}
            }
        }
        hosts.sort();
        consts.sort();
        fnv(&format!("{} {hosts:?} {consts:?} {calls} {loops}", sigs.get(i).map(String::as_str).unwrap_or("")))
    };
    let round = |prev: Option<&Vec<u64>>| -> Vec<u64> {
        bodies
            .iter()
            .map(|(n_locals, ops)| {
                let mut h: u64 = 0xcbf29ce484222325;
                let mut feed = |s: &str| {
                    for b in s.bytes() {
                        h ^= b as u64;
                        h = h.wrapping_mul(0x100000001b3);
                    }
                };
                feed(&n_locals.to_string());
                for op in ops {
                    match op {
                        Operator::I32Const { value } if is_data(*value) => feed("D"),
                        Operator::Call { function_index } => match (imports.get(function_index), function_index.checked_sub(n_imports)) {
                            (Some(hf), _) => feed(hf.name),
                            (None, Some(l)) => feed(&prev.and_then(|p| p.get(l as usize)).map(|fp| format!("F{fp:x}")).unwrap_or_else(|| "F".into())),
                            _ => feed("F"),
                        },
                        other => feed(&format!("{other:?}")),
                    }
                }
                h
            })
            .collect()
    };
    let first = round(None);
    round(Some(&first)).into_iter().enumerate().map(|(i, exact)| (exact, shape(i, &bodies[i].1))).collect()
}

/// `--fingerprints`, on a reference build that kept its symbol names: one
/// line per named, non-exported function that is not the reference crate's
/// own -- fingerprint, then the demangled path. The header says which SDK
/// and rustc built it.
fn fingerprint_table(fps: &[(u64, u64)], names: &HashMap<u32, String>, exported: &std::collections::HashSet<u32>, n_imports: u32, sdk: Option<&str>, rustc: Option<&str>) -> String {
    let mut out = format!("# sdk {}\n# rustc {}\n# exact shape name\n", sdk.unwrap_or("?"), rustc.unwrap_or("?"));
    for (i, (exact, shape)) in fps.iter().enumerate() {
        let fi = n_imports + i as u32;
        let Some(n) = names.get(&fi) else { continue };
        let full = format!("{:#}", rustc_demangle::demangle(n));
        if exported.contains(&fi) || full.contains("ponytail_ref") {
            continue;
        }
        let _ = writeln!(out, "{exact:016x} {shape:016x} {full}");
    }
    out
}

/// A loaded table: exact fingerprint -> name, and shape -> names.
#[derive(Default)]
struct Table {
    exact: HashMap<u64, String>,
    shape: HashMap<u64, Vec<String>>,
}

impl Table {
    /// The name for a function: its exact fingerprint's, else its shape's
    /// when that names exactly one function.
    fn name(&self, exact: u64, shape: u64) -> Option<(&str, bool)> {
        if let Some(n) = self.exact.get(&exact) {
            return Some((n, true));
        }
        match self.shape.get(&shape).map(Vec::as_slice) {
            Some([n]) => Some((n, false)),
            _ => None,
        }
    }
}

/// The cached table nearest the binary's SDK version: `<dir>/<sdk>.txt`, or
/// `<sdk>+rustc<ver>.txt` when the reference was built with a chosen
/// toolchain (preferred when it is the binary's). The dir is
/// `PONYTAIL_FINGERPRINTS`; else both ~/.cache/ponytail-wasm/fingerprints,
/// which gen.sh fills, and the tables checked in with this source. Returns
/// the table and a note for the IR header.
fn load_fingerprints(sdk: Option<&str>, rustc: Option<&str>) -> (Table, String) {
    let dirs: Vec<String> = match std::env::var("PONYTAIL_FINGERPRINTS") {
        Ok(d) => vec![d],
        Err(_) => vec![
            format!("{}/.cache/ponytail-wasm/fingerprints", std::env::var("HOME").unwrap_or_default()),
            concat!(env!("CARGO_MANIFEST_DIR"), "/fingerprints").to_string(),
        ],
    };
    let ver = |s: &str| -> Vec<u64> { s.split('.').map(|p| p.parse().unwrap_or(0)).collect() };
    let want = ver(sdk.unwrap_or("0"));
    // (version distance, toolchain differs, path): least wins.
    let mut best: Option<(u64, bool, std::path::PathBuf)> = None;
    for dir in &dirs {
        let Ok(rd) = std::fs::read_dir(dir) else { continue };
        for e in rd.flatten() {
            let name = e.file_name().to_string_lossy().into_owned();
            let Some(stem) = name.strip_suffix(".txt") else { continue };
            let (s, tc) = stem.split_once("+rustc").map(|(a, b)| (a, Some(b))).unwrap_or((stem, None));
            let have = ver(s);
            let dist: u64 = (0..3).map(|i| have.get(i).copied().unwrap_or(0).abs_diff(want.get(i).copied().unwrap_or(0)) << (32 - 16 * i)).sum();
            let cand = (dist, tc != rustc, e.path());
            if best.as_ref().map_or(true, |b| (cand.0, cand.1) < (b.0, b.1)) {
                best = Some(cand);
            }
        }
    }
    let Some((dist, _, path)) = best else {
        return (Table::default(), format!("no fingerprints in {}; run fingerprints/gen.sh {}", dirs.join(" or "), sdk.unwrap_or("<sdk version>")));
    };
    let mut table = Table::default();
    for l in std::fs::read_to_string(&path).unwrap_or_default().lines() {
        let mut it = l.splitn(3, ' ');
        let (Some(exact), Some(shape), Some(name)) = (it.next(), it.next(), it.next()) else { continue };
        let (Ok(exact), Ok(shape)) = (u64::from_str_radix(exact, 16), u64::from_str_radix(shape, 16)) else { continue };
        // Two functions with one body: say both.
        table
            .exact
            .entry(exact)
            .and_modify(|n| {
                if !n.contains(name) {
                    n.push_str(" | ");
                    n.push_str(name);
                }
            })
            .or_insert_with(|| name.to_string());
        let names = table.shape.entry(shape).or_default();
        if !names.iter().any(|n| n == name) {
            names.push(name.to_string());
        }
    }
    let file = path.file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or_default();
    (table, format!("fingerprints {file}{}", if dist > 0 { " (nearest)" } else { "" }))
}

/// A Rust identifier for a demangled path: `Type_method` for a method or a
/// trait impl, the bare name otherwise. `<soroban_sdk::vec::Vec<T> as
/// TryFromVal<E, Val>>::try_from_val` -> `Vec_try_from_val`.
fn sdk_ident(full: &str) -> String {
    let full = full.split(" | ").next().unwrap_or(full);
    let strip = |s: &str| -> String {
        let mut d = 0i32;
        s.chars()
            .filter(|&c| {
                if c == '<' {
                    d += 1
                }
                let keep = d == 0;
                if c == '>' {
                    d -= 1
                }
                keep
            })
            .collect()
    };
    let (ty, method) = if let Some(rest) = full.strip_prefix('<') {
        let mut d = 1i32;
        let close = rest
            .char_indices()
            .find(|&(_, c)| {
                if c == '<' {
                    d += 1
                }
                if c == '>' {
                    d -= 1
                }
                d == 0
            })
            .map(|(i, _)| i)
            .unwrap_or(rest.len());
        let ty = strip(rest[..close].split(" as ").next().unwrap_or(""));
        (ty, strip(rest.get(close + 1..).unwrap_or("")).trim_start_matches(':').to_string())
    } else {
        let s = strip(full);
        let mut segs = s.rsplit("::");
        let m = segs.next().unwrap_or("").to_string();
        (segs.next().filter(|t| t.starts_with(char::is_uppercase)).unwrap_or("").to_string(), m)
    };
    // `<U as IntoVal<E, T>>` is the blanket impl: no type to name. A tuple is one.
    let ty = if ty.starts_with('(') { "Tuple" } else { ty.rsplit("::").next().unwrap_or("").trim_start_matches('&') };
    let ty = if ty.len() == 1 && ty.starts_with(char::is_uppercase) { "" } else { ty };
    let raw = if ty.is_empty() { method } else { format!("{ty}_{method}") };
    raw.chars().map(|c| if c.is_ascii_alphanumeric() || c == '_' { c } else { '_' }).collect()
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
    /// The recovered shadow-stack frame (alloca, size) and the wasm local that
    /// holds its base, when the function opens one the way LLVM's wasm
    /// backend does.
    frame: Option<(PointerValue<'ctx>, u64)>,
    frame_local: Option<u32>,
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
        let o = fo.checked_add(off as i64)?;
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
                        let p = self.frame_ptr(fr, o);
                        SV::Reg(self.b.build_ptr_to_int(p, self.rt.i64t, "fp").expect("ptrtoint").into())
                    }
                    None => SV::Unknown,
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

    fn binop(&mut self, op: &str) {
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
        frame: None,
        frame_local: None,
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
    let mut skip = 0;
    if let [Operator::GlobalGet { global_index: 0 }, Operator::I32Const { value: n }, Operator::I32Sub, Operator::LocalTee { local_index: l }, Operator::GlobalSet { global_index: 0 }, ..] =
        ops
    {
        let sets = ops
            .iter()
            .filter(|o| matches!(o, Operator::LocalSet { local_index } | Operator::LocalTee { local_index } if local_index == l))
            .count();
        if *n > 0 && sets == 1 {
            let fr = b.build_alloca(ctx.i8_type().array_type(*n as u32), "frame").expect("alloca");
            fun.frame = Some((fr, *n as u64));
            fun.frame_local = Some(*l);
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
            Operator::GlobalGet { global_index } => match m.get_global(&format!("g{global_index}")) {
                Some(g) => {
                    let v = fun.b.build_load(rt.i64t, g.as_pointer_value(), &format!("g{global_index}")).expect("load");
                    fun.stack.push(SV::Reg(v));
                }
                None => fun.stack.push(SV::Unknown),
            },
            Operator::GlobalSet { global_index } => {
                let v = fun.pop();
                // Restoring the stack pointer from a frame address: the frame
                // is an alloca now, so there is nothing to restore.
                if matches!(v, SV::Frame(_)) {
                    continue;
                }
                let iv = fun.use_int(v);
                if let Some(g) = m.get_global(&format!("g{global_index}")) {
                    fun.b.build_store(g.as_pointer_value(), iv).expect("store");
                }
            }
            Operator::Block { blockty } => {
                let cont = fun.blk("c");
                fun.labels.push(Lbl { target: cont, cont, else_bb: None, slot: slot_for(blockty), is_loop: false });
            }
            Operator::Loop { blockty } => {
                let h = fun.blk("h");
                fun.br(h);
                fun.b.position_at_end(h);
                let cont = fun.blk("lc");
                fun.labels.push(Lbl { target: h, cont, else_bb: None, slot: slot_for(blockty), is_loop: true });
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
                fun.labels.push(Lbl { target: cont, cont, else_bb: Some(else_bb), slot, is_loop: false });
                fun.b.position_at_end(then_bb);
                let _ = i;
            }
            Operator::Else => {
                let (cont, eb) = match fun.labels.last_mut() {
                    Some(l) => (l.cont, l.else_bb.take()),
                    None => return Err("else with no frame".into()),
                };
                // The then arm's value is the if's result on this path.
                let last = fun.labels.len() - 1;
                fun.store_result(last, false);
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
                // The operand stack is not threaded across `end`; a typed
                // label's one result comes through its slot instead, and
                // locals go through allocas. mem2reg builds the phis.
                fun.stack.clear();
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
        eprintln!("usage: ponytail-wasm <contract.wasm> [export|--all|--inline|--sdk|--fingerprints]");
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

/// Linear memory for the optimiser. An address is an integer and an access is
/// `inttoptr` of it. A frame address is `ptrtoint` of the frame alloca, so
/// `inttoptr(ptrtoint(frame) + k)` folds back to the alloca and the optimiser
/// sees function-local memory; every other address is an opaque pointer, and
/// two of those may alias, which is the truth.
fn define_memory<'ctx>(ctx: &'ctx Context, m: &Module<'ctx>, rt: &Rt<'ctx>) {
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
    // Inlining exposes frame addresses that travelled as integers, and
    // constant addresses into the data segment. Each fold can feed the next
    // -- a folded frame load yields a constant, a constant yields an address --
    // so fold, let LLVM propagate, repeat until nothing changes.
    for _ in 0..6 {
        let folded = fold_frame_pointers(m) + fold_data_loads(m, mem);
        // Runs once more after the last fold: DSE has just emptied a frame,
        // and instcombine then drops the alloca and its lifetime markers.
        // LLVM 18 aborts if a standalone instcombine is not at a fixpoint
        // after one iteration, which hand-rewritten IR routinely is not.
        // Full unrolling: the SDK encodes `Symbol::new("Pair")` with a loop
        // over a constant string; unrolled, its loads are constant-address,
        // the next fold reads them, and the whole loop folds to the symbol.
        run("sroa,instcombine<no-verify-fixpoint>,gvn,dse,simplifycfg,adce,loop-simplify,lcssa,loop(indvars),loop-unroll<O3;upperbound;full-unroll-max=64>")?;
        if folded == 0 {
            break;
        }
    }
    Ok(())
}

/// `inttoptr(ptrtoint(P) + K)` -> `getelementptr i8, P, K`. LLVM will not do
/// this fold itself, on provenance grounds that do not hold for wasm's flat
/// memory, where an integer address IS the pointer. Only after it does the
/// optimiser see that a frame address handed to an inlined helper is the
/// frame alloca -- and only then can it forward the store and drop it.
fn fold_frame_pointers(m: &Module) -> usize {
    let ctx = m.get_context();
    let b = ctx.create_builder();
    let mut n = 0;
    for f in m.get_functions() {
        for bb in f.get_basic_blocks() {
            let mut cur = bb.get_first_instruction();
            while let Some(i) = cur {
                cur = i.get_next_instruction();
                if i.get_opcode() != InstructionOpcode::IntToPtr {
                    continue;
                }
                let Some(Operand::Value(BasicValueEnum::IntValue(a))) = i.get_operand(0) else { continue };
                let Some((p, k)) = ptr_plus_const(a) else { continue };
                b.position_before(&i);
                let g = if k == 0 {
                    p
                } else {
                    let k = ctx.i64_type().const_int(k as u64, true);
                    unsafe { b.build_gep(ctx.i8_type(), p, &[k], "fp") }.expect("gep")
                };
                i.as_any_value_enum().into_pointer_value().replace_all_uses_with(g);
                i.erase_from_basic_block();
                n += 1;
            }
        }
    }
    n
}

/// `ptrtoint P`, or `add (ptrtoint P), C` in either order -> (P, C).
fn ptr_plus_const(a: IntValue) -> Option<(PointerValue, i64)> {
    let i = a.as_instruction_value()?;
    match i.get_opcode() {
        InstructionOpcode::PtrToInt => match i.get_operand(0)? {
            Operand::Value(BasicValueEnum::PointerValue(p)) => Some((p, 0)),
            _ => None,
        },
        InstructionOpcode::Add => {
            let (Operand::Value(BasicValueEnum::IntValue(x)), Operand::Value(BasicValueEnum::IntValue(y))) =
                (i.get_operand(0)?, i.get_operand(1)?)
            else {
                return None;
            };
            [(x, y), (y, x)].into_iter().find_map(|(v, c)| {
                let (p, 0) = ptr_plus_const(v)? else { return None };
                c.is_constant_int().then(|| c.get_sign_extended_constant()).flatten().map(|k| (p, k))
            })
        }
        _ => None,
    }
}

/// A load whose address inlining has made constant is a read of the data
/// segment, if the address falls in one: replace it with the bytes. LLVM has
/// folded such an address into a constant `inttoptr` expression, which inkwell
/// does not unpack, so this reads it via the C API.
fn fold_data_loads(m: &Module, mem: &Mem) -> usize {
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
                let Some(addr) = const_addr(p) else { continue };
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

/// `inttoptr (i64 K to ptr)` as a constant expression -> K.
fn const_addr(p: PointerValue) -> Option<u64> {
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

/// `%p.i4.i.i` is LLVM's `%p` after inlining, three levels deep, and
/// `%frame.i.i.sroa.2` the same with SROA's own suffix after. The `.i`
/// segments record where a value came from and nothing else; drop them.
fn strip_inline_suffixes(m: &Module) {
    fn base(s: &str) -> String {
        s.split('.')
            .enumerate()
            .filter(|(k, seg)| *k == 0 || !(seg.starts_with('i') && seg[1..].chars().all(|c| c.is_ascii_digit())))
            .map(|(_, seg)| seg)
            .collect::<Vec<_>>()
            .join(".")
    }
    for f in m.get_functions() {
        for bb in f.get_basic_blocks() {
            if let Ok(n) = bb.get_name().to_str() {
                let b = base(n);
                if b.len() != n.len() && !b.is_empty() {
                    bb.set_name(&b);
                }
            }
            let mut cur = bb.get_first_instruction();
            while let Some(i) = cur {
                cur = i.get_next_instruction();
                let Some(n) = i.get_name().and_then(|n| n.to_str().ok()) else { continue };
                let b = base(n);
                if b.len() != n.len() && !b.is_empty() {
                    let _ = i.set_name(&b);
                }
            }
        }
    }
}

/// Names for what folding has just made constant: a `from_payload` of a
/// literal reads as the Val it is, a StorageType literal as its variant, and a
/// `*_from_linear_memory` call with constant position and length as the
/// symbol, string or Val list sitting in the data segment.
fn rename_decoded(m: &Module, mem: &Mem, spec: &spec::Spec) {
    let ctx = m.get_context();
    let b = ctx.create_builder();
    // Map key names, and symbol/string texts, by rodata position, for the
    // MIR stage: `soroban.keys` and `soroban.strings`.
    let mut keys_out: Vec<(u64, Vec<String>)> = Vec::new();
    let mut strings_out: Vec<(u64, String)> = Vec::new();
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
                    n => decode_lm(n, &args, mem, spec, &mut keys_out, &mut strings_out),
                };
                if let (Some(n), ValueKind::Basic(v)) = (new, cs.try_as_basic_value()) {
                    v.set_name(&n);
                }
            }
        }
    }
    keys_out.sort();
    keys_out.dedup();
    for (pos, keys) in keys_out {
        let line = format!("{pos} {}", keys.join(" "));
        let node = ctx.metadata_node(&[ctx.metadata_string(&line).into()]);
        let _ = m.add_global_metadata("soroban.keys", &node);
    }
    strings_out.sort();
    strings_out.dedup();
    for (pos, text) in strings_out {
        let node = ctx.metadata_node(&[ctx.metadata_string(&format!("{pos} {text}")).into()]);
        let _ = m.add_global_metadata("soroban.strings", &node);
    }
    // The read-only data itself, so the MIR stage can read a (pos, len) that
    // is constant only in a caller of the helper that uses it.
    if !mem.written {
        for (base, bytes) in &mem.segs {
            let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
            let node = ctx.metadata_node(&[ctx.metadata_string(&format!("{base} {hex}")).into()]);
            let _ = m.add_global_metadata("soroban.rodata", &node);
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

fn decode_lm(
    name: &str,
    args: &[Option<u64>],
    mem: &Mem,
    spec: &spec::Spec,
    keys_out: &mut Vec<(u64, Vec<String>)>,
    strings_out: &mut Vec<(u64, String)>,
) -> Option<String> {
    // Positions and lengths cross the boundary as U32Vals: tag 4, value in the top 32 bits.
    let u = |k: usize| args.get(k).copied().flatten().filter(|p| p & 0xff == 4).map(|p| p >> 32);
    let text = |k: usize| -> Option<String> {
        Some(String::from_utf8_lossy(mem.bytes(u(k)?, u(k + 1)? as usize)?).into_owned())
    };
    let vals = |pos: u64, len: u64| -> Option<Vec<String>> {
        (0..len).map(|i| mem.load(pos + 8 * i, 64, false).map(|v| explain_val(v as u64))).collect()
    };
    // Map keys are not Vals in memory: the host scans `len` (pos: u32, len: u32)
    // slices and reads each as a symbol (host.rs map_new_from_linear_memory ->
    // metered_vm_scan_slices_in_linear_memory).
    let slices = |pos: u64, len: u64| -> Option<Vec<String>> {
        (0..len)
            .map(|i| {
                let p = mem.load(pos + 8 * i, 32, false)? as u64;
                let l = mem.load(pos + 8 * i + 4, 32, false)? as usize;
                Some(format!("{:?}", String::from_utf8_lossy(mem.bytes(p, l)?)))
            })
            .collect()
    };
    let s = match name {
        "buf.symbol_new_from_linear_memory" | "buf.string_new_from_linear_memory" => {
            let t = text(0)?;
            strings_out.push((u(0)?, t.clone()));
            format!("{}({t:?})", if name.starts_with("buf.symbol") { "Symbol" } else { "String" })
        }
        "buf.bytes_new_from_linear_memory" => {
            let hex: String = mem.bytes(u(0)?, u(1)? as usize)?.iter().map(|b| format!("{b:02x}")).collect();
            format!("Bytes({hex})")
        }
        "vec.vec_new_from_linear_memory" => format!("Vec[{}]", vals(u(0)?, u(1)?)?.join(", ")),
        // The values are runtime Vals, not decoded here. A named struct is a
        // map whose keys are its field names (soroban-sdk-macros): when the
        // key set is exactly one spec struct's field set, this is that struct.
        "map.map_unpack_to_linear_memory" => {
            let keys = slices(u(1)?, u(3)?)?;
            keys_out.push((u(1)?, keys.iter().map(|k| k.trim_matches('"').to_string()).collect()));
            return None;
        }
        "map.map_new_from_linear_memory" => {
            let keys = slices(u(0)?, u(2)?)?;
            let mut sorted: Vec<String> = keys.iter().map(|k| k.trim_matches('"').to_string()).collect();
            keys_out.push((u(0)?, sorted.clone()));
            sorted.sort();
            let mut matches = spec.structs.iter().filter(|(_, fs)| {
                let mut f = fs.clone();
                f.sort();
                f == sorted
            });
            match (matches.next(), matches.next()) {
                (Some((s, _)), None) => return Some(spec::snake(s)),
                _ => format!("Map{{{}}}", keys.join(", ")),
            }
        }
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
    let mut wasm_types: Vec<(Vec<&'static str>, Vec<&'static str>)> = Vec::new();
    let mut func_types: Vec<u32> = Vec::new();
    let mut types = Types(Vec::new());
    let mut mem = Mem::default();
    let mut spec = spec::Spec::default();
    let mut names: HashMap<u32, String> = HashMap::new();
    let mut meta: Vec<(String, String)> = Vec::new();

    for p in Parser::new(0).parse_all(wasm) {
        match p.expect("parse") {
            Payload::TypeSection(r) => {
                for rg in r {
                    for st in rg.expect("rec group").into_types() {
                        if let wasmparser::CompositeInnerType::Func(ft) = &st.composite_type.inner {
                            sigs.push((ft.params().len(), ft.results().len()));
                            wasm_types.push((
                                ft.params().iter().map(|v| valtype_name(*v)).collect(),
                                ft.results().iter().map(|v| valtype_name(*v)).collect(),
                            ));
                        } else {
                            sigs.push((0, 0));
                            wasm_types.push((Vec::new(), Vec::new()));
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
            Payload::CustomSection(c) if c.name() == "contractspecv0" => spec = spec::parse(c.data()),
            // The SDK stamps its own version and rustc's: `rssdkver`, `rsver`.
            Payload::CustomSection(c) if c.name() == "contractmetav0" => {
                use stellar_xdr::curr::{Limited, Limits, ReadXdr, ScMetaEntry};
                for e in ScMetaEntry::read_xdr_iter(&mut Limited::new(c.data(), Limits::none())).flatten() {
                    let ScMetaEntry::ScMetaV0(m) = e;
                    meta.push((m.key.to_utf8_string_lossy(), m.val.to_utf8_string_lossy()));
                }
            }
            // Symbol names, when the build kept them: the reference build does.
            Payload::CustomSection(c) => {
                if let wasmparser::KnownCustom::Name(r) = c.as_known() {
                    for n in r.into_iter().flatten() {
                        if let wasmparser::Name::Function(map) = n {
                            for wasmparser::Naming { index, name } in map.into_iter().flatten() {
                                names.insert(index, name.to_string());
                            }
                        }
                    }
                }
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
    let mut wasm_sigs = HashMap::new();
    for (i, t) in func_types.iter().enumerate() {
        if let Some(s) = sigs.get(*t as usize) {
            local_sigs.insert(n_imports + i as u32, *s);
        }
        if let Some(w) = wasm_types.get(*t as usize) {
            wasm_sigs.insert(n_imports + i as u32, w.clone());
        }
    }
    // Which SDK built this, and what its functions are called.
    let sdk_version = meta.iter().find(|(k, _)| k == "rssdkver").map(|(_, v)| v.split('#').next().unwrap_or(v).to_string());
    let rust_version = meta.iter().find(|(k, _)| k == "rsver").map(|(_, v)| v.clone());
    let sig_strs: Vec<String> = (0..bodies.len())
        .map(|i| func_types.get(i).and_then(|t| wasm_types.get(*t as usize)).map(|(p, r)| format!("{p:?}->{r:?}")).unwrap_or_default())
        .collect();
    let fps = fingerprints(&bodies, &sig_strs, n_imports, &imports, &mem.segs);
    let exp_idx: std::collections::HashSet<u32> = exports.iter().map(|(_, i)| *i).collect();
    if only == Some("--fingerprints") {
        return Ok(fingerprint_table(&fps, &names, &exp_idx, n_imports, sdk_version.as_deref(), rust_version.as_deref()));
    }
    if only == Some("--sdk") {
        return Ok(format!("{} {}\n", sdk_version.as_deref().unwrap_or("?"), rust_version.as_deref().unwrap_or("?")));
    }
    let (table, table_note) = load_fingerprints(sdk_version.as_deref(), rust_version.as_deref());
    let mut fnames: HashMap<u32, (String, String)> = HashMap::new();
    let mut used: std::collections::HashSet<String> = exports.iter().map(|(n, _)| n.clone()).collect();
    let mut by_shape = 0;
    for (i, (exact, shape)) in fps.iter().enumerate() {
        let fi = n_imports + i as u32;
        if exp_idx.contains(&fi) {
            continue;
        }
        if let Some((full, is_exact)) = table.name(*exact, *shape) {
            by_shape += !is_exact as usize;
            // Bodies that are one trap are every panic at once: say so.
            let mut id = if full.contains(" | ") && full.split(" | ").all(|n| n.contains("panic") || n.contains("fail")) {
                "panic".to_string()
            } else {
                sdk_ident(full)
            };
            if !used.insert(id.clone()) {
                id = format!("{id}_{fi}");
                used.insert(id.clone());
            }
            fnames.insert(fi, (id, full.to_string()));
        }
    }
    let sdk_note = format!(
        "; sdk {} rustc {}; {}: {} of {} helpers named, {} by shape\n",
        sdk_version.as_deref().unwrap_or("?"),
        rust_version.as_deref().unwrap_or("?"),
        table_note,
        fnames.len(),
        bodies.len() - exp_idx.len(),
        by_shape
    );
    let mut md = Mod { types, mem, wasm_sigs, fnames };
    md.mem.written = writes_data(&bodies, &md, &imports, &local_sigs);

    let ctx = Context::create();
    let m = ctx.create_module("ponytail");
    let rt = Rt::new(&ctx, &m);
    // The declared ABI rides along as named metadata, one line per entry.
    for l in &spec.lines {
        let node = ctx.metadata_node(&[ctx.metadata_string(l).into()]);
        m.add_global_metadata("soroban.spec", &node).expect("named metadata takes nodes");
    }
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
                targets.push((fn_name(&md, fi), fi));
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
        wasm_type_attrs(&ctx, f, *fidx, &md);
        // An export's declared parameter names and types, from the spec.
        if let Some((_, params, ret)) = spec.fns.iter().find(|(n, ..)| n == name) {
            for (i, (pn, pt)) in params.iter().enumerate() {
                f.add_attribute(AttributeLoc::Param(i as u32), ctx.create_string_attribute("spec.name", pn));
                f.add_attribute(AttributeLoc::Param(i as u32), ctx.create_string_attribute("spec.type", pt));
            }
            if let Some(r) = ret {
                f.add_attribute(AttributeLoc::Return, ctx.create_string_attribute("spec.type", r));
            }
            if let Some(line) = spec.lines.iter().find(|l| l.starts_with(&format!("fn {name}("))) {
                f.add_attribute(AttributeLoc::Function, ctx.create_string_attribute("spec.sig", line));
            }
        }
        plan.push((f, local, np, nr, val_abi));
    }

    let mut notes = sdk_note;
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
        strip_inline_suffixes(&m);
    }
    rename_decoded(&m, &md.mem, &spec);

    // The real check, and the reason for inkwell: a Val/i64 confusion at a call
    // site is a verifier error here. In hand-written text it never can be.
    m.verify().map_err(|e| e.to_string())?;
    Ok(format!("{}{}", notes, m.print_to_string().to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn build(ops: Vec<Operator>, nr: usize) -> Result<String, String> {
        build_with(ops, nr, 0, &Mod::default())
    }

    fn build_with(ops: Vec<Operator>, nr: usize, n_locals: usize, md: &Mod) -> Result<String, String> {
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
            &ctx, &m, &rt, f, 0, nr, n_locals, &ops, &HashMap::new(), &HashMap::new(), md, true,
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
        let ir = build_with(ops(), 1, 0, &md).unwrap();
        assert!(ir.contains("ret %Val %v_true"), "{ir}");
        // ...unless something in the module writes the segment.
        md.mem.written = true;
        let ir = build_with(ops(), 1, 0, &md).unwrap();
        assert!(ir.contains("@soroban.load8u(i64 1048576)"), "{ir}");
    }

    #[test]
    fn inline_mode_shows_set_flag_as_its_syscall() {
        let wasm = std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/samples/three_bugs.wasm")).unwrap();
        let ir = lower_module(&wasm, Some("--inline")).unwrap();
        let body = ir
            .lines()
            .skip_while(|l| !(l.starts_with("define ") && l.contains("@set_flag(")))
            .take_while(|l| !l.starts_with('}'))
            .collect::<Vec<_>>()
            .join("\n");
        assert!(body.contains("@ledger.put_contract_data("), "{body}");
        assert!(body.contains("%v_true"), "{body}");
        assert!(body.contains("%Persistent"), "{body}");
        assert!(!body.contains("@f"), "helper calls remain: {body}");
        // Inline suffixes are stripped, and the recovered frame leaves no
        // stack-pointer traffic or dead stores behind.
        assert!(body.contains("%put_contract_data = "), "{body}");
        assert!(!body.contains("@g0") && !body.contains(" store "), "{body}");
    }

    #[test]
    fn frame_is_an_alloca() {
        // LLVM's prologue, a spill and a reload through the frame, the epilogue.
        let ma = |offset| wasmparser::MemArg { align: 0, max_align: 0, offset, memory: 0 };
        let ops = vec![
            Operator::GlobalGet { global_index: 0 },
            Operator::I32Const { value: 16 },
            Operator::I32Sub,
            Operator::LocalTee { local_index: 0 },
            Operator::GlobalSet { global_index: 0 },
            Operator::LocalGet { local_index: 0 },
            Operator::I64Const { value: 7 },
            Operator::I64Store { memarg: ma(8) },
            Operator::LocalGet { local_index: 0 },
            Operator::I64Load { memarg: ma(8) },
            Operator::Drop,
            Operator::LocalGet { local_index: 0 },
            Operator::I32Const { value: 16 },
            Operator::I32Add,
            Operator::GlobalSet { global_index: 0 },
            Operator::I64Const { value: 2 },
            Operator::End,
        ];
        let ir = build_with(ops, 1, 1, &Mod::default()).unwrap();
        assert!(ir.contains("%frame = alloca [16 x i8]"), "{ir}");
        assert!(ir.contains("store i64 7, ptr %slot8"), "{ir}");
        assert!(ir.contains("load i64, ptr %slot8"), "{ir}");
        // No stack-pointer traffic and no memory helper: the frame is local.
        assert!(
            !ir.contains("call void @soroban.store64(") && !ir.contains("call i64 @soroban.load64(") && !ir.contains("ptrtoint"),
            "{ir}"
        );
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
    fn fingerprints_name_the_sdk_helpers() {
        // The table for the sample's own SDK version is checked in; exact
        // fingerprints name what the reference built the same way, shapes
        // name what register allocation laid out differently.
        std::env::set_var("PONYTAIL_FINGERPRINTS", concat!(env!("CARGO_MANIFEST_DIR"), "/fingerprints"));
        let wasm = std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/samples/three_bugs.wasm")).unwrap();
        let ir = lower_module(&wasm, Some("--all")).unwrap();
        assert!(ir.starts_with("; sdk 25.3.2 rustc 1.97.1; fingerprints 25.3.2.txt: 4 of 43 helpers named, 3 by shape\n"), "{}", ir.lines().next().unwrap_or(""));
        assert!(ir.contains("@Symbol_new(") && ir.contains("\"sdk.name\"=\"<soroban_sdk::symbol::Symbol>::new\""), "{ir}");
        assert_eq!(sdk_ident("<soroban_sdk::vec::Vec<T> as soroban_env_common::convert::TryFromVal<E, Val>>::try_from_val"), "Vec_try_from_val");
        assert_eq!(sdk_ident("<U as soroban_sdk::env::IntoVal<E,T>>::into_val"), "into_val");
        assert_eq!(sdk_ident("<(a::Val, a::Val) as a::TryIntoVal<E, a::Val>>::try_into_val"), "Tuple_try_into_val");
        assert_eq!(sdk_ident("compiler_builtins::mem::memcpy"), "memcpy");
        assert_eq!(sdk_ident("core::ptr::drop_in_place<soroban_sdk::vec::Vec<T>>"), "drop_in_place");
        // The version query, for gen.sh.
        assert_eq!(lower_module(&wasm, Some("--sdk")).unwrap(), "25.3.2 1.97.1\n");
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
