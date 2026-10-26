//! Backward program slice over the lifted LLVM IR, with Soroban-aware sinks.
//!
//! Two dependences:
//!   * DATA    — SSA def-use: an instruction depends on the instructions defining
//!               its operands (transitively). SSA makes this a graph walk.
//!   * CONTROL — an instruction depends on the branches deciding whether it runs,
//!               from the post-dominator tree (block L is control-dependent on
//!               branch-block A iff L lies on the post-dom path from a successor of
//!               A up to, but not including, ipostdom(A)).
//!
//! Sinks it recognises (the ways a contract moves value or reverts):
//!   * TRANSFER     — a host `call`/`try_call` (optionally symbol == "transfer").
//!   * TRAP         — an `unreachable` terminator or a `soroban.trap` call.
//!   * ERROR        — a `context.fail_with_error` call (the error-raise syscall).
//!   * ERROR-RETURN — a `ret` of an Error-tagged Val (top-level `Err(..)`).
//!
//! Seeded from a sink, it reports the storage reads, branch guards, and auth
//! preconditions the sink depends on. Build in the `stellar-diver` crate:
//!     nix-shell --run 'cargo run --release --bin slice -- file.ll [--fn F] \
//!         [--sink transfer|trap|error|error-ret|all] [--callee call] [--sym transfer|any]'
//!     nix-shell --run 'cargo test --release --bin slice'

use inkwell::attributes::AttributeLoc;
use inkwell::basic_block::BasicBlock;
use inkwell::context::Context;
use inkwell::memory_buffer::MemoryBuffer;
use inkwell::values::{
    AnyValue, BasicMetadataValueEnum, BasicValueEnum, FunctionValue, InstructionOpcode,
    InstructionValue, Operand, PointerValue,
};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet, VecDeque};
use std::path::PathBuf;

// ======================= value helpers =======================

/// The instruction defining a value, if it is one (constants/args are leaves).
fn as_instr(v: BasicValueEnum) -> Option<InstructionValue> {
    use BasicValueEnum::*;
    match v {
        ArrayValue(x) => x.as_instruction(),
        IntValue(x) => x.as_instruction(),
        FloatValue(x) => x.as_instruction(),
        PointerValue(x) => x.as_instruction(),
        StructValue(x) => x.as_instruction(),
        VectorValue(x) => x.as_instruction(),
        ScalableVectorValue(x) => x.as_instruction(),
    }
}

/// Single-line textual form of any value.
fn fmt<'c, V: AnyValue<'c>>(v: V) -> String {
    v.print_to_string()
        .to_string()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

/// Name of the function a `call` targets (the callee is the last operand).
fn callee_name(i: InstructionValue) -> Option<String> {
    if i.get_opcode() != InstructionOpcode::Call {
        return None;
    }
    let n = i.get_num_operands();
    match i.get_operand(n.checked_sub(1)?) {
        Some(Operand::Value(BasicValueEnum::PointerValue(p))) => {
            p.get_name().to_str().ok().map(str::to_owned)
        }
        _ => None,
    }
}

/// `want` matches a callee exactly or as a `module.name` suffix, so `call`
/// matches the lifted `@call.call` and `fail_with_error` matches
/// `@context.fail_with_error`.
fn callee_matches(name: &str, want: &str) -> bool {
    name == want || name.ends_with(&format!(".{want}"))
}

/// SDK plumbing that is never an interesting source/sink — folded out of reports.
fn is_plumbing(name: &str) -> bool {
    const P: &[&str] = &[
        "soroban.val.from_payload",
        "soroban.val.payload",
        "soroban.storage_type",
        "int.obj_from_i128",
        "int.obj_to_i128",
        "int.obj_from_u",
        "int.obj_to_u",
        "vec.vec_new",
        "buf.symbol_new",
        "context.get_current_contract_address",
    ];
    P.iter().any(|p| name.contains(p))
}

/// The i64 payload a value ultimately carries as a constant, looking through the
/// lifter's `soroban.val.from_payload(i64 CONST)` wrapper, else a bare constant.
fn const_payload(v: BasicValueEnum) -> Option<u64> {
    if let BasicValueEnum::IntValue(c) = v {
        if let Some(b) = c.get_zero_extended_constant() {
            return Some(b);
        }
    }
    let i = as_instr(v)?;
    if callee_name(i)?.contains("from_payload") {
        if let Some(Operand::Value(BasicValueEnum::IntValue(c))) = i.get_operand(0) {
            return c.get_zero_extended_constant();
        }
    }
    None
}

/// Decode a `SymbolSmall` (tag 14) Val constant to its text.
fn decode_symbol(bits: u64) -> Option<String> {
    if bits & 0xff != 14 {
        return None;
    }
    let mut body = bits >> 8;
    let mut chars = Vec::new();
    while body != 0 {
        let code = (body & 0x3f) as u8;
        chars.push(match code {
            1 => b'_',
            2..=11 => b'0' + (code - 2),
            12..=37 => b'A' + (code - 12),
            38..=63 => b'a' + (code - 38),
            _ => return None,
        });
        body >>= 6;
    }
    chars.reverse();
    String::from_utf8(chars).ok()
}

/// The symbol a `call`'s func operand (index 1) carries, if literal.
fn call_symbol(i: InstructionValue) -> Option<String> {
    match i.get_operand(1)? {
        Operand::Value(v) => const_payload(v).and_then(decode_symbol),
        _ => None,
    }
}

/// A Val constant is an Error iff its low-byte tag is 3; describe (type, code).
fn error_tag(bits: u64) -> bool {
    bits & 0xff == 3
}
fn error_desc(bits: u64) -> String {
    format!("Error(type={}, code={})", (bits >> 8) & 0xff_ffff, bits >> 32)
}

// ======================= CFG =======================

struct Cfg<'c> {
    blocks: Vec<BasicBlock<'c>>,
    succ: Vec<Vec<usize>>,
}

impl<'c> Cfg<'c> {
    fn build(f: FunctionValue<'c>) -> Self {
        let blocks: Vec<_> = f.get_basic_blocks();
        let idx = |b: BasicBlock<'c>| blocks.iter().position(|x| *x == b);
        let mut succ = vec![Vec::new(); blocks.len()];
        for (u, &b) in blocks.iter().enumerate() {
            if let Some(term) = b.get_terminator() {
                for k in 0..term.get_num_operands() {
                    // Block operands of a terminator are its CFG successors.
                    if let Some(Operand::Block(tgt)) = term.get_operand(k) {
                        if let Some(v) = idx(tgt) {
                            succ[u].push(v);
                        }
                    }
                }
            }
        }
        Cfg { blocks, succ }
    }

    fn bidx(&self, b: BasicBlock<'c>) -> Option<usize> {
        self.blocks.iter().position(|x| *x == b)
    }

    fn instrs(&self) -> impl Iterator<Item = InstructionValue<'c>> + '_ {
        self.blocks.iter().flat_map(|b| {
            let mut cur = b.get_first_instruction();
            std::iter::from_fn(move || {
                let i = cur?;
                cur = i.get_next_instruction();
                Some(i)
            })
        })
    }
}

// ======================= dominators (Cooper-Harvey-Kennedy) =======================

/// Immediate dominators over an arbitrary graph (succ for ordering, pred for the
/// dataflow, single entry). Unreachable nodes get `None`.
fn idoms(entry: usize, succ: &[Vec<usize>], pred: &[Vec<usize>]) -> Vec<Option<usize>> {
    let n = succ.len();
    // iterative-DFS postorder, then reverse-postorder as processing order.
    let (mut post, mut seen, mut stack) = (Vec::with_capacity(n), vec![false; n], vec![(entry, 0usize)]);
    seen[entry] = true;
    while let Some(&(u, ci)) = stack.last() {
        if ci < succ[u].len() {
            stack.last_mut().unwrap().1 += 1;
            let w = succ[u][ci];
            if !seen[w] {
                seen[w] = true;
                stack.push((w, 0));
            }
        } else {
            post.push(u);
            stack.pop();
        }
    }
    let mut po = vec![usize::MAX; n];
    for (i, &b) in post.iter().enumerate() {
        po[b] = i;
    }
    let rpo: Vec<usize> = post.iter().rev().copied().collect();

    let intersect = |mut a: usize, mut b: usize, idom: &[Option<usize>]| {
        while a != b {
            while po[a] < po[b] {
                a = idom[a].unwrap();
            }
            while po[b] < po[a] {
                b = idom[b].unwrap();
            }
        }
        a
    };

    let mut idom = vec![None; n];
    idom[entry] = Some(entry);
    let mut changed = true;
    while changed {
        changed = false;
        for &b in rpo.iter().filter(|&&b| b != entry) {
            let mut new_idom = None;
            for &p in &pred[b] {
                if idom[p].is_some() {
                    new_idom = Some(match new_idom {
                        None => p,
                        Some(cur) => intersect(p, cur, &idom),
                    });
                }
            }
            if new_idom.is_some() && idom[b] != new_idom {
                idom[b] = new_idom;
                changed = true;
            }
        }
    }
    idom
}

/// Immediate post-dominators: dominators of the reverse graph rooted at a virtual
/// exit (index `n`) that every real exit block flows into.
fn ipostdoms(cfg: &Cfg) -> Vec<Option<usize>> {
    let n = cfg.blocks.len();
    let x = n;
    let (mut succ_r, mut pred_r) = (vec![Vec::new(); n + 1], vec![Vec::new(); n + 1]);
    for u in 0..n {
        for &v in &cfg.succ[u] {
            succ_r[v].push(u);
            pred_r[u].push(v);
        }
        if cfg.succ[u].is_empty() {
            succ_r[x].push(u);
            pred_r[u].push(x);
        }
    }
    idoms(x, &succ_r, &pred_r)
}

/// For each block, the set of branch-blocks it is control-dependent on.
fn control_deps(cfg: &Cfg, ipdom: &[Option<usize>]) -> Vec<HashSet<usize>> {
    let n = cfg.blocks.len();
    let mut cd = vec![HashSet::new(); n];
    for a in 0..n {
        for &b in &cfg.succ[a] {
            let stop = ipdom[a];
            let mut l = Some(b);
            while let Some(ll) = l {
                if Some(ll) == stop || ll >= n {
                    break;
                }
                cd[ll].insert(a);
                l = ipdom[ll];
            }
        }
    }
    cd
}

// ======================= sinks =======================

#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
enum SinkKind {
    Transfer,
    Trap,
    Error,
    ErrorReturn,
}

struct Sink<'c> {
    kind: SinkKind,
    instr: InstructionValue<'c>,
    vals: Vec<BasicValueEnum<'c>>, // value seeds (sink's data operands)
    label: String,
}

/// All sinks of the requested kinds in a function.
fn find_sinks<'c>(
    cfg: &Cfg<'c>,
    kinds: &[SinkKind],
    callee: &str,
    sym: Option<&str>,
) -> Vec<Sink<'c>> {
    let want = |k: SinkKind| kinds.contains(&k);
    let mut out = Vec::new();
    for i in cfg.instrs() {
        let name = callee_name(i);
        // TRANSFER: a host call (optionally filtered by symbol).
        if want(SinkKind::Transfer) {
            if let Some(n) = &name {
                if callee_matches(n, callee) {
                    let s = call_symbol(i);
                    if sym.is_none() || s.as_deref() == sym {
                        let nops = i.get_num_operands();
                        let vals = (0..nops.saturating_sub(1))
                            .filter_map(|k| match i.get_operand(k) {
                                Some(Operand::Value(v)) => Some(v),
                                _ => None,
                            })
                            .collect();
                        out.push(Sink { kind: SinkKind::Transfer, instr: i, vals, label: s.unwrap_or_default() });
                    }
                }
            }
        }
        // ERROR: the fail_with_error syscall.
        if want(SinkKind::Error) {
            if let Some(n) = &name {
                if callee_matches(n, "fail_with_error") {
                    let code = i.get_operand(0).and_then(|o| match o {
                        Operand::Value(v) => const_payload(v),
                        _ => None,
                    });
                    let vals = match i.get_operand(0) {
                        Some(Operand::Value(v)) => vec![v],
                        _ => vec![],
                    };
                    out.push(Sink {
                        kind: SinkKind::Error,
                        instr: i,
                        vals,
                        label: code.map(error_desc).unwrap_or_else(|| "fail_with_error".into()),
                    });
                }
            }
        }
        // TRAP: unreachable terminator, or a soroban.trap call.
        if want(SinkKind::Trap) {
            if i.get_opcode() == InstructionOpcode::Unreachable {
                out.push(Sink { kind: SinkKind::Trap, instr: i, vals: vec![], label: "unreachable".into() });
            } else if name.as_deref().map(|n| callee_matches(n, "trap")).unwrap_or(false) {
                out.push(Sink { kind: SinkKind::Trap, instr: i, vals: vec![], label: "trap()".into() });
            }
        }
        // ERROR-RETURN: ret of an Error-tagged Val.
        if want(SinkKind::ErrorReturn) && i.get_opcode() == InstructionOpcode::Return {
            if let Some(Operand::Value(v)) = i.get_operand(0) {
                if let Some(bits) = const_payload(v).filter(|&b| error_tag(b)) {
                    out.push(Sink { kind: SinkKind::ErrorReturn, instr: i, vals: vec![v], label: error_desc(bits) });
                }
            }
        }
    }
    out
}

// ======================= the slice =======================

/// Backward slice to a fixpoint over data dependence (operands) and control
/// dependence (guarding branches), from value seeds plus seed instructions (the
/// latter for operand-less sinks like `unreachable`).
fn backward_slice<'c>(
    cfg: &Cfg<'c>,
    cd: &[HashSet<usize>],
    seed_vals: &[BasicValueEnum<'c>],
    seed_instrs: &[InstructionValue<'c>],
) -> HashSet<InstructionValue<'c>> {
    let mut seen: HashSet<InstructionValue<'c>> = HashSet::new();
    let mut work: VecDeque<InstructionValue<'c>> = VecDeque::new();
    let push_val = |v: BasicValueEnum<'c>, seen: &mut HashSet<_>, work: &mut VecDeque<_>| {
        if let Some(i) = as_instr(v) {
            if seen.insert(i) {
                work.push_back(i);
            }
        }
    };
    for &v in seed_vals {
        push_val(v, &mut seen, &mut work);
    }
    for &i in seed_instrs {
        if seen.insert(i) {
            work.push_back(i);
        }
    }

    // Light memory dependence: a load pulls in stores to the same pointer SSA
    // value (most frame slots are promoted to registers by the opt, so SSA covers
    // the bulk; this catches the rest).
    let mut stores_by_ptr: HashMap<PointerValue<'c>, Vec<InstructionValue<'c>>> = HashMap::new();
    for i in cfg.instrs() {
        if i.get_opcode() == InstructionOpcode::Store {
            if let Some(Operand::Value(BasicValueEnum::PointerValue(p))) = i.get_operand(1) {
                stores_by_ptr.entry(p).or_default().push(i);
            }
        }
    }

    while let Some(i) = work.pop_front() {
        // DATA
        for k in 0..i.get_num_operands() {
            if let Some(Operand::Value(v)) = i.get_operand(k) {
                push_val(v, &mut seen, &mut work);
            }
        }
        // MEMORY
        if i.get_opcode() == InstructionOpcode::Load {
            if let Some(Operand::Value(BasicValueEnum::PointerValue(p))) = i.get_operand(0) {
                if let Some(ss) = stores_by_ptr.get(&p) {
                    for &st in ss {
                        if seen.insert(st) {
                            work.push_back(st);
                        }
                    }
                }
            }
        }
        // CONTROL
        if let Some(bi) = i.get_parent().and_then(|bb| cfg.bidx(bb)) {
            for &a in &cd[bi] {
                if let Some(term) = cfg.blocks[a].get_terminator() {
                    if seen.insert(term) {
                        work.push_back(term);
                    }
                }
            }
        }
    }
    seen
}

/// A tidy classification of a slice for reporting.
struct Report<'c> {
    sources: Vec<InstructionValue<'c>>,
    guards: Vec<(InstructionValue<'c>, BasicValueEnum<'c>)>,
    preconds: Vec<InstructionValue<'c>>,
    other_calls: Vec<InstructionValue<'c>>,
    size: usize,
}

fn classify<'c>(slice: &HashSet<InstructionValue<'c>>, sink: InstructionValue<'c>) -> Report<'c> {
    let (mut sources, mut guards, mut preconds, mut other_calls) = (vec![], vec![], vec![], vec![]);
    for &i in slice {
        match i.get_opcode() {
            InstructionOpcode::Call => {
                let nm = callee_name(i).unwrap_or_default();
                if nm.contains("get_contract_data") || nm.contains("has_contract_data") {
                    sources.push(i);
                } else if nm.contains("require_auth") {
                    preconds.push(i);
                } else if i != sink && !is_plumbing(&nm) {
                    other_calls.push(i);
                }
            }
            InstructionOpcode::Load => sources.push(i),
            InstructionOpcode::Br | InstructionOpcode::Switch => {
                if let Some(Operand::Value(c)) = i.get_operand(0) {
                    guards.push((i, c));
                }
            }
            _ => {}
        }
    }
    Report { sources, guards, preconds, other_calls, size: slice.len() }
}

// ======================= symbolic summary =======================

/// A named data source a gate rests on: a contract arg, or a storage slot.
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
enum Src {
    Arg(String),
    Store { dur: String, params: Vec<String> },
    Contract, // this contract's own address (get_current_contract_address)
}
impl Src {
    fn show(&self) -> String {
        match self {
            Src::Arg(n) => n.clone(),
            Src::Contract => "this.address".into(),
            Src::Store { dur, params } if params.is_empty() => format!("storage.{dur}"),
            Src::Store { dur, params } => format!("storage.{dur}[{}]", params.join(", ")),
        }
    }
}

fn tag_name(k: u64) -> &'static str {
    match k {
        0 => "False", 1 => "True", 2 => "Void", 3 => "Error", 4 => "u32", 5 => "i32",
        6 | 64 => "u64", 7 | 65 => "i64", 10 | 68 => "u128", 11 | 69 => "i128",
        14 | 74 => "Symbol", 72 => "Bytes", 73 => "String", 75 => "Vec", 76 => "Map",
        77 => "Address", _ => "?",
    }
}

type Args<'c> = Vec<(BasicValueEnum<'c>, String, String)>; // (value, spec.name, spec.type)

/// (value, name, spec-type) for each contract parameter, from the ABI attributes.
fn arg_table<'c>(f: FunctionValue<'c>) -> Args<'c> {
    let get = |i: u32, k: &str| {
        f.get_string_attribute(AttributeLoc::Param(i), k)
            .map(|a| a.get_string_value().to_string_lossy().into_owned())
    };
    f.get_params()
        .into_iter()
        .enumerate()
        .map(|(i, v)| {
            (
                v,
                get(i as u32, "spec.name").unwrap_or_else(|| format!("arg{i}")),
                get(i as u32, "spec.type").unwrap_or_default(),
            )
        })
        .collect()
}

/// Durability behind a `storage_type(i64 K)` value.
fn durability(v: BasicValueEnum) -> String {
    if let Some(i) = as_instr(v) {
        if callee_name(i).map(|n| n.contains("storage_type")).unwrap_or(false) {
            if let Some(Operand::Value(BasicValueEnum::IntValue(c))) = i.get_operand(0) {
                return match c.get_zero_extended_constant() {
                    Some(0) => "temporary",
                    Some(1) => "persistent",
                    Some(2) => "instance",
                    _ => "?",
                }
                .into();
            }
        }
    }
    "?".into()
}

/// The `*_from_linear_memory` call a storage key is built from, looking through
/// the transparent `from_payload`/`val.payload` wrappers.
fn find_key_vec<'c>(v: BasicValueEnum<'c>, depth: u32) -> Option<InstructionValue<'c>> {
    if depth == 0 {
        return None;
    }
    let i = as_instr(v)?;
    let name = callee_name(i)?;
    if name.contains("from_linear_memory") {
        return Some(i);
    }
    if name.contains("from_payload") || name.contains("val.payload") {
        if let Some(Operand::Value(inner)) = i.get_operand(0) {
            return find_key_vec(inner, depth - 1);
        }
    }
    None
}

/// The named sources written into the linear-memory buffer a `*_from_linear_memory`
/// value is built from. The SDK emits those `store`s in the buffer's own block just
/// before the call, so we scan that block for stored values that resolve to a source.
/// Used for both storage keys (→ the key's params) and call-arg vectors.
fn linmem_srcs(v: BasicValueEnum, args: &Args) -> BTreeSet<Src> {
    let mut out = BTreeSet::new();
    let Some(vec) = find_key_vec(v, 8) else { return out };
    let Some(bb) = vec.get_parent() else { return out };
    let mut it = bb.get_first_instruction();
    while let Some(i) = it {
        if i == vec {
            break;
        }
        if i.get_opcode() == InstructionOpcode::Store {
            if let Some(Operand::Value(val)) = i.get_operand(0) {
                if let Some(s) = src_of(val, args) {
                    out.insert(s);
                }
            }
        }
        it = i.get_next_instruction();
    }
    out
}

/// The contract args a storage key is parameterised by (its address fields).
fn key_params(key: BasicValueEnum, args: &Args) -> BTreeSet<String> {
    linmem_srcs(key, args)
        .into_iter()
        .filter_map(|s| match s {
            Src::Arg(n) => Some(n),
            _ => None,
        })
        .collect()
}

/// The storage slot a `get/has_contract_data` call reads.
fn store_src(i: InstructionValue, args: &Args) -> Src {
    let dur = match i.get_operand(1) {
        Some(Operand::Value(x)) => durability(x),
        _ => "?".into(),
    };
    let params = match i.get_operand(0) {
        Some(Operand::Value(key)) => key_params(key, args),
        _ => BTreeSet::new(),
    };
    Src::Store { dur, params: params.into_iter().collect() }
}

/// The named source a value *is* (arg, or storage read), looking through the
/// transparent Val wrappers; `None` means "recurse past this intermediate".
fn src_of(v: BasicValueEnum, args: &Args) -> Option<Src> {
    if let Some((_, n, _)) = args.iter().find(|(pv, _, _)| *pv == v) {
        return Some(Src::Arg(n.clone()));
    }
    let i = as_instr(v)?;
    let name = callee_name(i)?;
    if name.contains("get_contract_data") || name.contains("has_contract_data") {
        return Some(store_src(i, args));
    }
    if name.contains("from_payload") || name.contains("val.payload") || name.contains("obj_to_i128") {
        if let Some(Operand::Value(inner)) = i.get_operand(0) {
            return src_of(inner, args);
        }
    }
    None
}

/// All named sources a value's def-tree rests on.
fn srcs_in(v: BasicValueEnum, args: &Args, depth: u32, out: &mut BTreeSet<Src>) {
    if depth == 0 {
        return;
    }
    if let Some(s) = src_of(v, args) {
        out.insert(s);
        return;
    }
    if let Some(i) = as_instr(v) {
        for k in 0..i.get_num_operands() {
            if let Some(Operand::Value(o)) = i.get_operand(k) {
                srcs_in(o, args, depth - 1, out);
            }
        }
    }
}

enum Gate {
    Type(String),            // typeof(x) == T   (ABI-guaranteed → discharged)
    Presence,                // storage key present (defaulting read → discharged)
    Value(BTreeSet<Src>),    // a real gate over named sources
}

/// Is this value an i1 (a boolean)?
fn is_bool(v: BasicValueEnum) -> bool {
    matches!(v, BasicValueEnum::IntValue(i) if i.get_type().get_bit_width() == 1)
}

/// The atomic boolean conditions an i1 is built from: a compiler combines
/// several gates with `and`/`or`/`xor`/`select` into one branch condition, so we
/// split them back apart before classifying.
fn bool_leaves<'c>(v: BasicValueEnum<'c>, depth: u32, out: &mut Vec<BasicValueEnum<'c>>) {
    use InstructionOpcode::*;
    if depth > 0 {
        if let Some(i) = as_instr(v) {
            if is_bool(v) && matches!(i.get_opcode(), And | Or | Xor | Select) {
                let mut any = false;
                for k in 0..i.get_num_operands() {
                    if let Some(Operand::Value(o)) = i.get_operand(k) {
                        if is_bool(o) {
                            bool_leaves(o, depth - 1, out);
                            any = true;
                        }
                    }
                }
                if any {
                    return;
                }
            }
        }
    }
    out.push(v);
}

/// Classify one atomic condition (no boolean combinators).
fn leaf_class(cond: BasicValueEnum, args: &Args) -> Gate {
    if let Some(ci) = as_instr(cond) {
        if ci.get_opcode() == InstructionOpcode::ICmp {
            let op0 = match ci.get_operand(0) {
                Some(Operand::Value(v)) => Some(v),
                _ => None,
            };
            let op1k = match ci.get_operand(1) {
                Some(Operand::Value(BasicValueEnum::IntValue(c))) => c.get_zero_extended_constant(),
                _ => None,
            };
            if let (Some(v0), Some(k)) = (op0, op1k) {
                // tag check: icmp eq (and x, 255), TAG
                if let Some(ai) = as_instr(v0) {
                    if ai.get_opcode() == InstructionOpcode::And {
                        if let Some(Operand::Value(BasicValueEnum::IntValue(m))) = ai.get_operand(1) {
                            if m.get_zero_extended_constant() == Some(255) {
                                return Gate::Type(tag_name(k).into());
                            }
                        }
                    }
                }
                // presence: icmp eq (payload of has_contract_data), 1
                if k == 1 {
                    if let Some(Src::Store { .. }) = src_of(v0, args) {
                        return Gate::Presence;
                    }
                }
            }
        }
    }
    let mut s = BTreeSet::new();
    srcs_in(cond, args, 40, &mut s);
    Gate::Value(s)
}

fn classify_gate(cond: BasicValueEnum, is_switch: bool, args: &Args) -> Gate {
    if is_switch {
        // a switch dispatches on a value: if it rests on a named source it is a
        // real value gate on it, otherwise it is a Val tag/type dispatch.
        let mut s = BTreeSet::new();
        srcs_in(cond, args, 40, &mut s);
        return if s.is_empty() { Gate::Type("tag-dispatch".into()) } else { Gate::Value(s) };
    }
    // decompose boolean combinations, classify each leaf, then combine: a real
    // value leaf makes the whole gate a value gate; otherwise type/presence win.
    let mut leaves = Vec::new();
    bool_leaves(cond, 16, &mut leaves);
    let (mut value, mut ty, mut presence) = (BTreeSet::new(), None, false);
    for lf in leaves {
        match leaf_class(lf, args) {
            Gate::Type(t) => ty = Some(t),
            Gate::Presence => presence = true,
            Gate::Value(s) => value.extend(s),
        }
    }
    if !value.is_empty() {
        Gate::Value(value)
    } else if let Some(t) = ty {
        Gate::Type(t)
    } else if presence {
        Gate::Presence
    } else {
        Gate::Value(BTreeSet::new()) // discharged as Val-form plumbing
    }
}

/// The full per-sink symbolic report: typed args, fused storage-level gates, the
/// discharged ABI gates, storage reads, and auth preconditions.
fn report_sink<'c>(
    fname: &str,
    f: FunctionValue<'c>,
    s: &Sink<'c>,
    slice: &HashSet<InstructionValue<'c>>,
    module: &inkwell::module::Module<'c>,
) {
    let args = arg_table(f);
    let r = classify(slice, s.instr);

    println!("\n=== {:?} sink in @{fname}: {}", s.kind, fmt(s.instr));
    if !s.label.is_empty() {
        println!("    label: {}", s.label);
    }
    let typed: Vec<String> = args
        .iter()
        .filter(|(_, _, t)| !t.is_empty())
        .map(|(_, n, t)| format!("{n}: {t}"))
        .collect();
    if !typed.is_empty() {
        println!("    args (ABI): {}", typed.join(", "));
    }

    // classify + fuse guards.
    let (mut types, mut presence, mut repr, mut value) =
        (BTreeSet::new(), 0usize, 0usize, Vec::<BTreeSet<Src>>::new());
    for (br, c) in &r.guards {
        match classify_gate(*c, br.get_opcode() == InstructionOpcode::Switch, &args) {
            Gate::Type(t) => {
                types.insert(t);
            }
            Gate::Presence => presence += 1,
            // a value gate that rests on no named source is Val-representation
            // plumbing (tag/form bit tests), not a real data gate — discharge it.
            Gate::Value(set) if set.is_empty() => repr += 1,
            Gate::Value(set) => value.push(set),
        }
    }
    let mut fused: Vec<(BTreeSet<Src>, usize)> = Vec::new();
    for set in value {
        match fused.iter_mut().find(|(s, _)| *s == set) {
            Some(e) => e.1 += 1,
            None => fused.push((set, 1)),
        }
    }

    println!(
        "  ENABLING GATES  ({} distinct, from {} raw IR guards):",
        fused.len(),
        r.guards.len()
    );
    for (set, n) in &fused {
        let shown: Vec<String> = set.iter().map(Src::show).collect();
        let pred = match shown.len() {
            0 => "<opaque>".into(),
            2 => format!("{}  ⋈  {}", shown[0], shown[1]),
            _ => shown.join(" , "),
        };
        let note = if *n > 1 {
            format!("   [fused from {n} equivalent IR conditions]")
        } else {
            String::new()
        };
        println!("      {pred}{note}");
    }
    let tlist: Vec<_> = types.iter().cloned().collect();
    println!(
        "  discharged by ABI: {} type gate(s) [{}], {} key-presence gate(s), {} Val-form gate(s)",
        tlist.len(),
        tlist.join(", "),
        presence,
        repr
    );

    // storage reads, as named slots.
    let mut stores: BTreeSet<String> = BTreeSet::new();
    let mut loads = 0usize;
    for &src in &r.sources {
        match callee_name(src) {
            Some(n) if n.contains("get_contract_data") || n.contains("has_contract_data") => {
                stores.insert(store_src(src, &args).show());
            }
            _ if src.get_opcode() == InstructionOpcode::Load => loads += 1,
            _ => {}
        }
    }
    println!("  reads: {}{}", stores.iter().cloned().collect::<Vec<_>>().join(", "),
        if loads > 0 { format!("  (+{loads} frame loads)") } else { String::new() });

    // auth preconditions (out-of-band — a precondition, not a data/control
    // dependency, so it is NOT in the slice: scan the whole function for it).
    let mut auths: BTreeSet<String> = BTreeSet::new();
    for bb in f.get_basic_blocks() {
        let mut it = bb.get_first_instruction();
        while let Some(i) = it {
            if callee_name(i).map(|n| n.contains("require_auth")).unwrap_or(false) {
                let who = i
                    .get_operand(0)
                    .and_then(|o| match o { Operand::Value(v) => src_of(v, &args), _ => None })
                    .map(|s| s.show())
                    .unwrap_or_else(|| "?".into());
                auths.insert(who);
            }
            it = i.get_next_instruction();
        }
    }
    if !auths.is_empty() {
        println!("  precond (out-of-band): require_auth({})",
            auths.iter().cloned().collect::<Vec<_>>().join(", "));
    }

    // effect footprint through outlined helpers (storage ops + transfers are
    // outlined into fastcc helpers in optimised contracts, so follow the graph).
    let (fr, fw, ft) = effect_footprint(f, module);
    if !fr.is_empty() || !fw.is_empty() || ft > 0 {
        println!(
            "  effect footprint (incl. helpers): reads {{{}}}, writes {{{}}}, {} token transfer(s)",
            fr.iter().cloned().collect::<Vec<_>>().join(", "),
            fw.iter().cloned().collect::<Vec<_>>().join(", "),
            ft
        );
    }
}

// ======================= effects + Lean emission =======================

/// `f`'s instructions in EXECUTION order: blocks in reverse postorder of the
/// CFG (a topological order, loops aside), not their layout order.
fn rpo_instrs<'c>(f: FunctionValue<'c>) -> Vec<InstructionValue<'c>> {
    let cfg = Cfg::build(f);
    let n = cfg.blocks.len();
    let (mut seen, mut post) = (vec![false; n], vec![]);
    // iterative DFS: (block, next successor index)
    let mut stack = if n > 0 { vec![(0usize, 0usize)] } else { vec![] };
    if n > 0 {
        seen[0] = true;
    }
    while let Some((b, k)) = stack.pop() {
        if let Some(&s) = cfg.succ[b].get(k) {
            stack.push((b, k + 1));
            if !seen[s] {
                seen[s] = true;
                stack.push((s, 0));
            }
        } else {
            post.push(b);
        }
    }
    post.reverse();
    post.extend((0..n).filter(|&b| !seen[b]));
    post.into_iter().flat_map(|b| cfg.blocks[b].get_instructions()).collect()
}

fn all_instrs<'c>(f: FunctionValue<'c>) -> Vec<InstructionValue<'c>> {
    let mut v = vec![];
    for bb in f.get_basic_blocks() {
        let mut it = bb.get_first_instruction();
        while let Some(i) = it {
            v.push(i);
            it = i.get_next_instruction();
        }
    }
    v
}

fn callee_has(i: InstructionValue, needle: &str) -> bool {
    callee_name(i).map(|n| n.contains(needle)).unwrap_or(false)
}

/// The addresses a function authorises (`require_auth`).
fn auth_of(f: FunctionValue, args: &Args) -> Vec<String> {
    let mut s = BTreeSet::new();
    for i in all_instrs(f) {
        if callee_has(i, "require_auth") {
            if let Some(Operand::Value(v)) = i.get_operand(0) {
                if let Some(src) = src_of(v, args) {
                    s.insert(src.show());
                }
            }
        }
    }
    s.into_iter().collect()
}

/// The storage/transfer footprint of an entry INCLUDING the internal `fastcc`
/// helpers it calls (transitively). Real contracts outline every storage op and
/// token transfer into helpers, so an intra-procedural scan sees nothing; this
/// follows the call graph. Keys/params live in the callee's frame and are not
/// mapped across the boundary yet, so only durability + transfer count recover.
fn effect_footprint<'c>(
    entry: FunctionValue<'c>,
    module: &inkwell::module::Module<'c>,
) -> (BTreeSet<String>, BTreeSet<String>, usize) {
    let (mut reads, mut writes, mut transfers) = (BTreeSet::new(), BTreeSet::new(), 0usize);
    let mut seen: HashSet<String> = HashSet::new();
    let mut work = vec![entry];
    let mut budget = 20000;
    while let Some(g) = work.pop() {
        let gn = g.get_name().to_string_lossy().into_owned();
        if !seen.insert(gn) || budget == 0 {
            continue;
        }
        budget -= 1;
        for i in all_instrs(g) {
            let Some(n) = callee_name(i) else { continue };
            if n.contains("get_contract_data") || n.contains("has_contract_data") {
                if let Some(Operand::Value(x)) = i.get_operand(1) {
                    reads.insert(durability(x));
                }
            } else if n.contains("put_contract_data") {
                if let Some(Operand::Value(x)) = i.get_operand(2) {
                    writes.insert(durability(x));
                }
            } else if n.contains("call.call") && call_symbol(i).as_deref() == Some("transfer") {
                transfers += 1;
            } else if let Some(callee) = module.get_function(&n) {
                if callee.count_basic_blocks() > 0 {
                    work.push(callee);
                }
            }
        }
    }
    (reads, writes, transfers)
}

/// Is this a public contract entry (its params carry ABI spec names)?
fn is_entry(f: FunctionValue) -> bool {
    // an ABI-described export: named params, or (a zero-arg export like
    // `increment()`) an exported function with a body.
    f.get_params()
        .iter()
        .enumerate()
        .any(|(i, _)| f.get_string_attribute(AttributeLoc::Param(i as u32), "spec.name").is_some())
        || (f.count_basic_blocks() > 0
            && f.get_linkage() != inkwell::module::Linkage::Internal
            && (f.get_string_attribute(AttributeLoc::Function, "spec.type").is_some()
                || f.get_string_attribute(AttributeLoc::Return, "spec.type").is_some()))
}

// ================= transitive transfer / arithmetic recovery =================

/// An address value: an arg, this contract, or a storage slot — looking through
/// Val wrappers. Used to read SEP-41 transfer (from, to) operands.
fn addr_src(v: BasicValueEnum, args: &Args) -> Option<Src> {
    if let Some(s) = src_of(v, args) {
        return Some(s);
    }
    let i = as_instr(v)?;
    let n = callee_name(i)?;
    if n.contains("get_current_contract_address") {
        return Some(Src::Contract);
    }
    if n.contains("from_payload") || n.contains("val.payload") {
        if let Some(Operand::Value(inner)) = i.get_operand(0) {
            return addr_src(inner, args);
        }
    }
    None
}

fn is_address_arg(name: &str, args: &Args) -> bool {
    args.iter().any(|(_, n, t)| n == name && t == "Address")
}

/// Byte offset of a frame `getelementptr`, so linear-memory stores can be ordered.
fn gep_off(ptr: BasicValueEnum) -> i64 {
    if let Some(i) = as_instr(ptr) {
        if i.get_opcode() == InstructionOpcode::GetElementPtr {
            let n = i.get_num_operands();
            if n >= 2 {
                if let Some(Operand::Value(BasicValueEnum::IntValue(c))) = i.get_operand(n - 1) {
                    return c.get_sign_extended_constant().unwrap_or(0);
                }
            }
        }
    }
    0
}

/// The ordered address operands written into a call-arg vector (SEP-41 from, to).
fn addr_seq(v: BasicValueEnum, args: &Args) -> Vec<Src> {
    let mut stores: Vec<(i64, Src)> = vec![];
    let Some(vec) = find_key_vec(v, 8) else { return vec![] };
    let Some(bb) = vec.get_parent() else { return vec![] };
    let mut it = bb.get_first_instruction();
    while let Some(i) = it {
        if i == vec {
            break;
        }
        if i.get_opcode() == InstructionOpcode::Store {
            let off = match i.get_operand(1) {
                Some(Operand::Value(p)) => gep_off(p),
                _ => 0,
            };
            if let Some(Operand::Value(val)) = i.get_operand(0) {
                if let Some(s) = addr_src(val, args) {
                    if matches!(s, Src::Contract) || matches!(&s, Src::Arg(n) if is_address_arg(n, args)) {
                        stores.push((off, s));
                    }
                }
            }
        }
        it = i.get_next_instruction();
    }
    stores.sort_by_key(|(o, _)| *o);
    stores.into_iter().map(|(_, s)| s).collect()
}

/// Does this value's def-tree add or subtract two distinct named sources?
/// ('-' for the balance-decreasing path, '+' for increasing, '?' if neither.)
fn delta_op(v: BasicValueEnum, args: &Args) -> char {
    fn two_sources(i: InstructionValue, args: &Args) -> bool {
        let s0 = match i.get_operand(0) {
            Some(Operand::Value(x)) => {
                let mut s = BTreeSet::new();
                srcs_in(x, args, 40, &mut s);
                s
            }
            _ => BTreeSet::new(),
        };
        let s1 = match i.get_operand(1) {
            Some(Operand::Value(x)) => {
                let mut s = BTreeSet::new();
                srcs_in(x, args, 40, &mut s);
                s
            }
            _ => BTreeSet::new(),
        };
        !s0.is_empty() && !s1.is_empty() && s0 != s1
    }
    let mut seen = HashSet::new();
    let mut work = vec![v];
    let mut saw_add = false;
    while let Some(x) = work.pop() {
        let Some(i) = as_instr(x) else { continue };
        if !seen.insert(fmt(i)) {
            continue;
        }
        match i.get_opcode() {
            InstructionOpcode::Sub if two_sources(i, args) => return '-',
            InstructionOpcode::Add if two_sources(i, args) => saw_add = true,
            _ => {}
        }
        for k in 0..i.get_num_operands() {
            if let Some(Operand::Value(o)) = i.get_operand(k) {
                work.push(o);
            }
        }
    }
    if saw_add {
        '+'
    } else {
        '?'
    }
}

/// If `g` is a storage setter (a fn whose body does a put), its durability.
fn setter_dur(g: FunctionValue) -> Option<String> {
    for i in all_instrs(g) {
        if callee_has(i, "put_contract_data") {
            return match i.get_operand(2) {
                Some(Operand::Value(x)) => Some(durability(x)),
                _ => None,
            };
        }
    }
    None
}

struct Update {
    slot: Src,
    op: char,              // '+', '-', or '?'
    amount: BTreeSet<Src>, // sources other than the slot itself
}

/// Storage updates of `f`: direct puts, plus one level of `fastcc` setter calls
/// (NO deeper interprocedural descent, per the chosen abstraction).
fn write_updates<'c>(f: FunctionValue<'c>, module: &inkwell::module::Module<'c>, args: &Args) -> Vec<Update> {
    let mut ups = vec![];
    for i in all_instrs(f) {
        // direct put in this function.
        if callee_has(i, "put_contract_data") {
            let dur = match i.get_operand(2) {
                Some(Operand::Value(x)) => durability(x),
                _ => "?".into(),
            };
            let params = match i.get_operand(0) {
                Some(Operand::Value(k)) => key_params(k, args).into_iter().collect(),
                _ => vec![],
            };
            let slot = Src::Store { dur, params };
            let (op, mut amount) = match i.get_operand(1) {
                Some(Operand::Value(val)) => {
                    let mut s = BTreeSet::new();
                    srcs_in(val, args, 40, &mut s);
                    (delta_op(val, args), s)
                }
                _ => ('?', BTreeSet::new()),
            };
            amount.remove(&slot);
            ups.push(Update { slot, op, amount });
            continue;
        }
        // one-level fastcc setter call.
        let Some(name) = callee_name(i) else { continue };
        let Some(g) = module.get_function(&name) else { continue };
        if g.count_basic_blocks() == 0 {
            continue;
        }
        let Some(dur) = setter_dur(g) else { continue };
        let mut keyp = BTreeSet::new();
        let mut valsrcs = BTreeSet::new();
        let mut op = '?';
        for k in 0..i.get_num_operands().saturating_sub(1) {
            let Some(Operand::Value(a)) = i.get_operand(k) else { continue };
            if let Some(Src::Arg(n)) = src_of(a, args) {
                if is_address_arg(&n, args) {
                    keyp.insert(n);
                    continue;
                }
            }
            srcs_in(a, args, 40, &mut valsrcs);
            if op == '?' {
                op = delta_op(a, args);
            }
        }
        let slot = Src::Store { dur, params: keyp.into_iter().collect() };
        valsrcs.remove(&slot);
        ups.push(Update { slot, op, amount: valsrcs });
    }
    ups
}

// ---- transitive SEP-41 transfer summary (general, any depth) ----

/// The length of a `*_from_linear_memory` vector (its `U32Val` count operand).
fn vec_len(vec: InstructionValue) -> usize {
    if let Some(Operand::Value(v)) = vec.get_operand(1) {
        if let Some(i) = as_instr(v) {
            if callee_has(i, "from_payload") {
                if let Some(Operand::Value(BasicValueEnum::IntValue(c))) = i.get_operand(0) {
                    return (c.get_zero_extended_constant().unwrap_or(0) >> 32) as usize;
                }
            }
        }
    }
    0
}

/// The values stored into a call-arg vector, in element order (the last `len`
/// frame stores before the vec, sorted by offset) — e.g. [from, to, amount].
fn linmem_vals_ordered<'c>(v: BasicValueEnum<'c>) -> Vec<BasicValueEnum<'c>> {
    let Some(vec) = find_key_vec(v, 8) else { return vec![] };
    let Some(bb) = vec.get_parent() else { return vec![] };
    let len = vec_len(vec);
    let mut stores: Vec<(i64, BasicValueEnum)> = vec![];
    let mut it = bb.get_first_instruction();
    while let Some(i) = it {
        if i == vec {
            break;
        }
        if i.get_opcode() == InstructionOpcode::Store {
            let off = match i.get_operand(1) {
                Some(Operand::Value(p)) => gep_off(p),
                _ => 0,
            };
            if let Some(Operand::Value(val)) = i.get_operand(0) {
                stores.push((off, val));
            }
        }
        it = i.get_next_instruction();
    }
    stores.sort_by_key(|(o, _)| *o);
    if len > 0 && stores.len() >= len {
        stores.split_off(stores.len() - len).into_iter().map(|(_, v)| v).collect()
    } else {
        stores.into_iter().map(|(_, v)| v).collect()
    }
}

/// Which parameter of `g` a value is (through Val wrappers), if any.
fn param_index(v: BasicValueEnum, g: FunctionValue) -> Option<usize> {
    for (i, p) in g.get_params().iter().enumerate() {
        if *p == v {
            return Some(i);
        }
    }
    let i = as_instr(v)?;
    let n = callee_name(i)?;
    if n.contains("from_payload") || n.contains("val.payload") || n.contains("obj_to_i128") {
        if let Some(Operand::Value(o)) = i.get_operand(0) {
            return param_index(o, g);
        }
    }
    None
}

/// Where a transfer operand comes from, relative to a function's parameters.
#[derive(Clone, Copy, PartialEq)]
enum ARef {
    Param(usize),
    Contract,
    Other,
}

fn aref(v: BasicValueEnum, g: FunctionValue) -> ARef {
    if let Some(i) = param_index(v, g) {
        return ARef::Param(i);
    }
    if let Some(ins) = as_instr(v) {
        let n = callee_name(ins).unwrap_or_default();
        if n.contains("get_current_contract_address") {
            return ARef::Contract;
        }
        if n.contains("from_payload") || n.contains("val.payload") || n.contains("obj_to_i128") {
            if let Some(Operand::Value(o)) = ins.get_operand(0) {
                return aref(o, g);
            }
        }
    }
    ARef::Other
}

#[derive(Clone)]
struct TFact {
    from: ARef,
    to: ARef,
    amount: ARef,
}

/// Transitive SEP-41 transfer summary of `g`, as facts over g's OWN parameters.
/// Descends through `fastcc` helpers, substituting call-site args at each hop.
fn summarize<'c>(
    g: FunctionValue<'c>,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Vec<TFact>>,
    depth: u32,
) -> Vec<TFact> {
    let name = g.get_name().to_string_lossy().into_owned();
    if let Some(f) = memo.get(&name) {
        return f.clone();
    }
    memo.insert(name.clone(), vec![]); // recursion guard
    if depth == 0 {
        return vec![];
    }
    let mut facts = vec![];
    for i in all_instrs(g) {
        if callee_has(i, "call.call") && call_symbol(i).as_deref() == Some("transfer") {
            let vals = match i.get_operand(2) {
                Some(Operand::Value(av)) => linmem_vals_ordered(av),
                _ => vec![],
            };
            let at = |k: usize| vals.get(k).map(|v| aref(*v, g)).unwrap_or(ARef::Other);
            facts.push(TFact { from: at(0), to: at(1), amount: at(2) });
            continue;
        }
        let Some(cn) = callee_name(i) else { continue };
        let Some(h) = module.get_function(&cn) else { continue };
        if h.count_basic_blocks() == 0 {
            continue;
        }
        let hs = summarize(h, module, memo, depth - 1);
        // map h's param-relative facts to g's terms via the call-site actuals.
        let remap = |r: ARef| match r {
            ARef::Param(j) => match i.get_operand(j as u32) {
                Some(Operand::Value(a)) => aref(a, g),
                _ => ARef::Other,
            },
            other => other,
        };
        for f in hs {
            facts.push(TFact { from: remap(f.from), to: remap(f.to), amount: remap(f.amount) });
        }
    }
    memo.insert(name, facts.clone());
    facts
}

/// Direction of each SEP-41 transfer w.r.t. a user arg: +1 user receives,
/// -1 user sends, 0 unknown. (SEP-41 is abstracted: no descent into the token.)
fn transfer_dirs(f: FunctionValue, args: &Args) -> Vec<i32> {
    let mut out = vec![];
    for i in all_instrs(f) {
        if callee_has(i, "call.call") && call_symbol(i).as_deref() == Some("transfer") {
            let seq = match i.get_operand(2) {
                Some(Operand::Value(av)) => addr_seq(av, args),
                _ => vec![],
            };
            let dir = match seq.first().zip(seq.get(1)) {
                Some((Src::Contract, Src::Arg(_))) => 1,
                Some((Src::Arg(_), Src::Contract)) => -1,
                _ => 0,
            };
            out.push(dir);
        }
    }
    out
}

#[derive(Clone, Copy, PartialEq)]
enum RelOp { Lt, Le, Gt, Ge, Eq, Ne }
impl RelOp {
    fn negate(self) -> RelOp {
        match self {
            RelOp::Lt => RelOp::Ge, RelOp::Le => RelOp::Gt, RelOp::Gt => RelOp::Le,
            RelOp::Ge => RelOp::Lt, RelOp::Eq => RelOp::Ne, RelOp::Ne => RelOp::Eq,
        }
    }
    fn lean(self) -> &'static str {
        match self {
            RelOp::Lt => "<", RelOp::Le => "≤", RelOp::Gt => ">",
            RelOp::Ge => "≥", RelOp::Eq => "=", RelOp::Ne => "≠",
        }
    }
}

/// One side of a recovered relation, as an SMT term over the state.
fn side_smt(srcs: &BTreeSet<Src>) -> Option<String> {
    if srcs.len() != 1 {
        return None;
    }
    match srcs.iter().next().unwrap() {
        Src::Store { dur, .. } => Some(format!("s_{dur}")),
        Src::Arg(n) => Some(n.clone()),
        Src::Contract => None,
    }
}

fn srcs_of(v: BasicValueEnum, args: &Args) -> BTreeSet<Src> {
    let mut s = BTreeSet::new();
    srcs_in(v, args, 40, &mut s);
    s
}

/// Recover a relation (op, lhs, rhs) from a branch condition: a plain `icmp`,
/// or the i128 limb-compare idiom `select (icmp eq hi)(icmp P lo)(icmp P hi)`.
fn gate_rel(cond: BasicValueEnum, args: &Args) -> Option<(RelOp, BTreeSet<Src>, BTreeSet<Src>)> {
    let i = as_instr(cond)?;
    // i128 idiom: select i1 %eqhi, i1 %cmplo, i1 %cmphi  ==>  A < B
    if i.get_opcode() == InstructionOpcode::Select {
        let lo = match i.get_operand(1) { Some(Operand::Value(v)) => as_instr(v), _ => None };
        let hi = match i.get_operand(2) { Some(Operand::Value(v)) => as_instr(v), _ => None };
        if let (Some(lo), Some(hi)) = (lo, hi) {
            if lo.get_opcode() == InstructionOpcode::ICmp && hi.get_opcode() == InstructionOpcode::ICmp {
                let a = match hi.get_operand(0) { Some(Operand::Value(v)) => srcs_of(v, args), _ => BTreeSet::new() };
                let b = match hi.get_operand(1) { Some(Operand::Value(v)) => srcs_of(v, args), _ => BTreeSet::new() };
                if !a.is_empty() && !b.is_empty() && a != b {
                    return Some((RelOp::Lt, a, b));
                }
            }
        }
        return None;
    }
    if i.get_opcode() == InstructionOpcode::ICmp {
        let op = match i.get_icmp_predicate()? {
            inkwell::IntPredicate::SLT | inkwell::IntPredicate::ULT => RelOp::Lt,
            inkwell::IntPredicate::SLE | inkwell::IntPredicate::ULE => RelOp::Le,
            inkwell::IntPredicate::SGT | inkwell::IntPredicate::UGT => RelOp::Gt,
            inkwell::IntPredicate::SGE | inkwell::IntPredicate::UGE => RelOp::Ge,
            inkwell::IntPredicate::EQ => RelOp::Eq,
            inkwell::IntPredicate::NE => RelOp::Ne,
        };
        let a = match i.get_operand(0) { Some(Operand::Value(v)) => srcs_of(v, args), _ => BTreeSet::new() };
        let b = match i.get_operand(1) { Some(Operand::Value(v)) => srcs_of(v, args), _ => BTreeSet::new() };
        // keep only relations between named sources (skip tag/const plumbing).
        if !a.is_empty() && !b.is_empty() && a != b {
            return Some((op, a, b));
        }
    }
    None
}

struct Trans {
    action: String,
    amount: Option<String>,
    guards: Vec<(RelOp, String, String)>, // success guards: op(lhs, rhs), as state/amount terms
    writes: Vec<(String, char, String)>,  // (slot var, '+'/'-'/'?', amount name | havoc var)
    ext: i32,                             // net SEP-41 direction on the user: +recv / -send / 0
    auth: Vec<String>,
    prov: Vec<String>,
}

/// A state term ("s_persistent", "ext", amount name, "0") rendered for Lean.
fn lean_term(t: &str) -> String {
    if let Some(rest) = t.strip_prefix("s_") {
        format!("s.{rest}")
    } else if t == "ext" || t == "ext0" {
        format!("s.{t}")
    } else {
        t.to_string() // an amount arg (bound var) or a literal
    }
}

/// A Lean-safe identifier for an action constructor.
fn lean_ctor(name: &str) -> String {
    let c = name.trim_start_matches('_');
    match c {
        "" => "act".into(),
        "constructor" => "construct".into(),
        "end" | "match" | "fun" | "let" | "do" | "if" | "then" | "else" => format!("{c}_"),
        _ if c.chars().next().map(|ch| ch.is_ascii_alphabetic()).unwrap_or(false) => c.into(),
        _ => format!("a_{c}"),
    }
}

/// Emit a concrete Lean 4 state machine (no Mathlib: `omega` discharges the
/// linear goals). Storage slots with recovered arithmetic + the SEP-41-abstracted
/// external balance are the state; the author writes the invariant, and the
/// inductive-preservation theorem is proved over the *emitted* step/guard.
fn emit_lean_sm(trans: &[Trans], slots: &BTreeSet<String>) {
    // track only slots whose arithmetic was actually recovered (a +/- write).
    let tracked: Vec<String> = slots
        .iter()
        .filter(|d| {
            let v = format!("s_{d}");
            trans.iter().any(|t| t.writes.iter().any(|(sv, op, _)| *sv == v && *op != '?'))
        })
        .cloned()
        .collect();

    println!("-- Auto-emitted by stellar-diver from lifted LLVM IR (one representative user).");
    println!("-- State = storage slots with recovered arithmetic + the SEP-41 external balance.");
    println!("-- SEP-41 transfers are abstracted by their spec; one-level setter summary.");
    println!("-- The preservation theorem below is proved over this emitted step/guard.\n");
    println!("namespace Contract\n");

    // ----- State -----
    println!("structure State where");
    for d in &tracked {
        println!("  {d} : Int        -- storage.{d}[user]");
    }
    println!("  ext  : Int        -- user's external balance of the token (SEP-41, abstracted)");
    println!("  ext0 : Int        -- initial external balance (constant)\n");

    // field accessor for a slot var "s_<dur>".
    let field = |sv: &str| sv.strip_prefix("s_").unwrap_or(sv).to_string();
    let is_tracked = |sv: &str| tracked.iter().any(|d| format!("s_{d}") == sv);

    // ----- Action -----
    println!("inductive Action where");
    for t in trans {
        let c = lean_ctor(&t.action);
        match &t.amount {
            Some(a) => println!("  | {c} ({a} : Int) : Action"),
            None => println!("  | {c} : Action"),
        }
    }
    println!();

    // ----- guard -----
    println!("-- recovered preconditions (guards + SEP-41 transfer spec)");
    println!("def guard (s : State) : Action → Prop");
    for t in trans {
        let c = lean_ctor(&t.action);
        let bind = if t.amount.is_some() { format!(" {}", t.amount.as_ref().unwrap()) } else { String::new() };
        let mut parts: Vec<String> = t
            .guards
            .iter()
            .map(|(op, l, r)| format!("{} {} {}", lean_term(l), op.lean(), lean_term(r)))
            .collect();
        if let Some(a) = &t.amount {
            if t.ext != 0 {
                parts.push(format!("{a} ≥ 0"));
            }
            if t.ext < 0 {
                parts.push(format!("s.ext ≥ {a}"));
            }
        }
        let body = if parts.is_empty() { "True".to_string() } else { parts.join(" ∧ ") };
        println!("  | .{c}{bind} => {body}");
    }
    println!();

    // ----- step -----
    println!("-- recovered state updates");
    println!("def step (s : State) : Action → State");
    for t in trans {
        let c = lean_ctor(&t.action);
        let bind = if t.amount.is_some() { format!(" {}", t.amount.as_ref().unwrap()) } else { String::new() };
        let mut upd: Vec<String> = vec![];
        for (sv, op, amt) in &t.writes {
            if *op == '?' || !is_tracked(sv) {
                continue; // untracked / unrecovered -> left unchanged
            }
            let f = field(sv);
            upd.push(format!("{f} := s.{f} {op} {amt}"));
        }
        if t.ext != 0 {
            if let Some(a) = &t.amount {
                let sign = if t.ext > 0 { '+' } else { '-' };
                upd.push(format!("ext := s.ext {sign} {a}"));
            }
        }
        if upd.is_empty() {
            println!("  | .{c}{bind} => s");
        } else {
            println!("  | .{c}{bind} => {{ s with {} }}", upd.join(", "));
        }
    }
    println!();

    // ----- init -----
    let mut init_fields: Vec<String> = tracked.iter().map(|d| format!("{d} := 0")).collect();
    init_fields.push("ext := e".into());
    init_fields.push("ext0 := e".into());
    println!("-- a fresh user: empty records, external balance e");
    println!("def init (e : Int) : State := {{ {} }}\n", init_fields.join(", "));

    // ----- invariant (author edits) + proofs over the emitted model -----
    let coupling = {
        let mut terms: Vec<String> = tracked.iter().map(|d| format!("s.{d}")).collect();
        terms.push("s.ext".into());
        terms.join(" + ")
    };
    println!("-- ===== WRITE YOUR INVARIANT HERE (over the State fields above) =====");
    println!("-- The property you want: \"no operation lets you end with more token than you started\".");
    println!("-- It needs the conservation coupling to be inductive (first conjunct is the property):");
    println!("def Inv (s : State) : Prop :=");
    println!("  s.ext ≤ s.ext0 ∧ {coupling} ≤ s.ext0\n");

    println!("-- holds initially");
    println!("theorem init_holds (e : Int) : Inv (init e) := by");
    println!("  simp only [Inv, init] <;> omega\n");

    println!("-- PROVED over the emitted step/guard, for every action, by `omega` (linear):");
    println!("theorem inductive_step (s : State) (a : Action)");
    println!("    (h : Inv s) (g : guard s a) : Inv (step s a) := by");
    println!("  cases a <;> simp_all [Inv, guard, step] <;> omega\n");

    println!("-- the property you care about is the first conjunct:");
    println!("theorem no_free_tokens (s : State) (h : Inv s) : s.ext ≤ s.ext0 := h.1\n");

    println!("end Contract");
}

// ================= faithful symbolic value translation (general) =================

/// A recovered value expression over a function's parameters and storage.
#[derive(Clone, PartialEq)]
enum Expr {
    Param(usize),             // a parameter of the function being analyzed
    Slot(String, usize),      // a storage read: durability + key arity
    Const(i64),
    Bin(char, Box<Expr>, Box<Expr>), // +, -, *, /, % on recognized arithmetic
    VecGet(Box<Expr>, Box<Expr>),    // vec_get(handle, index): a symbolic array read
    Opaque(String, Vec<Expr>),       // an unrecognized op, as an uninterpreted fn of its inputs
}

/// Map a host arithmetic callee to an operator, if recognized.
fn host_op(name: &str) -> Option<char> {
    let n = name;
    if n.contains("u256_mul") || n.contains("i128_mul") || n.ends_with(".mul") {
        Some('*')
    } else if n.contains("u256_div") || n.contains("i128_div") || n.ends_with(".div") {
        Some('/')
    } else if n.contains("u256_add") || n.contains("i128_add") {
        Some('+')
    } else if n.contains("u256_sub") || n.contains("i128_sub") {
        Some('-')
    } else if n.contains("rem_euclid") || n.contains("u256_rem") {
        Some('%')
    } else {
        None
    }
}

/// Is this callee a transparent Val/int wrapper we look straight through?
/// Includes the value-preserving u128<->u256 conversions (byte (de)serialization),
/// so the operands of a u256 multiply/divide resolve to the underlying integer.
fn is_wrapper(name: &str) -> bool {
    name.contains("from_payload")
        || name.contains("val.payload")
        || name.contains("obj_to_u128")
        || name.contains("obj_to_i128")
        || name.contains("obj_to_u64")
        || name.contains("obj_to_i64")
        || name.contains("obj_from_u64")
        || name.contains("obj_from_i64")
        || name.contains("u256_val_from_be_bytes")
        || name.contains("u256_val_to_be_bytes")
        || name.contains("obj_to_u256")
        || name.contains("obj_to_i256")
}

/// Base identity + byte offset of a pointer, chasing geps to the alloca and
/// through `inttoptr` of a `ptrtoint(alloca) (+ const)` address (the wasm shadow
/// stack reconstructs frame pointers that way). Only CONSTANT offsets are
/// tracked; a dynamic offset yields an opaque base (so it won't alias-match).
fn ptr_base_off(p: BasicValueEnum) -> (String, i64) {
    if let Some(i) = as_instr(p) {
        match i.get_opcode() {
            InstructionOpcode::GetElementPtr => {
                if let Some(Operand::Value(base)) = i.get_operand(0) {
                    let (b, o) = ptr_base_off(base);
                    return (b, o + gep_off(p));
                }
            }
            InstructionOpcode::IntToPtr => {
                if let Some(Operand::Value(addr)) = i.get_operand(0) {
                    return addr_base_off(addr);
                }
            }
            _ => {}
        }
    }
    (fmt(p), 0)
}

/// Base + constant offset of an i64 ADDRESS value (shadow-stack arithmetic).
fn addr_base_off(a: BasicValueEnum) -> (String, i64) {
    if let Some(i) = as_instr(a) {
        match i.get_opcode() {
            // a phi whose incomings all agree (`phi [trunc %0, …], [trunc %0, …]`).
            InstructionOpcode::Phi => {
                if let Ok(phi) = inkwell::values::PhiValue::try_from(i) {
                    let ins: Vec<(String, i64)> = (0..phi.count_incoming())
                        .filter_map(|k| phi.get_incoming(k))
                        .map(|(x, _)| if as_instr(x).is_some_and(|j| j.get_opcode() == InstructionOpcode::Phi) { (fmt(x), 0) } else { addr_base_off(x) })
                        .collect();
                    if !ins.is_empty() && ins.iter().all(|x| *x == ins[0]) {
                        return ins[0].clone();
                    }
                }
            }
            InstructionOpcode::Add => {
                if let (Some(Operand::Value(x)), Some(Operand::Value(BasicValueEnum::IntValue(c)))) =
                    (i.get_operand(0), i.get_operand(1))
                {
                    if let Some(k) = c.get_sign_extended_constant() {
                        let (b, o) = addr_base_off(x);
                        return (b, o + k);
                    }
                }
            }
            InstructionOpcode::ZExt | InstructionOpcode::SExt | InstructionOpcode::Trunc => {
                if let Some(Operand::Value(x)) = i.get_operand(0) {
                    return addr_base_off(x);
                }
            }
            InstructionOpcode::PtrToInt => {
                if let Some(Operand::Value(p)) = i.get_operand(0) {
                    return ptr_base_off(p);
                }
            }
            _ => {}
        }
    }
    (fmt(a), 0)
}

/// The constant of a `U32Val` (`from_payload(n << 32 | 4)`), if `v` is one.
fn u32_val(v: BasicValueEnum) -> Option<u64> {
    u32_val_in(v, &|x| x)
}

/// `u32_val`, resolving phis on the way with `pick` (e.g. to one switch case).
fn u32_val_in<'c>(v: BasicValueEnum<'c>, pick: &dyn Fn(BasicValueEnum<'c>) -> BasicValueEnum<'c>) -> Option<u64> {
    let i = as_instr(v).filter(|i| callee_has(*i, "from_payload"))?;
    match i.get_operand(0).and_then(|o| o.value()).map(pick) {
        Some(BasicValueEnum::IntValue(c)) => c.get_zero_extended_constant().map(|k| k >> 32),
        _ => None,
    }
}

/// The linear-memory address a `U32Val` pointer argument carries
/// (`from_payload(addr << 32 | 4)`), as base + offset.
fn val_addr(v: BasicValueEnum) -> Option<(String, i64)> {
    val_addr_in(v, &|x| x)
}

/// `val_addr`, resolving phis on the way with `pick`.
fn val_addr_in<'c>(v: BasicValueEnum<'c>, pick: &dyn Fn(BasicValueEnum<'c>) -> BasicValueEnum<'c>) -> Option<(String, i64)> {
    let i = as_instr(v).filter(|i| callee_has(*i, "from_payload"))?;
    let Some(Operand::Value(x)) = i.get_operand(0) else { return None };
    let or = as_instr(pick(x)).filter(|o| o.get_opcode() == InstructionOpcode::Or)?;
    let (Some(Operand::Value(sh)), Some(Operand::Value(BasicValueEnum::IntValue(tag)))) = (or.get_operand(0), or.get_operand(1)) else { return None };
    let sh = as_instr(sh).filter(|s| s.get_opcode() == InstructionOpcode::Shl)?;
    let (Some(Operand::Value(a)), Some(Operand::Value(BasicValueEnum::IntValue(k)))) = (sh.get_operand(0), sh.get_operand(1)) else { return None };
    (tag.get_zero_extended_constant() == Some(4) && k.get_zero_extended_constant() == Some(32)).then(|| addr_base_off(pick(a)))
}

/// A host call that writes guest linear memory (`map/vec_unpack_to_linear_memory`,
/// `*_copy_to_linear_memory`): Some(Some((dest, bytes))), or Some(None) when the
/// destination can't be decoded (it may write anywhere). None: not such a call.
#[allow(clippy::type_complexity)]
fn linmem_dest(i: InstructionValue) -> Option<Option<((String, i64), i64)>> {
    let n = callee_name(i)?;
    let (pos, len, unit) = if n.contains("map_unpack_to_linear_memory") {
        (2, 3, 8)
    } else if n.contains("vec_unpack_to_linear_memory") {
        (1, 2, 8)
    } else if n.contains("copy_to_linear_memory") {
        (2, 3, 1)
    } else {
        return None;
    };
    let op = |k: u32| match i.get_operand(k) { Some(Operand::Value(x)) => Some(x), _ => None };
    Some(match (op(pos).and_then(val_addr), op(len).and_then(u32_val)) {
        (Some(a), Some(l)) => Some((a, l as i64 * unit)),
        _ => None,
    })
}

/// The `#[contracttype]` structs of the contract spec: name -> (field, type).
fn spec_structs(module: &inkwell::module::Module) -> HashMap<String, Vec<(String, String)>> {
    let mut out = HashMap::new();
    for node in module.get_global_metadata("soroban.spec") {
        for v in node.get_node_values().unwrap_or_default() {
            let BasicMetadataValueEnum::MetadataValue(mv) = v else { continue };
            let Some(raw) = mv.get_string_value() else { continue };
            let line = String::from_utf8_lossy(raw).into_owned();
            let Some(rest) = line.strip_prefix("struct ") else { continue };
            let Some((name, body)) = rest.split_once('{') else { continue };
            let fields = body.trim_end_matches('}').split(',').filter_map(|f| {
                let (n, t) = f.split_once(':')?;
                Some((n.trim().to_string(), t.trim().to_string()))
            });
            out.insert(name.trim().to_string(), fields.collect());
        }
    }
    out
}

/// The Val tags a value of spec type `ty` can carry (None: not tracked).
fn val_tags(ty: &str, structs: &HashMap<String, Vec<(String, String)>>) -> Option<Vec<i64>> {
    Some(match ty {
        "bool" => vec![0, 1],
        "u32" => vec![4],
        "i32" => vec![5],
        "u64" => vec![6, 64],
        "i64" => vec![7, 65],
        "u128" => vec![10, 68],
        "i128" => vec![11, 69],
        "Address" => vec![77],
        "MuxedAddress" => vec![77, 78],
        "String" => vec![73],
        "Bytes" => vec![72],
        t if t.starts_with("BytesN<") => vec![72],
        t if t.starts_with("Vec<") => vec![75],
        t if t.starts_with("Map<") => vec![76],
        t if structs.contains_key(t) => vec![76],
        _ => return None,
    })
}

/// `tag(x) = k` (`ICmp_EQ(And(x, 255), k)`): `(x, k)`.
fn tag_test(c: &Expr) -> Option<(Expr, i64)> {
    match c {
        Expr::Opaque(l, v) if l == "ICmp_EQ" && v.len() == 2 => match (&v[0], &v[1]) {
            (Expr::Opaque(a, ax), Expr::Const(k)) if a == "And" && ax.len() == 2 && ax[1] == Expr::Const(255) => Some((ax[0].clone(), *k)),
            _ => None,
        },
        _ => None,
    }
}

/// In a successful run every argument has its spec type (the SDK's entrypoint
/// wrapper traps when one fails to convert), and so do the fields of a struct
/// argument: their Val-tag tests are decided. Folds the decided booleans.
fn assume_arg_types(e: &Expr, args: &Args, structs: &HashMap<String, Vec<(String, String)>>) -> Expr {
    fn excludes_all(xs: &[Expr], args: &Args, structs: &HashMap<String, Vec<(String, String)>>) -> bool {
        let mut ne: Vec<(&Expr, i64)> = vec![];
        for x in xs {
            if let Expr::Opaque(l, v) = x {
                if let (true, [Expr::Opaque(a, ax), Expr::Const(k)]) = (l == "ICmp_NE", v.as_slice()) {
                    if a == "And" && ax.len() == 2 && ax[1] == Expr::Const(255) {
                        ne.push((&ax[0], *k));
                    }
                }
            }
        }
        ne.iter().any(|(x, _)| {
            ty(x, args, structs).and_then(|t| val_tags(&t, structs))
                .is_some_and(|tags| tags.iter().all(|t| ne.iter().any(|(y, k)| y == x && k == t)))
        })
    }
    fn ty(e: &Expr, args: &Args, structs: &HashMap<String, Vec<(String, String)>>) -> Option<String> {
        match e {
            Expr::Param(i) => args.get(*i).map(|a| a.2.clone()).filter(|t| !t.is_empty()),
            Expr::Opaque(l, xs) if l.starts_with("@field:") && xs.len() == 1 => {
                let s = ty(&xs[0], args, structs)?;
                structs.get(&s)?.iter().find(|(f, _)| *f == l["@field:".len()..]).map(|(_, t)| t.clone())
            }
            _ => None,
        }
    }
    let t = Expr::Opaque("@true".into(), vec![]);
    let f = Expr::Opaque("@false".into(), vec![]);
    let is = |x: &Expr, n: &str| matches!(x, Expr::Opaque(l, v) if l == n && v.is_empty());
    let boolish = |x: &Expr| matches!(x, Expr::Opaque(l, _) if l.starts_with("ICmp_") || ["@true", "@false", "@not", "@and", "@or"].contains(&l.as_str()));
    let rec = |x: &Expr| assume_arg_types(x, args, structs);
    match e {
        // a u32 argument's Val (`v·2³² + 4`) masked by `m·2³² + 4` (m = 2^k − 1,
        // the compiler knowing `v < 2^k`): the value `v % 2^k`.
        Expr::Opaque(l, xs) if l == "And" && xs.len() == 2
            && matches!(&xs[0], Expr::Param(i) if args.get(*i).is_some_and(|a| a.2 == "u32"))
            && matches!(xs[1], Expr::Const(c) if c & 0xffff_ffff == 4 && ((c >> 32) + 1).count_ones() == 1 && c >> 32 > 0) =>
        {
            let Expr::Const(c) = xs[1] else { unreachable!() };
            Expr::Bin('%', Box::new(xs[0].clone()), Box::new(Expr::Const((c >> 32) + 1)))
        }
        // an if-chain over an argument's Val tag that tests every tag its type
        // allows: the final `else` can't happen.
        Expr::Opaque(l, xs) if l == "Select" && xs.len() == 3 && tag_test(&xs[0]).is_some() => {
            fn chain(e: &Expr, x: &Expr, left: &[i64]) -> Expr {
                if let Expr::Opaque(l, xs) = e {
                    if l == "Select" && xs.len() == 3 {
                        if let Some((y, k)) = tag_test(&xs[0]) {
                            if y == *x && left.contains(&k) {
                                let rest: Vec<i64> = left.iter().copied().filter(|t| *t != k).collect();
                                if rest.is_empty() {
                                    return xs[1].clone();
                                }
                                return Expr::Opaque(l.clone(), vec![xs[0].clone(), xs[1].clone(), chain(&xs[2], x, &rest)]);
                            }
                        }
                    }
                }
                e.clone()
            }
            let (x, _) = tag_test(&xs[0]).unwrap();
            let e2 = match ty(&x, args, structs).and_then(|t| val_tags(&t, structs)) {
                Some(tags) => chain(e, &x, &tags),
                None => e.clone(),
            };
            match &e2 {
                Expr::Opaque(l2, ys) if l2 == "Select" => Expr::Opaque(l2.clone(), ys.iter().map(rec).collect()),
                other => rec(other),
            }
        }
        Expr::Opaque(l, xs) if (l == "ICmp_EQ" || l == "ICmp_NE") && xs.len() == 2 => {
            if let (Expr::Opaque(a, ax), Expr::Const(k)) = (&xs[0], &xs[1]) {
                if a == "And" && ax.len() == 2 && ax[1] == Expr::Const(255) {
                    if let Some(tags) = ty(&ax[0], args, structs).and_then(|ty| val_tags(&ty, structs)) {
                        let eq = if tags == [*k] { Some(true) } else if !tags.contains(k) { Some(false) } else { None };
                        if let Some(eq) = eq {
                            return if eq == (l == "ICmp_EQ") { t } else { f };
                        }
                    }
                }
            }
            Expr::Opaque(l.clone(), xs.iter().map(rec).collect())
        }
        Expr::Opaque(l, xs) => {
            let xs: Vec<Expr> = xs.iter().map(rec).collect();
            match (l.as_str(), xs.as_slice()) {
                ("@not", [x]) if is(x, "@true") => f,
                ("@not", [x]) if is(x, "@false") => t,
                ("@and", _) if xs.iter().any(|x| is(x, "@false")) => f,
                // `tag ≠ a ∧ tag ≠ b ∧ …` ruling out every tag the type allows.
                ("@and", _) if excludes_all(&xs, args, structs) => f,
                ("@or", _) if xs.iter().any(|x| is(x, "@true")) => t,
                ("@and" | "@or", _) => {
                    let unit = if l == "@and" { "@true" } else { "@false" };
                    let rest: Vec<Expr> = xs.iter().filter(|x| !is(x, unit)).cloned().collect();
                    match rest.len() {
                        0 => Expr::Opaque(unit.into(), vec![]),
                        1 => rest.into_iter().next().unwrap(),
                        _ => Expr::Opaque(l.clone(), rest),
                    }
                }
                // i1 bitwise and/or of decided tests.
                ("And", [a, b]) if boolish(a) && boolish(b) && (is(a, "@false") || is(b, "@false")) => f,
                ("And", [a, b]) if boolish(a) && boolish(b) && is(a, "@true") => b.clone(),
                ("And", [a, b]) if boolish(a) && boolish(b) && is(b, "@true") => a.clone(),
                ("Or", [a, b]) if boolish(a) && boolish(b) && (is(a, "@true") || is(b, "@true")) => t,
                ("Or", [a, b]) if boolish(a) && boolish(b) && is(a, "@false") => b.clone(),
                ("Or", [a, b]) if boolish(a) && boolish(b) && is(b, "@false") => a.clone(),
                ("Select", [c, a, _]) if is(c, "@true") => a.clone(),
                ("Select", [c, _, b]) if is(c, "@false") => b.clone(),
                _ => Expr::Opaque(l.clone(), xs),
            }
        }
        Expr::Bin(o, a, b) => Expr::Bin(*o, Box::new(rec(a)), Box::new(rec(b))),
        Expr::VecGet(a, b) => Expr::VecGet(Box::new(rec(a)), Box::new(rec(b))),
        other => other.clone(),
    }
}

thread_local! {
    /// Facts every successful run of the entrypoint satisfies: `(e, is_eq, k)`
    /// for `e = k` / `e ≠ k`, from the unconditional panic guards.
    static FACTS: std::cell::RefCell<Vec<(usize, (Expr, bool, i64))>> = const { std::cell::RefCell::new(vec![]) };
    /// The guard block being stated (its own fact must not simplify it away).
    static EXCLUDE: std::cell::Cell<Option<usize>> = const { std::cell::Cell::new(None) };
}

/// Simplify `e` under the entrypoint's FACTS. A value fact `X = k` / `X ≠ k`
/// decides tests on X and pins X; `X ≠ k` for an if-chain `Select(c, k, Y)`
/// also says `c` is false (and `Y ≠ k`) — e.g. a decode helper's error result,
/// which the caller panics on, rules out the error paths. Boolean facts are
/// split (`¬a`, `a ∧ b`) and the whole set closed under simplification.
fn entry_fact_list() -> Vec<(Expr, bool, i64)> {
    let ex = EXCLUDE.with(|x| x.get());
    FACTS.with(|f| f.borrow().iter().filter(|(b, _)| Some(*b) != ex).map(|(_, x)| x.clone()).collect())
}

fn apply_facts(e: &Expr) -> Expr {
    let raw = entry_fact_list();
    simplify_under(e, &raw, true)
}

/// `e` simplified under `raw` facts; `by_state` equates reads of a key at
/// points that see the same state (entry level), else reads match exactly.
fn simplify_under(e: &Expr, raw: &[(Expr, bool, i64)], by_state: bool) -> Expr {
    if raw.is_empty() {
        return e.clone();
    }
    BY_STATE.with(|b| b.set(by_state));
    let facts = close_facts(raw);
    let mut cur = e.clone();
    for _ in 0..4 {
        let next = fold_bools(&facts_go(&cur, &facts));
        if next == cur {
            break;
        }
        cur = next;
    }
    cur
}

/// `e` assuming the conditions `cs` (and the entrypoint's facts).
fn assuming(e: &Expr, cs: &[(Expr, bool)]) -> Expr {
    if cs.is_empty() {
        return e.clone();
    }
    let raw = entry_fact_list();
    let facts = close_facts_with(&raw, cs);
    let mut cur = e.clone();
    for _ in 0..4 {
        let next = fold_bools(&facts_go(&cur, &facts));
        if next == cur {
            break;
        }
        cur = next;
    }
    cur
}

/// Contextual simplification: in `Select(c, a, b)` the arm `a` assumes `c` and
/// `b` assumes `¬c`; each conjunct of an `@and` assumes the ones before it.
fn ctx_simplify(e: &Expr) -> Expr {
    fn go(e: &Expr, cs: &mut Vec<(Expr, bool)>, budget: &mut usize) -> Expr {
        if *budget == 0 {
            return e.clone();
        }
        *budget -= 1;
        match e {
            Expr::Opaque(l, v) if l == "Select" && v.len() == 3 => {
                let c = go(&v[0], cs, budget);
                let c = assuming(&c, cs);
                cs.push((c.clone(), true));
                let a = assuming(&go(&v[1], cs, budget), cs);
                cs.pop();
                cs.push((c.clone(), false));
                let b = assuming(&go(&v[2], cs, budget), cs);
                cs.pop();
                fold_bools(&Expr::Opaque("Select".into(), vec![c, a, b]))
            }
            Expr::Opaque(l, v) if l == "@and" => {
                let n = cs.len();
                let mut out = vec![];
                for x in v {
                    let x = assuming(&go(x, cs, budget), cs);
                    cs.push((x.clone(), true));
                    out.push(x);
                }
                cs.truncate(n);
                fold_bools(&Expr::Opaque("@and".into(), out))
            }
            Expr::Opaque(l, v) => Expr::Opaque(l.clone(), v.iter().map(|x| go(x, cs, budget)).collect()),
            Expr::Bin(o, a, b) => Expr::Bin(*o, Box::new(go(a, cs, budget)), Box::new(go(b, cs, budget))),
            Expr::VecGet(a, b) => Expr::VecGet(Box::new(go(a, cs, budget)), Box::new(go(b, cs, budget))),
            e => e.clone(),
        }
    }
    if !has_label(e, "Select") && !has_label(e, "@and") {
        return e.clone();
    }
    go(e, &mut vec![], &mut 400)
}

/// Facts as (normalized expr, value): a boolean fact `(c, 1|0)` or a value fact.
struct Facts {
    vals: Vec<(Expr, bool, i64)>, // (x, is_eq, k): x = k / x ≠ k
    bools: Vec<(Expr, bool)>,      // (c, holds)
}

thread_local! {
    static BY_STATE: std::cell::Cell<bool> = const { std::cell::Cell::new(true) };
}

/// Reads of one key at points that see the same state are the same value.
fn norm_at(e: &Expr) -> Expr {
    if !BY_STATE.with(|b| b.get()) {
        return e.clone();
    }
    let st = |id: usize| {
        let at = path_of(id);
        TX_SITES.with(|t| t.borrow().iter().filter(|&&s| path_of(s) < at).count()) as i64
    };
    match e {
        Expr::Slot(n, t) if *t > 0 => Expr::Slot(n.clone(), st(*t - 1) as usize + 1),
        Expr::Opaque(l, xs) if l == "@at" => match xs.first() {
            Some(Expr::Const(id)) => Expr::Opaque("@at".into(), vec![Expr::Const(st(*id as usize))]),
            _ => e.clone(),
        },
        Expr::Opaque(l, xs) => Expr::Opaque(l.clone(), xs.iter().map(norm_at).collect()),
        Expr::Bin(o, a, b) => Expr::Bin(*o, Box::new(norm_at(a)), Box::new(norm_at(b))),
        Expr::VecGet(a, b) => Expr::VecGet(Box::new(norm_at(a)), Box::new(norm_at(b))),
        e => e.clone(),
    }
}

fn close_facts(raw: &[(Expr, bool, i64)]) -> Facts {
    close_facts_with(raw, &[])
}

fn close_facts_with(raw: &[(Expr, bool, i64)], bools: &[(Expr, bool)]) -> Facts {
    let mut fs = Facts { vals: vec![], bools: vec![] };
    let mut todo: Vec<(Expr, bool, i64)> = raw.iter().map(|(e, q, k)| (norm_at(e), *q, *k)).collect();
    let mut btodo: Vec<(Expr, bool)> = bools.iter().map(|(e, h)| (norm_at(e), *h)).collect();
    for _round in 0..8 {
        let mut changed = false;
        // revisit what is known with what was learnt since.
        btodo.extend(std::mem::take(&mut fs.bools));
        todo.extend(std::mem::take(&mut fs.vals));
        let before = (todo.clone(), btodo.clone());
        for (x, q, k) in std::mem::take(&mut todo) {
            let x = fold_bools(&facts_go(&x, &fs));
            if !fs.vals.contains(&(x.clone(), q, k)) {
                // an if-chain known = k: arms that are other constants are not taken.
                if q {
                    let mut cur = &x;
                    while let Expr::Opaque(l, v) = cur {
                        if l != "Select" || v.len() != 3 {
                            break;
                        }
                        let other = |y: &Expr| matches!(y, Expr::Const(j) if *j != k);
                        if other(&v[1]) {
                            btodo.push((v[0].clone(), false));
                            cur = &v[2];
                        } else if other(&v[2]) {
                            btodo.push((v[0].clone(), true));
                            cur = &v[1];
                        } else {
                            break;
                        }
                    }
                }
                // an if-chain known ≠ k: the conditions of its k arms are false.
                if !q {
                    let mut cur = &x;
                    while let Expr::Opaque(l, v) = cur {
                        if l != "Select" || v.len() != 3 {
                            break;
                        }
                        if v[1] == Expr::Const(k) {
                            btodo.push((v[0].clone(), false));
                            cur = &v[2];
                        } else if v[2] == Expr::Const(k) {
                            btodo.push((v[0].clone(), true));
                            cur = &v[1];
                        } else {
                            break;
                        }
                    }
                }
                fs.vals.push((x, q, k));
                changed = true;
            }
        }
        while let Some((c, holds)) = btodo.pop() {
            let c = fold_bools(&facts_go(&c, &fs));
            match (&c, holds) {
                (Expr::Opaque(l, v), _) if l == "@not" && v.len() == 1 => btodo.push((v[0].clone(), !holds)),
                (Expr::Opaque(l, v), true) if l == "@and" => btodo.extend(v.iter().map(|x| (x.clone(), true))),
                (Expr::Opaque(l, v), false) if l == "@or" => btodo.extend(v.iter().map(|x| (x.clone(), false))),
                (Expr::Opaque(l, v), _) if (l == "ICmp_EQ" || l == "ICmp_NE") && v.len() == 2 && matches!(v[1], Expr::Const(_)) => {
                    let Expr::Const(k) = v[1] else { unreachable!() };
                    todo.push((v[0].clone(), (l == "ICmp_EQ") == holds, k));
                }
                (Expr::Opaque(l, v), _) if (l == "@true" || l == "@false") && v.is_empty() => {}
                _ => {
                    // also its negation, pushed inwards (`¬(a ∨ b)` is `¬a ∧ ¬b`).
                    for f in [(c.clone(), holds), (negate_bool(&c), !holds)] {
                        if !fs.bools.contains(&f) {
                            fs.bools.push(f);
                            changed = true;
                        }
                    }
                }
            }
        }
        let _ = changed;
        if todo.is_empty() && (fs.vals.clone(), fs.bools.clone()) == before {
            break;
        }
    }
    fs
}

fn facts_go(e: &Expr, fs: &Facts) -> Expr {
    fn prune(e: &Expr, k: i64) -> Expr {
        match e {
            Expr::Opaque(l, v) if l == "Select" && v.len() == 3 => {
                let (a, b) = (prune(&v[1], k), prune(&v[2], k));
                if a == Expr::Const(k) { b } else if b == Expr::Const(k) { a } else { Expr::Opaque(l.clone(), vec![v[0].clone(), a, b]) }
            }
            e => e.clone(),
        }
    }
    let e = match e {
        Expr::Opaque(l, xs) => Expr::Opaque(l.clone(), xs.iter().map(|x| facts_go(x, fs)).collect()),
        Expr::Bin(o, a, b) => Expr::Bin(*o, Box::new(facts_go(a, fs)), Box::new(facts_go(b, fs))),
        Expr::VecGet(a, b) => Expr::VecGet(Box::new(facts_go(a, fs)), Box::new(facts_go(b, fs))),
        e => e.clone(),
    };
    let ne = norm_at(&e);
    for (c, holds) in &fs.bools {
        if *c == ne {
            return Expr::Opaque(if *holds { "@true" } else { "@false" }.into(), vec![]);
        }
    }
    if let Expr::Opaque(l, xs) = &e {
        if (l == "ICmp_EQ" || l == "ICmp_NE") && xs.len() == 2 {
            if let Expr::Const(k) = xs[1] {
                let x = norm_at(&xs[0]);
                for (fe, is_eq, fk) in &fs.vals {
                    if *fe == x && (*is_eq || *fk == k) {
                        let eq = if *is_eq { *fk == k } else { false };
                        return Expr::Opaque(if eq == (l == "ICmp_EQ") { "@true" } else { "@false" }.into(), vec![]);
                    }
                }
            }
        }
    }
    for (fe, is_eq, k) in &fs.vals {
        if *fe == ne {
            return if *is_eq { Expr::Const(*k) } else { prune(&e, *k) };
        }
    }
    e
}

/// `¬e` with the negation pushed through `@and` / `@or` / `@not` to the
/// comparisons (which flip).
fn negate_bool(e: &Expr) -> Expr {
    match e {
        Expr::Opaque(l, v) if l == "@not" && v.len() == 1 => v[0].clone(),
        Expr::Opaque(l, v) if l == "@and" || l == "@or" => {
            Expr::Opaque(if l == "@and" { "@or" } else { "@and" }.into(), v.iter().map(negate_bool).collect())
        }
        Expr::Opaque(l, v) if l.starts_with("ICmp_") && v.len() == 2 => {
            let flip = match &l["ICmp_".len()..] {
                "EQ" => "NE", "NE" => "EQ", "SLT" => "SGE", "SGE" => "SLT", "SGT" => "SLE", "SLE" => "SGT",
                "ULT" => "UGE", "UGE" => "ULT", "UGT" => "ULE", "ULE" => "UGT", _ => return Expr::Opaque("@not".into(), vec![e.clone()]),
            };
            Expr::Opaque(format!("ICmp_{flip}"), v.clone())
        }
        Expr::Opaque(l, v) if l == "@true" && v.is_empty() => Expr::Opaque("@false".into(), vec![]),
        Expr::Opaque(l, v) if l == "@false" && v.is_empty() => Expr::Opaque("@true".into(), vec![]),
        e => Expr::Opaque("@not".into(), vec![e.clone()]),
    }
}

/// An if-chain whose leaves are all constants.
fn const_chain(e: &Expr) -> bool {
    match e {
        Expr::Const(_) => true,
        Expr::Opaque(l, v) if l == "Select" && v.len() == 3 => const_chain(&v[1]) && const_chain(&v[2]),
        _ => false,
    }
}

/// Fold decided booleans: `@and`/`@or`/`@not`, i1 `And`/`Or`, `Select` on a
/// decided condition.
fn fold_bools(e: &Expr) -> Expr {
    let t = Expr::Opaque("@true".into(), vec![]);
    let f = Expr::Opaque("@false".into(), vec![]);
    let is = |x: &Expr, n: &str| matches!(x, Expr::Opaque(l, v) if l == n && v.is_empty());
    let boolish = |x: &Expr| matches!(x, Expr::Opaque(l, _) if l.starts_with("ICmp_") || ["@true", "@false", "@not", "@and", "@or"].contains(&l.as_str()));
    match e {
        Expr::Opaque(l, xs) => {
            let xs: Vec<Expr> = xs.iter().map(fold_bools).collect();
            match (l.as_str(), xs.as_slice()) {
                ("@not", [x]) if is(x, "@true") => f,
                ("@not", [x]) if is(x, "@false") => t,
                ("@and", _) if xs.iter().any(|x| is(x, "@false")) => f,
                ("@or", _) if xs.iter().any(|x| is(x, "@true")) => t,
                ("@and" | "@or", _) => {
                    let unit = if l == "@and" { "@true" } else { "@false" };
                    let rest: Vec<Expr> = xs.iter().filter(|x| !is(x, unit)).cloned().collect();
                    match rest.len() {
                        0 => Expr::Opaque(unit.into(), vec![]),
                        1 => rest.into_iter().next().unwrap(),
                        _ => Expr::Opaque(l.clone(), rest),
                    }
                }
                ("And", [a, b]) if boolish(a) && boolish(b) && (is(a, "@false") || is(b, "@false")) => f,
                ("And", [a, b]) if boolish(a) && boolish(b) && is(a, "@true") => b.clone(),
                ("And", [a, b]) if boolish(a) && boolish(b) && is(b, "@true") => a.clone(),
                ("Or", [a, b]) if boolish(a) && boolish(b) && (is(a, "@true") || is(b, "@true")) => t,
                ("Or", [a, b]) if boolish(a) && boolish(b) && is(a, "@false") => b.clone(),
                ("Or", [a, b]) if boolish(a) && boolish(b) && is(b, "@false") => a.clone(),
                ("Select", [c, a, _]) if is(c, "@true") => a.clone(),
                ("Select", [c, _, b]) if is(c, "@false") => b.clone(),
                ("Select", [_, a, b]) if a == b => a.clone(),
                // a mask of an if-chain of constants: per arm.
                ("And", [Expr::Opaque(sl, v), Expr::Const(k)]) if sl == "Select" && v.len() == 3 && const_chain(&xs[0]) => {
                    let m = |x: &Expr| fold_bools(&Expr::Opaque("And".into(), vec![x.clone(), Expr::Const(*k)]));
                    Expr::Opaque("Select".into(), vec![v[0].clone(), m(&v[1]), m(&v[2])])
                }
                ("And", [Expr::Const(a), Expr::Const(b)]) => Expr::Const(a & b),
                (op, [Expr::Const(a), Expr::Const(b)]) if op.starts_with("ICmp_") => {
                    let (a, b) = (*a, *b);
                    let r = match &op["ICmp_".len()..] {
                        "EQ" => Some(a == b), "NE" => Some(a != b),
                        "SLT" => Some(a < b), "SLE" => Some(a <= b), "SGT" => Some(a > b), "SGE" => Some(a >= b),
                        "ULT" => Some((a as u64) < (b as u64)), "ULE" => Some((a as u64) <= (b as u64)),
                        "UGT" => Some((a as u64) > (b as u64)), "UGE" => Some((a as u64) >= (b as u64)),
                        _ => None,
                    };
                    match r { Some(true) => t, Some(false) => f, None => Expr::Opaque(l.clone(), xs) }
                }
                _ => Expr::Opaque(l.clone(), xs),
            }
        }
        Expr::Bin(o, a, b) => Expr::Bin(*o, Box::new(fold_bools(a)), Box::new(fold_bools(b))),
        Expr::VecGet(a, b) => Expr::VecGet(Box::new(fold_bools(a)), Box::new(fold_bools(b))),
        other => other.clone(),
    }
}

/// The facts of entrypoint `f`: the `=` / `≠ const` tests of the panic guards
/// that every successful run passes (their branch is reached unconditionally).
fn entry_facts<'c>(f: FunctionValue<'c>, module: &inkwell::module::Module<'c>) -> Vec<(usize, (Expr, bool, i64))> {
    guard_facts_blocks(f, module, true, true)
}

/// The raw (unnamed) facts of `f` that hold at the end of block `b`: the
/// panic guards whose branch dominates `b` (every path to `b` passed them).
fn facts_at<'c>(f: FunctionValue<'c>, cfg: &Cfg<'c>, b: usize, module: &inkwell::module::Module<'c>) -> Vec<(Expr, bool, i64)> {
    use inkwell::values::AsValueRef;
    thread_local! {
        static MEMO: std::cell::RefCell<HashMap<usize, (Vec<HashSet<usize>>, Vec<(usize, (Expr, bool, i64))>)>> = std::cell::RefCell::new(HashMap::new());
    }
    let key = f.as_value_ref() as usize;
    if MEMO.with(|m| !m.borrow().contains_key(&key)) {
        MEMO.with(|m| m.borrow_mut().insert(key, (vec![], vec![]))); // recursion guard
        let r = (dominators(cfg), guard_facts_blocks(f, module, false, false));
        MEMO.with(|m| m.borrow_mut().insert(key, r));
    }
    MEMO.with(|m| {
        let m = m.borrow();
        let (dom, gf) = &m[&key];
        gf.iter().filter(|(g, _)| dom.get(b).is_some_and(|d| d.contains(g))).map(|(_, x)| x.clone()).collect()
    })
}

/// Each block's dominators (blocks on every path from the entry to it).
fn dominators(cfg: &Cfg) -> Vec<HashSet<usize>> {
    let n = cfg.succ.len();
    let all: HashSet<usize> = (0..n).collect();
    let preds: Vec<Vec<usize>> = (0..n).map(|b| (0..n).filter(|&u| cfg.succ[u].contains(&b)).collect()).collect();
    let mut dom: Vec<HashSet<usize>> = (0..n).map(|b| if b == 0 { [0].into() } else { all.clone() }).collect();
    loop {
        let mut changed = false;
        for b in 1..n {
            let mut d: HashSet<usize> = preds[b].iter().map(|&p| dom[p].clone()).reduce(|a, x| &a & &x).unwrap_or_default();
            d.insert(b);
            if d != dom[b] {
                dom[b] = d;
                changed = true;
            }
        }
        if !changed {
            return dom;
        }
    }
}

/// The `=` / `≠ const` tests of `f`'s panic guards, with the guard's block;
/// `unconditional`: only guards on every successful path.
fn guard_facts_blocks<'c>(f: FunctionValue<'c>, module: &inkwell::module::Module<'c>, named: bool, unconditional: bool) -> Vec<(usize, (Expr, bool, i64))> {    let cfg = Cfg::build(f);
    let args = arg_table(f);
    let structs = spec_structs(module);
    let kbf = datakey_builder(module);
    let usage = kbf.map(kb_field_usage);
    let kb = kbf.zip(usage.as_ref());
    let segs = rodata_segs(module);
    let mut out = vec![];
    with_rich(|| {
        let mut memo = HashMap::new();
        for (bi, blk) in cfg.blocks.iter().enumerate() {
            let Some(term) = blk.get_terminator().filter(|t| t.get_opcode() == InstructionOpcode::Br) else { continue };
            let Some(Operand::Value(cond)) = term.get_operand(0) else { continue };
            if !is_bool(cond) || cfg.succ[bi].len() != 2 {
                continue;
            }
            let (ft, tt) = (forces_trap(cfg.blocks[cfg.succ[bi][0]], 6), forces_trap(cfg.blocks[cfg.succ[bi][1]], 6));
            let negate = match (tt, ft) { (true, false) => true, (false, true) => false, _ => continue };
            if unconditional && reach_dnf(&cfg, bi, &mut HashMap::new(), &mut HashSet::new()).as_deref() != Some(&[PathConj::new()][..]) {
                continue; // not on every successful path
            }
            let mut leaves = vec![];
            bool_split(cond, negate, 8, &mut leaves);
            for leaf in leaves {
                let Some((op0, l, r)) = gate_vals(leaf) else { continue };
                let op = if negate { op0.negate() } else { op0 };
                let is_eq = match op { RelOp::Eq => true, RelOp::Ne => false, _ => continue };
                let mut ev = |x| {
                    let e = simplify(value_expr(x, f, module, &mut memo, 40));
                    if named { assume_arg_types(&name_slots(&e, module, kb, &segs), &args, &structs) } else { e }
                };
                let (le, re) = (ev(l), ev(r));
                match (le, re) {
                    (e, Expr::Const(k)) | (Expr::Const(k), e) if !matches!(e, Expr::Const(_)) => out.push((bi, (e, is_eq, k))),
                    _ => {}
                }
            }
        }
    });
    out
}

/// The field names (sorted, as Soroban stores them) of the `#[contracttype]`
/// struct whose key table is at `pos` — the front end's `soroban.keys` metadata.
fn struct_keys(module: &inkwell::module::Module, pos: u64) -> Option<Vec<String>> {
    for node in module.get_global_metadata("soroban.keys") {
        for v in node.get_node_values()? {
            let BasicMetadataValueEnum::MetadataValue(mv) = v else { continue };
            let s = String::from_utf8_lossy(mv.get_string_value()?).into_owned();
            let mut it = s.split(' ');
            if it.next().and_then(|p| p.parse::<u64>().ok()) == Some(pos) {
                return Some(it.map(String::from).collect());
            }
        }
    }
    None
}

/// Does this pointer bottom out at an `alloca` (through geps)? Only then can we
/// compare it precisely; anything else (inttoptr of an i64 address, unknown) is
/// opaque and a store through it may-aliases every slot.
fn ptr_is_clean(p: BasicValueEnum) -> bool {
    match as_instr(p) {
        Some(i) if i.get_opcode() == InstructionOpcode::Alloca => true,
        Some(i) if i.get_opcode() == InstructionOpcode::GetElementPtr => {
            matches!(i.get_operand(0), Some(Operand::Value(b)) if ptr_is_clean(b))
        }
        Some(i) if i.get_opcode() == InstructionOpcode::IntToPtr => {
            matches!(i.get_operand(0), Some(Operand::Value(a)) if addr_is_clean(a))
        }
        _ => false,
    }
}

/// An i64 address is clean iff it is `ptrtoint(clean ptr)` plus constant offsets.
fn addr_is_clean(a: BasicValueEnum) -> bool {
    match as_instr(a) {
        Some(i) if i.get_opcode() == InstructionOpcode::PtrToInt => {
            matches!(i.get_operand(0), Some(Operand::Value(p)) if ptr_is_clean(p))
        }
        Some(i) if matches!(i.get_opcode(), InstructionOpcode::ZExt | InstructionOpcode::SExt | InstructionOpcode::Trunc) => {
            matches!(i.get_operand(0), Some(Operand::Value(x)) if addr_is_clean(x))
        }
        Some(i) if i.get_opcode() == InstructionOpcode::Add => {
            // base + constant only (a dynamic offset is not clean)
            matches!(i.get_operand(1), Some(Operand::Value(BasicValueEnum::IntValue(c))) if c.get_sign_extended_constant().is_some())
                && matches!(i.get_operand(0), Some(Operand::Value(x)) if addr_is_clean(x))
        }
        _ => false,
    }
}

/// The state of the slot after scanning block `b` up to `stop`: None = untouched
/// here (look at predecessors); Some(None) = clobbered/ambiguous (a may-alias
/// store); Some(Some v) = cleanly defined to v. A store through an un-analyzable
/// pointer KILLS the definition — this is what keeps forwarding sound.
fn block_rd<'c>(b: BasicBlock<'c>, stop: Option<InstructionValue<'c>>, ptr: BasicValueEnum<'c>, target: &(String, i64)) -> Option<Option<BasicValueEnum<'c>>> {
    let mut cur: Option<Option<BasicValueEnum<'c>>> = None;
    let mut it = b.get_first_instruction();
    while let Some(i) = it {
        if Some(i) == stop {
            break;
        }
        if i.get_opcode() == InstructionOpcode::Store {
            if let (Some(Operand::Value(sv)), Some(Operand::Value(sp))) = (i.get_operand(0), i.get_operand(1)) {
                if sp == ptr {
                    cur = Some(Some(sv));
                } else if ptr_is_clean(sp) {
                    if ptr_base_off(sp) == *target {
                        cur = Some(Some(sv)); // same clean location
                    }
                    // else: a provably different alloca location — no effect.
                } else {
                    cur = Some(None); // may-alias store -> clobber (sound)
                }
            } else {
                cur = Some(None);
            }
        }
        // a call handed a pointer into the same frame region may write the slot
        // through it (i128 results / getters return via out-pointer). Clobber iff
        // the callee writes at our offset through that pointer (or we can't tell).
        if let Some(d) = linmem_dest(i) {
            match d {
                Some(((b, o), len)) if b == target.0 && o < target.1 + 8 && target.1 < o + len => cur = Some(None),
                Some(_) => {}
                None => cur = Some(None),
            }
        } else if i.get_opcode() == InstructionOpcode::Call {
            let callee = inkwell::values::CallSiteValue::try_from(i).ok().and_then(|cs| cs.get_called_fn_value());
            let nargs = i.get_num_operands().saturating_sub(1);
            for k in 0..nargs {
                if let Some(Operand::Value(a)) = i.get_operand(k) {
                    let (base, o) = if a.is_pointer_value() { ptr_base_off(a) } else { addr_base_off(a) };
                    if base != target.0 || o > target.1 {
                        continue;
                    }
                    let delta = target.1 - o;
                    let writes = callee.and_then(|h| callee_write_offsets(h, k as usize, 3));
                    let hit = match writes {
                        Some(ws) => ws.iter().any(|&(w, sz)| w < delta + 8 && delta < w + sz),
                        None => true,
                    };
                    if hit {
                        cur = Some(None);
                    }
                }
            }
        }
        it = i.get_next_instruction();
    }
    cur
}

/// The store reaching the ENTRY of block `bi`, if a SINGLE definition reaches on
/// every path (else None). Loops are treated conservatively (None). This is a
/// sound intra-procedural reaching-definition: it never forwards an ambiguous value.
fn entry_reach<'c>(
    bi: usize,
    blocks: &[BasicBlock<'c>],
    preds: &[Vec<usize>],
    ptr: BasicValueEnum<'c>,
    target: &(String, i64),
    visiting: &mut HashSet<usize>,
    memo: &mut HashMap<usize, Option<BasicValueEnum<'c>>>,
) -> Option<BasicValueEnum<'c>> {
    if let Some(m) = memo.get(&bi) {
        return *m;
    }
    if !visiting.insert(bi) {
        return None; // loop -> ambiguous
    }
    let ps = &preds[bi];
    let mut agreed: Option<Option<BasicValueEnum<'c>>> = None; // None=unset; Some(Some v)=agreed v; Some(None)=ambiguous
    if ps.is_empty() {
        agreed = Some(None); // entry block: uninitialized / a parameter -> not forwardable
    }
    for &p in ps {
        let via = match block_rd(blocks[p], None, ptr, target) {
            Some(x) => x,                                                      // block p defines or clobbers
            None => entry_reach(p, blocks, preds, ptr, target, visiting, memo), // untouched in p -> look further back
        };
        agreed = Some(match agreed {
            None => via,
            Some(a) if a == via => a,
            _ => None, // paths disagree -> ambiguous
        });
    }
    visiting.remove(&bi);
    let result = agreed.flatten();
    memo.insert(bi, result);
    result
}

/// The value feeding a `load`, via SOUND intra-procedural reaching definitions:
/// the unique store to the slot that reaches the load on every path. Returns
/// None (stays opaque) whenever the reaching definition is ambiguous — it never
/// forwards a value that isn't guaranteed, so it cannot fabricate.
fn forward_load<'c>(load: InstructionValue<'c>, g: FunctionValue<'c>) -> Option<BasicValueEnum<'c>> {
    let ptr = match load.get_operand(0) {
        Some(Operand::Value(p)) => p,
        _ => return None,
    };
    // only analyze loads from a precisely-comparable (alloca-based) slot.
    if !ptr_is_clean(ptr) {
        return None;
    }
    let target = ptr_base_off(ptr);
    let blocks = g.get_basic_blocks();
    let load_blk = load.get_parent()?;
    // within the load's own block: the reaching state before the load.
    match block_rd(load_blk, Some(load), ptr, &target) {
        Some(Some(v)) => return Some(v),
        Some(None) => return None, // clobbered in-block before the load
        None => {}                 // untouched here -> predecessors
    }
    // otherwise, the reaching definition at the block entry (across predecessors).
    let bidx: HashMap<String, usize> = blocks
        .iter()
        .enumerate()
        .map(|(i, b)| (b.get_name().to_string_lossy().into_owned(), i))
        .collect();
    let mut preds: Vec<Vec<usize>> = vec![vec![]; blocks.len()];
    for (i, b) in blocks.iter().enumerate() {
        if let Some(term) = b.get_terminator() {
            for k in 0..term.get_num_operands() {
                if let Some(Operand::Block(bb)) = term.get_operand(k) {
                    if let Some(&j) = bidx.get(&bb.get_name().to_string_lossy().into_owned()) {
                        preds[j].push(i);
                    }
                }
            }
        }
    }
    let load_bi = *bidx.get(&load_blk.get_name().to_string_lossy().into_owned())?;
    let (mut visiting, mut memo) = (HashSet::new(), HashMap::new());
    entry_reach(load_bi, &blocks, &preds, ptr, &target, &mut visiting, &mut memo)
}

/// Recover the symbolic value of `v` inside `g`, NORMALIZING the Soroban i128/u128
/// limb representation: Vals are decoded to their mathematical integer, the small
/// (shift+tag) and object forms collapse, spilled values forward from their store,
/// carry/sign bookkeeping is dropped, and fastcc helpers are inlined. Models
/// i128/u128 as unbounded Int (sound while the contract's range checks hold).
/// Anything unrecognized becomes an uninterpreted function of its recovered inputs.
fn value_expr<'c>(
    v: BasicValueEnum<'c>,
    g: FunctionValue<'c>,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
    depth: u32,
) -> Expr {
    if !rich() {
        return value_expr_raw(v, g, module, memo, depth);
    }
    // rich mode explores callees through out-pointers: memoize by LLVM value
    // identity (unique per function) with a cycle guard, or it is exponential.
    use inkwell::values::AsValueRef;
    let key = (v.as_value_ref() as usize, g.as_value_ref() as usize);
    if let Some(e) = RICH_MEMO.with(|m| m.borrow().get(&key).cloned()) {
        return e;
    }
    RICH_MEMO.with(|m| m.borrow_mut().insert(key, Expr::Opaque("cyc".into(), vec![])));
    let mut e = fold_rich(simplify(value_expr_raw(v, g, module, memo, depth)));
    // shared subterms are cloned at every use, so trees can grow exponentially;
    // a guard operand worth naming is small — collapse anything huge.
    if expr_size(&e, rich_cap()) >= rich_cap() {
        e = Expr::Opaque("big".into(), vec![]);
    }
    RICH_MEMO.with(|m| m.borrow_mut().insert(key, e.clone()));
    e
}

/// Fold the i128 / Soroban lowering idioms back into source-level values. Applied
/// at every reconstructed node (children are already folded):
/// - hi-limb phi `phi(x, AShr(x,63))` → `x` (the sign-extended hi limb);
/// - Soroban bool decode `Select(And(b,255)==1, 1, Select(And(b,255)==0, 0, 2))`
///   → `@bool(b)`, and `And(@bool b, 1) == 0` → `@isfalse(b)`;
/// rustc's inlined 64×32 multiply of a limb `x` by `y`: `(x >> 32)·y << 32 +
/// (x & (2³²−1))·y` is `x·y`; and the sign restore of a sign-magnitude
/// product, `c ? |a|·y : −(|a|·y)` with `|a| = c ? a : −a`, is `a·y`.
fn fold_mul(e: &Expr) -> Option<Expr> {
    let op = |x: &Expr, l: &str, n: usize| match x { Expr::Opaque(m, v) if m == l && v.len() == n => Some(v.clone()), _ => None };
    let mul = |x: &Expr| match x { Expr::Bin('*', a, b) => Some(((**a).clone(), (**b).clone())), _ => None };
    match e {
        Expr::Bin('+', p, q) => {
            for (hi, lo) in [(p, q), (q, p)] {
                let sh = op(hi, "Shl", 2)?;
                if sh[1] != Expr::Const(32) {
                    continue;
                }
                let (m1, m2) = mul(&sh[0])?;
                let (n1, n2) = mul(lo)?;
                // (x >> 32) * y  and  (x & mask) * y, either factor order
                for (xs, y1) in [(&m1, &m2), (&m2, &m1)] {
                    let Some(r) = op(xs, "LShr", 2) else { continue };
                    if r[1] != Expr::Const(32) {
                        continue;
                    }
                    for (xm, y2) in [(&n1, &n2), (&n2, &n1)] {
                        if let Some(a) = op(xm, "And", 2) {
                            if a[1] == Expr::Const(0xffff_ffff) && a[0] == r[0] && y1 == y2 {
                                return Some(Expr::Bin('*', Box::new(r[0].clone()), Box::new(y1.clone())));
                            }
                        }
                    }
                }
            }
            None
        }
        Expr::Opaque(l, v) if l == "Select" && v.len() == 3 => {
            let neg = match &v[2] { Expr::Bin('-', z, x) if **z == Expr::Const(0) => (**x).clone(), _ => return None };
            if neg != v[1] {
                return None;
            }
            let (m1, m2) = mul(&v[1])?;
            for (abs, y) in [(&m1, &m2), (&m2, &m1)] {
                let s = op(abs, "Select", 3);
                if let Some(s) = s {
                    if s[0] == v[0] && s[2] == Expr::Bin('-', Box::new(Expr::Const(0)), Box::new(s[1].clone())) {
                        return Some(Expr::Bin('*', Box::new(s[1].clone()), Box::new(y.clone())));
                    }
                }
            }
            None
        }
        _ => None,
    }
}

fn fold_rich(e: Expr) -> Expr {
    fn is_op(x: &Expr, l: &str) -> bool { matches!(x, Expr::Opaque(n, _) if n == l) }
    let args_of = |x: &Expr| -> Vec<Expr> { if let Expr::Opaque(_, xs) = x { xs.clone() } else { vec![] } };
    if let Some(m) = fold_mul(&e) {
        return m;
    }
    match &e {
        Expr::Opaque(l, xs) if l == "phi" => {
            // only the exact limb idiom: every arm is x or its sign extension (a
            // `0` arm is a real alternative, e.g. an absent key's default).
            let arms: Vec<&Expr> = xs.iter().collect();
            let is_sext_of = |a: &Expr, x: &Expr| {
                matches!(a, Expr::Opaque(n, v) if n == "AShr" && v.len() == 2 && v[0] == *x && v[1] == Expr::Const(63))
            };
            if let Some(x) = arms.iter().find(|a| !matches!(a, Expr::Opaque(n, _) if n == "AShr")) {
                if arms.iter().all(|a| *a == *x || is_sext_of(a, x)) {
                    return (*x).clone();
                }
            }
            e
        }
        Expr::Opaque(l, xs) if l == "Select" && xs.len() == 3 && xs[1] == xs[2] => xs[1].clone(),
        // `to_muxed.address()`: the muxed case extracts the address, the plain
        // case is the address itself — either way, the address of the argument.
        Expr::Opaque(l, xs) if l == "Select" && xs.len() == 3
            && (matches!(&xs[1], Expr::Opaque(a, v) if a == "@addrof" && v.len() == 1 && v[0] == xs[2])
                || matches!(&xs[2], Expr::Opaque(a, v) if a == "@addrof" && v.len() == 1 && v[0] == xs[1])) =>
        {
            Expr::Opaque("@addrof".into(), vec![if matches!(&xs[1], Expr::Opaque(a, _) if a == "@addrof") { xs[2].clone() } else { xs[1].clone() }])
        }
        Expr::Opaque(l, xs) if l == "Select" && xs.len() == 3 => {
            let (c, t, f) = (&xs[0], &xs[1], &xs[2]);
            // bool decode
            let and255 = |x: &Expr| -> Option<Expr> {
                let a = args_of(x);
                (is_op(x, "And") && a.len() == 2 && a[1] == Expr::Const(255)).then(|| a[0].clone())
            };
            let eq_tag = |x: &Expr, k: i64| -> Option<Expr> {
                let a = args_of(x);
                if is_op(x, "ICmp_EQ") && a.len() == 2 && a[1] == Expr::Const(k) { and255(&a[0]) } else { None }
            };
            if *t == Expr::Const(1) {
                if let (Some(b), Expr::Opaque(fl, fx)) = (eq_tag(c, 1), f) {
                    if fl == "Select" && fx.len() == 3 && fx[1] == Expr::Const(0) && fx[2] == Expr::Const(2) {
                        if eq_tag(&fx[0], 0).as_ref() == Some(&b) {
                            return Expr::Opaque("@bool".into(), vec![b]);
                        }
                    }
                }
            }
            // the i128 compare idiom as a value: select(hi==, lo-cmp, hi-cmp) -> cmp(a, b)
            if is_op(c, "ICmp_EQ") && is_op(f, "ICmp_SLT") || is_op(f, "ICmp_SGT") || is_op(f, "ICmp_SLE") || is_op(f, "ICmp_SGE") {
                let (ce, fe, te) = (args_of(c), args_of(f), args_of(t));
                if is_op(c, "ICmp_EQ") && ce.len() == 2 && fe.len() == 2 && te.len() == 2
                    && ((ce[0] == fe[0] && ce[1] == fe[1]) || (ce[0] == fe[1] && ce[1] == fe[0]))
                {
                    // the value relation: the lo-limb compare's operands (the lo limb
                    // carries the value — the hi limb of a constant is 0) with its
                    // direction, made signed.
                    if let Expr::Opaque(tn, _) = t {
                        if let Some(sfx) = tn.strip_prefix("ICmp_U") {
                            return Expr::Opaque(format!("ICmp_S{sfx}"), te);
                        }
                    }
                    return f.clone();
                }
            }
            // i128 signed division via sign-magnitude: Select(a^b > -1, |a|/|b|, neg).
            // Only when the quotient is literally |a| op |b| of the XOR'd operands.
            let unabs = |x: &Expr| -> Option<Expr> {
                let a = args_of(x);
                if is_op(x, "Select") && a.len() == 3 {
                    let ca = args_of(&a[0]);
                    if is_op(&a[0], "ICmp_SGT") && ca.len() == 2 && ca[1] == Expr::Const(-1) && ca[0] == a[1]
                        && a[2] == Expr::Bin('-', Box::new(Expr::Const(0)), Box::new(a[1].clone()))
                    {
                        return Some(a[1].clone());
                    }
                }
                None
            };
            let ca = args_of(c);
            if is_op(c, "ICmp_SGT") && ca.len() == 2 && ca[1] == Expr::Const(-1) && is_op(&ca[0], "Xor") {
                let xa = args_of(&ca[0]);
                if let (Expr::Bin(o @ ('/' | '%'), qa, qb), 2) = (t, xa.len()) {
                    if let (Some(ua), Some(ub)) = (unabs(qa), unabs(qb)) {
                        if (xa[0] == ua && xa[1] == ub) || (xa[0] == ub && xa[1] == ua) {
                            return Expr::Bin(*o, Box::new(ua), Box::new(ub));
                        }
                    }
                }
            }
            e
        }
        // address arithmetic: @addr(b, o) + k  ->  @addr(b, o + k)
        Expr::Bin('+', a, b) => match (addr_of(a), b.as_ref()) {
            (Some((base, o)), Expr::Const(k)) => Expr::Opaque(format!("@addr:{base}"), vec![Expr::Const(o + k)]),
            _ => e,
        },
        Expr::Opaque(l, xs) if l == "ICmp_EQ" && xs.len() == 2 && xs[1] == Expr::Const(0) => {
            let a = args_of(&xs[0]);
            if is_op(&xs[0], "And") && a.len() == 2 && a[1] == Expr::Const(1) && is_op(&a[0], "@bool") {
                return Expr::Opaque("@isfalse".into(), args_of(&a[0]));
            }
            e
        }
        _ => e,
    }
}

/// A phi as an if-else chain over the conditions that pick each incoming arm:
/// the non-guard conditional branches that SPLIT the paths into the join (the
/// join is reachable from both of their edges); an arm's condition is the edge
/// that leads to its incoming block. The last arm is the `else`.
fn phi_gated<'c>(
    phi: InstructionValue<'c>,
    g: FunctionValue<'c>,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
    depth: u32,
) -> Option<Expr> {
    let pv = inkwell::values::PhiValue::try_from(phi).ok()?;
    let cfg = Cfg::build(g);
    let ij = cfg.bidx(phi.get_parent()?)?;
    let mut arms: Vec<(BasicValueEnum<'c>, usize)> = vec![];
    for k in 0..pv.count_incoming() {
        let (v, b) = pv.get_incoming(k)?;
        if let BasicValueEnum::IntValue(c) = v {
            if c.is_undef() || c.is_poison() {
                continue;
            }
        }
        arms.push((v, cfg.bidx(b)?));
    }
    if arms.len() < 2 {
        return None;
    }
    // each arm's exact condition: reaching its incoming block, then that edge.
    let mut rmemo = HashMap::new();
    let mut conds: Vec<Vec<Expr>> = vec![];
    for (_, b) in &arms {
        let ds = reach_dnf(&cfg, *b, &mut rmemo, &mut HashSet::new())?;
        let mut c = vec![dnf_expr(g, &cfg, &ds, module, memo)?];
        if let Some(e) = edge_cond(g, &cfg, *b, ij, module, memo) {
            if cfg.succ[*b].iter().filter(|&&s| !forces_trap(cfg.blocks[s], 6)).count() > 1 {
                c.push(e);
            }
        }
        c.retain(|x| !matches!(x, Expr::Opaque(l, v) if l == "@true" && v.is_empty()));
        conds.push(c);
    }
    // every arm but the last needs a distinguishing condition.
    if conds[..conds.len() - 1].iter().any(|c| c.is_empty()) {
        return None;
    }
    let mut acc = value_expr(arms.last()?.0, g, module, memo, depth);
    for k in (0..arms.len() - 1).rev() {
        let v = value_expr(arms[k].0, g, module, memo, depth);
        if v == acc {
            continue;
        }
        let c = if conds[k].len() == 1 { conds[k][0].clone() } else { Expr::Opaque("@and".into(), conds[k].clone()) };
        acc = Expr::Opaque("Select".into(), vec![c, v, acc]);
    }
    Some(acc)
}

/// `@addr:base(off)` as a (base, off) memory target.
fn addr_of(e: &Expr) -> Option<(String, i64)> {
    match e {
        Expr::Opaque(l, xs) if l.starts_with("@addr:") && xs.len() == 1 => match xs[0] {
            Expr::Const(o) => Some((l["@addr:".len()..].to_string(), o)),
            _ => None,
        },
        _ => None,
    }
}

/// Node count of `e`, stopping once it reaches `cap`.
fn expr_size(e: &Expr, cap: usize) -> usize {
    fn go(e: &Expr, n: &mut usize, cap: usize) {
        if *n >= cap {
            return;
        }
        *n += 1;
        match e {
            Expr::Bin(_, a, b) | Expr::VecGet(a, b) => {
                go(a, n, cap);
                go(b, n, cap);
            }
            Expr::Opaque(_, xs) => xs.iter().for_each(|x| go(x, n, cap)),
            _ => {}
        }
    }
    let mut n = 0;
    go(e, &mut n, cap);
    n
}

fn value_expr_raw<'c>(
    v: BasicValueEnum<'c>,
    g: FunctionValue<'c>,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
    depth: u32,
) -> Expr {
    use InstructionOpcode::*;
    if depth == 0 {
        return Expr::Opaque("deep".into(), vec![]);
    }
    if let Some(i) = param_index(v, g) {
        return Expr::Param(i);
    }
    if let BasicValueEnum::IntValue(c) = v {
        if c.is_const() {
            if let Some(k) = c.get_sign_extended_constant() {
                return Expr::Const(k);
            }
        }
    }
    let Some(ins) = as_instr(v) else { return Expr::Opaque("arg".into(), vec![]) };
    let o = |k: u32| match ins.get_operand(k) { Some(Operand::Value(x)) => Some(x), _ => None };

    // ---- named calls: storage / host arithmetic / wrappers / helpers ----
    if let Some(name) = callee_name(ins) {
        // rich mode: keep the storage KEY so the slot can be named after
        // substitution (a getter helper's key is built from its discriminant
        // param; the caller's constant names it).
        if rich() && (name.contains("get_contract_data") || name.contains("has_contract_data")) {
            let dur = match o(1) { Some(d) => durability(d), None => "?".into() };
            let key = o(0).map(|x| key_expr(x, g, module, memo, depth - 1)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            let mut slot = Expr::Opaque(format!("@slot:{dur}"), vec![key]);
            if let Some(site) = entry_site(g, ins) {
                slot = annotate_at(&slot, site);
            }
            return if name.contains("has_contract_data") { Expr::Opaque("@has".into(), vec![slot]) } else { slot };
        }
        // rich mode: a `#[contracttype]` struct packed from linear memory
        // (keys_pos, vals_pos, n): its field values, by name.
        if rich() && name.contains("map_new_from_linear_memory") {
            let names = o(0).and_then(u32_val).and_then(|p| struct_keys(module, p));
            let (Some(names), Some(at)) = (names, o(1).and_then(val_addr)) else { return Expr::Opaque("@struct".into(), vec![]) };
            let cfg = Cfg::build(g);
            let Some(blk) = ins.get_parent().and_then(|bb| cfg.bidx(bb)) else { return Expr::Opaque("@struct".into(), vec![]) };
            let vals: Vec<Expr> = (0..names.len())
                .map(|k| {
                    let mut seen = MemCtx::default();
                    mem_before(ins.get_previous_instruction(), blk, &(at.0.clone(), at.1 + 8 * k as i64), g, &cfg, module, memo, depth - 1, &mut seen)
                        .map(val_literal)
                        .unwrap_or_else(|| Expr::Opaque("?".into(), vec![]))
                })
                .collect();
            return Expr::Opaque(format!("@struct:{}", names.join(",")), vals);
        }
        // rich mode: a Vec built from linear memory, as its element values
        // (e.g. the `[current_contract_address]` argument of `balance`).
        if rich() && name.contains("vec_new_from_linear_memory") {
            let els: Vec<Expr> = linmem_vals_ordered(v)
                .into_iter()
                .map(|x| value_expr(x, g, module, memo, depth - 1))
                .collect();
            return Expr::Opaque("@vec".into(), els);
        }
        // rich mode: a cross-contract call `call(contract, fn_symbol, args_vec)`.
        if rich() && name == "call.call" {
            let a = |k: u32, memo: &mut HashMap<String, Option<Expr>>| {
                o(k).map(|x| value_expr(x, g, module, memo, depth - 1)).unwrap_or(Expr::Opaque("?".into(), vec![]))
            };
            let (c0, c1, c2) = (a(0, memo), a(1, memo), a(2, memo));
            if let Expr::Const(sym) = c1 {
                if let Some(fname) = decode_symbol(sym as u64) {
                    let e = Expr::Opaque(format!("@call:{fname}"), vec![c0, c2]);
                    return match entry_site(g, ins) { Some(site) => annotate_at(&e, site), None => e };
                }
            }
            return Expr::Opaque("@call".into(), vec![c0, c1, c2]);
        }
        if rich() && name.contains("symbol_new_from_linear_memory") {
            if let Some((off, len)) = symbol_off_len(ins, module) {
                if let Some(t) = rodata_text(&rodata_segs(module), off, len) {
                    return Expr::Opaque(format!("@sym:{t}"), vec![]);
                }
            }
        }
        if rich() && name.contains("get_address_from_muxed_address") {
            let x = o(0).map(|x| value_expr(x, g, module, memo, depth - 1)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            return Expr::Opaque("@addrof".into(), vec![x]);
        }
        if rich() && name.contains("get_current_contract_address") {
            return Expr::Opaque("@pool".into(), vec![]);
        }
        // ledger info: `e.ledger().sequence()` / `.timestamp()`.
        if rich() && name.starts_with("context.get_ledger_") && ins.get_num_operands() == 1 {
            return Expr::Opaque(format!("@env:{}", &name["context.get_ledger_".len()..]), vec![]);
        }
        // `v.len()` (a U32Val).
        if rich() && name == "vec.vec_len" {
            let x = o(0).map(|x| value_expr(x, g, module, memo, depth - 1)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            return Expr::Opaque("@len".into(), vec![x]);
        }
        // `obj_cmp(a, b)`: the ordering of two host objects (== 0 iff a == b).
        if rich() && name == "context.obj_cmp" {
            let a = |k: u32, memo: &mut HashMap<String, Option<Expr>>| {
                o(k).map(|x| value_expr(x, g, module, memo, depth - 1)).unwrap_or(Expr::Opaque("?".into(), vec![]))
            };
            let (x, y) = (a(0, memo), a(1, memo));
            return Expr::Opaque("@cmp".into(), vec![x, y]);
        }
        if name.contains("get_contract_data") {
            if let Src::Store { dur, params } = store_src(ins, &arg_table(g)) {
                return Expr::Slot(dur, params.len());
            }
        }
        if let Some(opc) = host_op(&name) {
            let a = o(0).map(|x| value_expr(x, g, module, memo, depth - 1)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            let b = o(1).map(|x| value_expr(x, g, module, memo, depth - 1)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            return Expr::Bin(opc, Box::new(a), Box::new(b));
        }
        if is_wrapper(&name) {
            if let Some(x) = o(0) {
                return value_expr(x, g, module, memo, depth - 1);
            }
        }
        if name.contains("obj_from_") && name.contains("_pieces") {
            // the lowest limb (the last ARGUMENT — the final operand of a call is
            // the callee itself) carries the value's low 64 bits.
            let n = ins.get_num_operands();
            if n >= 2 {
                if let Some(Operand::Value(lo)) = ins.get_operand(n - 2) {
                    return value_expr(lo, g, module, memo, depth - 1);
                }
            }
        }
        // vec_get(handle, index): a symbolic array read -> reserve[index].
        if name.contains("vec_get") {
            let h = o(0).map(|x| value_expr(x, g, module, memo, depth - 1)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            let idx = o(1).map(|x| value_expr(x, g, module, memo, depth - 1)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            return Expr::VecGet(Box::new(h), Box::new(idx));
        }
        if let Some(h) = module.get_function(&name) {
            if h.count_basic_blocks() > 0 {
                if let Some(re) = ret_expr(h, module, memo, depth - 1) {
                    let actuals: Vec<Expr> = (0..ins.get_num_operands().saturating_sub(1))
                        .map(|k| o(k).map(|x| value_expr(x, g, module, memo, depth - 1)).unwrap_or(Expr::Opaque("?".into(), vec![])))
                        .collect();
                    return subst(&re, &actuals);
                }
            }
        }
    }

    // ---- i128/u128 encode/decode + arithmetic normalization ----
    match ins.get_opcode() {
        // small-form ENCODE: or(shl(V, 8), tag) == V
        Or => {
            if let Some(sh) = o(0).and_then(as_instr) {
                if sh.get_opcode() == Shl {
                    let v8 = match sh.get_operand(1) {
                        Some(Operand::Value(BasicValueEnum::IntValue(a))) => a.get_zero_extended_constant(),
                        _ => None,
                    };
                    if v8 == Some(8) {
                        if let Some(Operand::Value(val)) = sh.get_operand(0) {
                            return value_expr(val, g, module, memo, depth - 1);
                        }
                    }
                }
            }
        }
        // small-form DECODE: (ashr|lshr)(payload, 8) == value
        AShr | LShr => {
            let amt = o(1).and_then(|x| match x {
                BasicValueEnum::IntValue(a) => a.get_zero_extended_constant(),
                _ => None,
            });
            if amt == Some(8) {
                if let Some(x) = o(0) {
                    return value_expr(x, g, module, memo, depth - 1);
                }
            }
        }
        // value arithmetic (low-limb add/sub/mul/div == value, modulo range).
        Add | Sub | Mul | UDiv | SDiv | URem | SRem => {
            let opc = match ins.get_opcode() {
                Add => '+', Sub => '-', Mul => '*', UDiv | SDiv => '/', _ => '%',
            };
            // drop the i128 carry addend of a hi limb: X ± ext(icmp ult (a + b), a).
            if matches!(opc, '+' | '-') {
                let carry = o(1).and_then(as_instr).filter(|bi| matches!(bi.get_opcode(), SExt | ZExt)).and_then(|bi| match bi.get_operand(0) {
                    Some(Operand::Value(c)) => as_instr(c),
                    _ => None,
                }).is_some_and(|c| {
                    c.get_opcode() == ICmp && c.get_icmp_predicate() == Some(inkwell::IntPredicate::ULT)
                        && matches!(c.get_operand(0), Some(Operand::Value(s)) if as_instr(s).is_some_and(|s| s.get_opcode() == Add))
                });
                if carry {
                    if let Some(x) = o(0) {
                        return value_expr(x, g, module, memo, depth - 1);
                    }
                }
            }
            let a = o(0).map(|x| value_expr(x, g, module, memo, depth - 1)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            let b = o(1).map(|x| value_expr(x, g, module, memo, depth - 1)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            return Expr::Bin(opc, Box::new(a), Box::new(b));
        }
        // rich mode: the address of a frame slot, symbolically.
        PtrToInt if rich() => {
            if let Some(p) = o(0) {
                if ptr_is_clean(p) {
                    let (b, off) = ptr_base_off(p);
                    return Expr::Opaque(format!("@addr:{b}"), vec![Expr::Const(off)]);
                }
            }
        }
        // extension, and truncation to ≥ 32 bits (u32/i32 values, limbs), pass the
        // value through; a narrower truncation keeps the low bits (a Val's tag byte).
        SExt | ZExt | Trunc => {
            if let Some(x) = o(0) {
                let w = ins.get_type().into_int_type().get_bit_width();
                let v = value_expr(x, g, module, memo, depth - 1);
                if ins.get_opcode() == Trunc && w < 32 {
                    return Expr::Opaque("And".into(), vec![v, Expr::Const((1i64 << w) - 1)]);
                }
                return v;
            }
        }
        // rich mode: a phi at a control-flow join, as the value of the arm taken —
        // `Select(c, vT, vF)` / an if-else chain over the branches that split the
        // paths into the join. Lowering idioms (hi-limb sign phis, undef arms of an
        // Option, identical arms) fold first.
        Phi if rich() => {
            let n = ins.get_num_operands();
            let mut arms: Vec<Expr> = vec![];
            for k in 0..n {
                if let Some(Operand::Value(x)) = ins.get_operand(k) {
                    if let BasicValueEnum::IntValue(c) = x {
                        if c.is_undef() || c.is_poison() {
                            continue; // the absent case of an Option
                        }
                    }
                    arms.push(value_expr(x, g, module, memo, depth - 1));
                }
            }
            if arms.is_empty() {
                return Expr::Opaque("undef".into(), vec![]);
            }
            if arms.iter().all(|a| *a == arms[0]) {
                return arms.swap_remove(0);
            }
            // the i128 hi-limb pattern `phi(x, AShr(x, 63) [, 0])` folds to x; any
            // other phi is a real choice (`if buy_a { out } else { 0 }`): gate it.
            let has_sext = arms.iter().any(|a| matches!(a, Expr::Opaque(n, v) if n == "AShr" && v.get(1) == Some(&Expr::Const(63))));
            let folded = fold_rich(Expr::Opaque("phi".into(), arms.clone()));
            if has_sext && !matches!(&folded, Expr::Opaque(l, _) if l == "phi") {
                return folded;
            }
            if let Some(sel) = phi_gated(ins, g, module, memo, depth - 1) {
                return sel;
            }
            return folded;
        }
        // phi: collapse when all incoming values denote the same value.
        Phi => {
            let mut branches = vec![];
            for k in 0..ins.get_num_operands() {
                if let Some(Operand::Value(x)) = ins.get_operand(k) {
                    if x.is_int_value() {
                        branches.push(value_expr(x, g, module, memo, depth - 1));
                    }
                }
            }
            // collapse when the non-zero branches all agree (the 0 is the
            // storage-absent default, which the Lean model reads as 0 anyway).
            let nonzero: Vec<&Expr> = branches.iter().filter(|b| **b != Expr::Const(0)).collect();
            if let Some(first) = nonzero.first() {
                if nonzero.iter().all(|b| *b == *first) {
                    return (*first).clone();
                }
            } else if !branches.is_empty() {
                return Expr::Const(0);
            }
            return Expr::Opaque("phi".into(), branches);
        }
        // spilled value: forward from the store that wrote this slot.
        Load => {
            if let Some(stored) = forward_load(ins, g) {
                return value_expr(stored, g, module, memo, depth - 1);
            }
            // rich mode: the slot was written by a CALLEE through an out-pointer
            // (i128 results, storage getters, token balance calls).
            if rich() {
                if let Some(e) = outparam_load(ins, g, module, memo, depth - 1) {
                    return e;
                }
                // a read through one of OUR pointer params: the caller resolves it.
                if let Some(Operand::Value(p)) = ins.get_operand(0) {
                    let (b, off) = ptr_base_off(p);
                    if let Some(j) = (0..g.count_params()).find(|&q| g.get_nth_param(q).map(fmt) == Some(b.clone())) {
                        return Expr::Opaque("@deref".into(), vec![Expr::Param(j as usize), Expr::Const(off)]);
                    }
                    // a read through a COMPUTED pointer (e.g. a by-reference closure
                    // capture: the env holds the address): resolve the address, then
                    // the memory there; or defer to the call site.
                    if let Some(itp) = as_instr(p).filter(|x| x.get_opcode() == IntToPtr) {
                        if let Some(Operand::Value(a)) = itp.get_operand(0) {
                            let ae = fold_rich(value_expr(a, g, module, memo, depth - 1));
                            if let Some(t) = addr_of(&ae) {
                                let cfg = Cfg::build(g);
                                if let Some(blk) = ins.get_parent().and_then(|bb| cfg.bidx(bb)) {
                                    let mut seen = MemCtx::default();
                                    if let Some(v) = mem_before(ins.get_previous_instruction(), blk, &t, g, &cfg, module, memo, depth - 1, &mut seen) {
                                        return v;
                                    }
                                }
                            }
                            if expr_size(&ae, 16) < 16 {
                                return Expr::Opaque("@load".into(), vec![ae]);
                            }
                        }
                    }
                }
            }
        }
        _ => {}
    }

    // ---- unrecognized: uninterpreted function of recovered inputs ----
    let label = callee_name(ins).filter(|n| !n.is_empty()).unwrap_or_else(|| {
        match (rich(), ins.get_opcode(), ins.get_icmp_predicate()) {
            (true, ICmp, Some(p)) => format!("ICmp_{p:?}"),
            (_, op, _) => format!("{op:?}"),
        }
    });
    let inputs: Vec<Expr> = (0..ins.get_num_operands())
        .filter_map(|k| match ins.get_operand(k) {
            Some(Operand::Value(x)) if x.is_int_value() => Some(value_expr(x, g, module, memo, depth - 1)),
            _ => None,
        })
        .collect();
    Expr::Opaque(sanitize(&label), inputs)
}

/// The return expression of `g` over its own parameters (memoized).
fn ret_expr<'c>(
    g: FunctionValue<'c>,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
    depth: u32,
) -> Option<Expr> {
    let key = g.get_name().to_string_lossy().into_owned();
    if let Some(e) = memo.get(&key) {
        return e.clone();
    }
    memo.insert(key.clone(), None); // recursion guard
    if depth == 0 {
        return None;
    }
    // u128->u256 widening helper: serializes its two limb params through linear
    // memory into a host Bytes object, then `u256_val_from_be_bytes`. That round
    // trip is host-managed memory we can't thread, but the widen is value-
    // preserving, so model the result as the low-limb param (the integer value).
    let widens_u256 = all_instrs(g).iter().any(|i| callee_has(*i, "u256_val_from_be_bytes"));
    if widens_u256 {
        let nparams = g.get_params().len();
        if nparams >= 2 {
            let r = Some(Expr::Param(nparams - 1)); // low limb is the last param
            memo.insert(key, r.clone());
            return r;
        }
    }
    // find a `ret <val>` with a value operand.
    let mut result = None;
    for i in all_instrs(g) {
        if i.get_opcode() == InstructionOpcode::Return {
            if let Some(Operand::Value(rv)) = i.get_operand(0) {
                result = Some(value_expr(rv, g, module, memo, depth - 1));
                break;
            }
        }
    }
    memo.insert(key, result.clone());
    result
}

thread_local! {
    /// Rich reconstruction (used by `--lean model`): keep storage keys and resolve
    /// loads of callee-written out-pointer slots. Off by default so the other
    /// emitters and the tests see the established `value_expr` behaviour.
    static RICH: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
    static RICH_MEMO: std::cell::RefCell<HashMap<(usize, usize), Expr>> = std::cell::RefCell::new(HashMap::new());
}
fn rich_cap() -> usize {
    std::env::var("SLICE_CAP").ok().and_then(|v| v.parse().ok()).unwrap_or(1500)
}
fn rich() -> bool {
    RICH.with(|r| r.get())
}
fn with_rich<T>(f: impl FnOnce() -> T) -> T {
    let prev = RICH.with(|r| r.replace(true));
    let out = f();
    RICH.with(|r| r.set(prev));
    if !prev {
        RICH_MEMO.with(|m| m.borrow_mut().clear());
    }
    out
}

/// A load whose slot was written by a callee through an out-pointer (or by a
/// store the sound forwarding couldn't prove): resolve the memory at the load's
/// address just before the load. See `mem_before`.
fn outparam_load<'c>(
    load: InstructionValue<'c>,
    g: FunctionValue<'c>,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
    depth: u32,
) -> Option<Expr> {
    let Some(Operand::Value(ptr)) = load.get_operand(0) else { return None };
    let target = ptr_base_off(ptr);
    let cfg = Cfg::build(g);
    let blk = cfg.bidx(load.get_parent()?)?;
    let width = match load.get_type() { inkwell::types::AnyTypeEnum::IntType(t) => (t.get_bit_width() as i64 + 7) / 8, _ => 8 };
    let mut seen = MemCtx { width, ..Default::default() };
    mem_before(load.get_previous_instruction(), blk, &target, g, &cfg, module, memo, depth, &mut seen)
}

/// The value in memory at `target` (frame base, offset) just before `start` (or
/// at the end of block `blk` when `start` is None): the nearest preceding write —
/// a store to it, or a call that writes it through a pointer we handed it (the
/// callee's stored value, reconstructed over its params and substituted with the
/// call's actuals). At a join, each predecessor is resolved and they must agree
/// (else a `phi`). Loops / unknown writes give None.
#[allow(clippy::too_many_arguments)]
fn mem_before<'c>(
    start: Option<InstructionValue<'c>>,
    blk: usize,
    target: &(String, i64),
    g: FunctionValue<'c>,
    cfg: &Cfg<'c>,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
    depth: u32,
    seen: &mut MemCtx,
) -> Option<Expr> {
    if depth == 0 {
        return None;
    }
    let mut cur = start;
    while let Some(i) = cur {
        cur = i.get_previous_instruction();
        match i.get_opcode() {
            InstructionOpcode::Store => {
                if let (Some(Operand::Value(sv)), Some(Operand::Value(sp))) = (i.get_operand(0), i.get_operand(1)) {
                    let (b, o) = ptr_base_off(sp);
                    if (b.as_str(), o) == (target.0.as_str(), target.1) {
                        return Some(value_expr(sv, g, module, memo, depth));
                    }
                    // `base + phi(k₁, k₂, …)`: which slot is written depends on the
                    // path in; resolve per predecessor and join.
                    if let Some(r) = phi_offset_store(i, sv, sp, blk, target, g, cfg, module, memo, depth) {
                        return r;
                    }
                    let size = match sv { BasicValueEnum::IntValue(v) => (v.get_type().get_bit_width() as i64 + 7) / 8, _ => 8 };
                    if b == target.0 && o < target.1 + seen.width.max(1) && target.1 < o + size {
                        return None; // a partial overwrite of our slot
                    }
                    // a store through an address we can't place may hit our slot.
                    let placed = ptr_is_clean(sp)
                        || g.get_params().iter().any(|q| fmt(*q) == b)
                        || (sp.is_pointer_value() && sp.into_pointer_value().as_instruction().is_none());
                    if b != target.0 && !placed {
                        return None;
                    }
                }
            }
            InstructionOpcode::Call => {
                let Some(cn) = callee_name(i) else { continue };
                // a host unpack of a struct (map) / Vec into linear memory: the slot
                // is one named field (element) of it.
                if let Some(d) = linmem_dest(i) {
                    let ((b, o), len) = d?;
                    if b != target.0 || target.1 + 8 <= o || o + len <= target.1 {
                        continue;
                    }
                    let delta = target.1 - o;
                    if delta % 8 != 0 {
                        return None;
                    }
                    let op = |k: u32| match i.get_operand(k) { Some(Operand::Value(x)) => Some(x), _ => None };
                    let src = value_expr(op(0)?, g, module, memo, depth);
                    let idx = (delta / 8) as usize;
                    if cn.contains("map_unpack_to_linear_memory") {
                        let names = op(1).and_then(u32_val).and_then(|p| struct_keys(module, p))?;
                        return Some(Expr::Opaque(format!("@field:{}", names.get(idx)?), vec![src]));
                    }
                    if cn.contains("vec_unpack_to_linear_memory") {
                        return Some(Expr::VecGet(Box::new(src), Box::new(Expr::Const(idx as i64))));
                    }
                    return None; // raw bytes
                }
                // memset(dst, byte, len) / memcpy(dst, src, len) covering our slot.
                if cn.starts_with("llvm.memset") || cn.starts_with("llvm.memcpy") || cn.starts_with("llvm.memmove") {
                    if let (Some(Operand::Value(dst)), Some(Operand::Value(x)), Some(Operand::Value(BasicValueEnum::IntValue(len)))) =
                        (i.get_operand(0), i.get_operand(1), i.get_operand(2))
                    {
                        let (b, o) = ptr_base_off(dst);
                        if b == target.0 && o <= target.1 {
                            let n = len.get_zero_extended_constant().map(|n| n as i64);
                            match n {
                                Some(n) if target.1 < o + n => {
                                    if cn.starts_with("llvm.memset") {
                                        return match x {
                                            BasicValueEnum::IntValue(c) if c.get_zero_extended_constant() == Some(0) => Some(Expr::Const(0)),
                                            _ => None,
                                        };
                                    }
                                    // memcpy: the source at the same displacement.
                                    let (sb, so) = ptr_base_off(x);
                                    let blk_here = i.get_parent().and_then(|bb| cfg.bidx(bb))?;
                                    let mut seen2 = MemCtx::default();
                                    return mem_before(i.get_previous_instruction(), blk_here, &(sb, so + (target.1 - o)), g, cfg, module, memo, depth - 1, &mut seen2);
                                }
                                Some(_) => continue, // doesn't cover our slot
                                None => return None, // unknown length
                            }
                        }
                    }
                    continue;
                }
                let Some(h) = module.get_function(&cn) else { continue };
                if h.count_basic_blocks() == 0 {
                    continue;
                }
                let nargs = i.get_num_operands().saturating_sub(1);
                for k in 0..nargs {
                    let Some(Operand::Value(a)) = i.get_operand(k) else { continue };
                    let (b, o) = if a.is_pointer_value() { ptr_base_off(a) } else { addr_base_off(a) };
                    if b != target.0 || o > target.1 {
                        continue;
                    }
                    let delta = target.1 - o;
                    // only a callee that writes this offset through the pointer.
                    match callee_write_offsets(h, k as usize, 3) {
                        Some(ws) if !ws.iter().any(|&(w, sz)| w < delta + 8 && delta < w + sz) => continue,
                        _ => {}
                    }
                    if let Some(e) = arith_out(i, h, k, delta, g, module, memo, depth) {
                        return Some(e);
                    }
                    let e = callee_store_at(h, k as usize, delta, module, memo, depth, 3)?;
                    return Some(subst_call(&e, i, g, cfg, module, memo, depth));
                }
            }
            _ => {}
        }
    }
    // reached the block start: resolve from the predecessors (each block's
    // end-state cached, so diamonds don't re-walk; a cycle gives None).
    if let Some(r) = seen.done.get(&blk) {
        return r.clone();
    }
    if !seen.active.insert(blk) {
        return None; // loop
    }
    let preds: Vec<usize> = (0..cfg.succ.len())
        .filter(|&u| cfg.succ[u].contains(&blk) && seen.allow.as_ref().is_none_or(|a| a.contains(&u)))
        .collect();
    // the function's entry: memory behind one of our pointer params is the
    // caller's (resolved at the call site).
    if preds.is_empty() {
        seen.active.remove(&blk);
        let r = (0..g.count_params())
            .find(|&q| g.get_nth_param(q).map(fmt).as_deref() == Some(target.0.as_str()))
            .map(|q| Expr::Opaque("@deref".into(), vec![Expr::Param(q as usize), Expr::Const(target.1)]));
        seen.done.insert(blk, r.clone());
        return r;
    }
    let mut vals: Vec<Expr> = vec![];
    let mut arms: Vec<(usize, Expr)> = vec![];
    let mut ok = true;
    for p in preds {
        let e = match seen.done.get(&(p + 1_000_000)) {
            Some(r) => r.clone(),
            None => {
                let r = mem_before(cfg.blocks[p].get_last_instruction(), p, target, g, cfg, module, memo, depth, seen);
                seen.done.insert(p + 1_000_000, r.clone());
                r
            }
        };
        match e {
            Some(e) => {
                if !vals.contains(&e) {
                    vals.push(e.clone());
                }
                arms.push((p, e));
            }
            None => {
                ok = false;
                break;
            }
        }
    }
    seen.active.remove(&blk);
    let r = if !ok {
        None
    } else {
        match vals.len() {
            0 => None,
            1 => vals.pop(),
            // paths that disagree: the value of the path taken.
            _ => gate_by_reach(g, cfg, arms, Some(blk), module, memo),
        }
    };
    seen.done.insert(blk, r.clone());
    r
}

/// A store through `inttoptr(base + phi(consts))` with the phi in block `blk`
/// (the store's own block): per predecessor, the stored value (its phi arm) if
/// that arm's offset is the target, else the memory at the end of the
/// predecessor; joined by the exact path conditions. None: not this shape.
#[allow(clippy::too_many_arguments)]
fn phi_offset_store<'c>(
    store: InstructionValue<'c>,
    sv: BasicValueEnum<'c>,
    sp: BasicValueEnum<'c>,
    blk: usize,
    target: &(String, i64),
    g: FunctionValue<'c>,
    cfg: &Cfg<'c>,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
    depth: u32,
) -> Option<Option<Expr>> {
    let itp = as_instr(sp).filter(|x| x.get_opcode() == InstructionOpcode::IntToPtr)?;
    let add = itp.get_operand(0)?.value().and_then(as_instr).filter(|x| x.get_opcode() == InstructionOpcode::Add)?;
    let (x, y) = (add.get_operand(0)?.value()?, add.get_operand(1)?.value()?);
    let is_phi = |v: BasicValueEnum<'c>| as_instr(v).and_then(|p| inkwell::values::PhiValue::try_from(p).ok()).filter(|p| p.as_instruction().get_parent() == store.get_parent());
    let (phi, base) = match (is_phi(x), is_phi(y)) {
        (Some(p), None) => (p, y),
        (None, Some(p)) => (p, x),
        _ => return None,
    };
    let (bname, boff) = addr_base_off(base);
    if bname != target.0 {
        return None;
    }
    let mut arms: Vec<(usize, Expr)> = vec![];
    for k in 0..phi.count_incoming() {
        let (off, pred) = phi.get_incoming(k)?;
        let BasicValueEnum::IntValue(c) = off else { return Some(None) };
        let Some(c) = c.get_sign_extended_constant() else { return Some(None) };
        let p = cfg.bidx(pred)?;
        let v = if boff + c == target.1 {
            // the stored value as it arrives from this predecessor
            let svp = as_instr(sv)
                .and_then(|i| inkwell::values::PhiValue::try_from(i).ok())
                .filter(|q| q.as_instruction().get_parent() == store.get_parent())
                .and_then(|q| (0..q.count_incoming()).filter_map(|j| q.get_incoming(j)).find(|(_, b)| *b == pred).map(|(v, _)| v))
                .unwrap_or(sv);
            value_expr(svp, g, module, memo, depth)
        } else if (boff + c - target.1).abs() < 8 {
            return Some(None); // a partial overlap
        } else {
            let mut seen = MemCtx::default();
            // unknown on this path: open (a path that panics later drops out under the facts)
            mem_before(cfg.blocks[p].get_last_instruction(), p, target, g, cfg, module, memo, depth, &mut seen)
                .unwrap_or_else(|| Expr::Opaque("?".into(), vec![]))
        };
        arms.push((p, v));
    }
    let _ = blk;
    Some(gate_by_reach(g, cfg, arms, Some(cfg.bidx(store.get_parent()?)?), module, memo))
}

/// Walk state for `mem_before`: blocks in progress (cycle guard) and resolved
/// block end-states.
#[derive(Default)]
struct MemCtx {
    active: HashSet<usize>,
    done: HashMap<usize, Option<Expr>>,
    allow: Option<HashSet<usize>>, // only these blocks are on the paths considered (one switch case)
    width: i64,                    // bytes read at the target (0: unknown)
}

/// Substitute a callee-relative expression at call site `call`: callee reads
/// through a pointer param (`@deref(Param j, off)`) are resolved against the
/// caller's memory at the call; the remaining params become the call's actuals.
#[allow(clippy::too_many_arguments)]
fn subst_call<'c>(
    e: &Expr,
    call: InstructionValue<'c>,
    g: FunctionValue<'c>,
    cfg: &Cfg<'c>,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
    depth: u32,
) -> Expr {
    fn derefs<'c>(
        e: &Expr,
        call: InstructionValue<'c>,
        g: FunctionValue<'c>,
        cfg: &Cfg<'c>,
        module: &inkwell::module::Module<'c>,
        memo: &mut HashMap<String, Option<Expr>>,
        depth: u32,
    ) -> Expr {
        match e {
            Expr::Opaque(l, xs) if l == "@deref" && xs.len() == 2 => {
                if let (Expr::Param(j), Expr::Const(off)) = (&xs[0], &xs[1]) {
                    if let Some(Operand::Value(a)) = call.get_operand(*j as u32) {
                        let (b, o) = if a.is_pointer_value() { ptr_base_off(a) } else { addr_base_off(a) };
                        // the pointer is itself our param: keep propagating outward.
                        if let Some(pj) = (0..g.count_params()).find(|&q| g.get_nth_param(q).map(fmt) == Some(b.clone())) {
                            return done(Expr::Opaque("@deref".into(), vec![Expr::Param(pj as usize), Expr::Const(o + off)]));
                        }
                        let blk = call.get_parent().and_then(|bb| cfg.bidx(bb));
                        if let Some(blk) = blk {
                            let mut seen = MemCtx::default();
                            if let Some(v) = mem_before(call.get_previous_instruction(), blk, &(b, o + off), g, cfg, module, memo, depth, &mut seen) {
                                return done(v);
                            }
                        }
                    }
                }
                Expr::Opaque("Load".into(), vec![])
            }
            Expr::Opaque(l, xs) if l == "@load" && xs.len() == 1 => {
                let a = fold_rich(derefs(&xs[0], call, g, cfg, module, memo, depth));
                // an address made only of resolved (caller-side) parts.
                let a = match caller_side(&a) { Some(c) => fold_rich(c), None => a };
                if let (Some(t), Some(blk)) = (addr_of(&a), call.get_parent().and_then(|bb| cfg.bidx(bb))) {
                    let mut seen = MemCtx::default();
                    if let Some(v) = mem_before(call.get_previous_instruction(), blk, &t, g, cfg, module, memo, depth, &mut seen) {
                        return done(v);
                    }
                }
                Expr::Opaque("@load".into(), vec![a])
            }
            Expr::Bin(op, a, b) => fold_rich(Expr::Bin(*op, Box::new(derefs(a, call, g, cfg, module, memo, depth)), Box::new(derefs(b, call, g, cfg, module, memo, depth)))),
            Expr::VecGet(a, b) => Expr::VecGet(Box::new(derefs(a, call, g, cfg, module, memo, depth)), Box::new(derefs(b, call, g, cfg, module, memo, depth))),
            Expr::Opaque(l, xs) => Expr::Opaque(l.clone(), xs.iter().map(|x| derefs(x, call, g, cfg, module, memo, depth)).collect()),
            other => other.clone(),
        }
    }
    // what `derefs` resolves is already over the CALLER's params: shielded from
    // the actuals substitution below (`subst` unwraps it).
    fn done(v: Expr) -> Expr {
        Expr::Opaque("@done".into(), vec![v])
    }
    /// `e` with its `@done` parts unwrapped, if nothing outside them is still
    /// over the callee's params (else None).
    fn caller_side(e: &Expr) -> Option<Expr> {
        match e {
            Expr::Opaque(l, xs) if l == "@done" && xs.len() == 1 => Some(xs[0].clone()),
            Expr::Param(_) => None,
            Expr::Bin(o, a, b) => Some(Expr::Bin(*o, Box::new(caller_side(a)?), Box::new(caller_side(b)?))),
            Expr::VecGet(a, b) => Some(Expr::VecGet(Box::new(caller_side(a)?), Box::new(caller_side(b)?))),
            Expr::Opaque(l, xs) => Some(Expr::Opaque(l.clone(), xs.iter().map(caller_side).collect::<Option<_>>()?)),
            e => Some(e.clone()),
        }
    }
    let e = prefix_at(&derefs(e, call, g, cfg, module, memo, depth), local_ordinal(g, call));
    let nargs = call.get_num_operands().saturating_sub(1);
    let actuals: Vec<Expr> = (0..nargs)
        .map(|j| match call.get_operand(j) {
            Some(Operand::Value(x)) => value_expr(x, g, module, memo, depth),
            _ => Expr::Opaque("?".into(), vec![]),
        })
        .collect();
    fold_rich(subst(&e, &actuals))
}

/// A rustc/compiler-rt i128 arithmetic routine, `f(out, a_lo, a_hi, b_lo, b_hi
/// [, overflow_out])` writing `a op b` to `*out`, recognized by structure: pure
/// (no calls but LLVM intrinsics), all-integer params, and `udiv`/`urem` ⇒ the
/// division routine (`__divti3`), else `mul` ⇒ the (checked) multiply.
fn i128_arith_helper(h: FunctionValue) -> Option<char> {
    let n = h.count_params();
    if !(n == 5 || n == 6) || !h.get_params().iter().all(|p| p.is_int_value()) {
        return None;
    }
    let ins = all_instrs(h);
    let pure = ins.iter().all(|i| {
        i.get_opcode() != InstructionOpcode::Call || callee_name(*i).map_or(false, |c| c.starts_with("llvm."))
    });
    if !pure {
        return None;
    }
    let has = |op| ins.iter().any(|i| i.get_opcode() == op);
    if has(InstructionOpcode::UDiv) || has(InstructionOpcode::URem) {
        Some('/')
    } else if has(InstructionOpcode::Mul) {
        Some('*')
    } else {
        None
    }
}

/// An out-pointer load from an i128 arithmetic helper call: the result limbs
/// (offset 0 = lo, 8 = hi) both denote `a op b`, with each operand's value
/// carried by its lo limb.
#[allow(clippy::too_many_arguments)]
fn arith_out<'c>(
    call: InstructionValue<'c>,
    h: FunctionValue<'c>,
    k: u32,
    delta: i64,
    g: FunctionValue<'c>,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
    depth: u32,
) -> Option<Expr> {
    let op = i128_arith_helper(h)?;
    if k != 0 || !(delta == 0 || delta == 8) {
        return None;
    }
    let arg = |j: u32, memo: &mut HashMap<String, Option<Expr>>| match call.get_operand(j) {
        Some(Operand::Value(x)) => value_expr(x, g, module, memo, depth),
        _ => Expr::Opaque("?".into(), vec![]),
    };
    let a = arg(1, memo);
    let b = arg(3, memo);
    Some(Expr::Bin(op, Box::new(a), Box::new(b)))
}

/// Does `f` build a Symbol from linear memory — directly, or via a helper that
/// does (the SDK's `Symbol::new` / small-symbol packing helper)?
fn builds_symbol(f: FunctionValue) -> bool {
    all_instrs(f).iter().any(|i| {
        callee_has(*i, "symbol_new_from_linear_memory")
            || inkwell::values::CallSiteValue::try_from(*i).ok().and_then(|cs| cs.get_called_fn_value()).map_or(false, |h| {
                h.count_basic_blocks() > 0 && all_instrs(h).iter().any(|j| callee_has(*j, "symbol_new_from_linear_memory"))
            })
    })
}

/// Is `f` a contracttype-enum key builder (a `DataKey` → Val conversion): it
/// switches on the discriminant and each case builds the variant's Symbol. It
/// takes the enum either as `(discriminant, field)` integers or by pointer.
fn is_datakey_builder(f: FunctionValue) -> bool {
    f.count_basic_blocks() > 0 && !f.get_params().is_empty() && !kb_cases(f).is_empty() && builds_symbol(f)
}

/// Does builder `kb` take the enum BY POINTER (it dispatches on a value loaded
/// through its param) rather than as an integer discriminant?
fn kb_by_pointer(kb: FunctionValue) -> bool {
    let Some(p0) = kb.get_nth_param(0) else { return false };
    let pb = fmt(p0);
    all_instrs(kb).into_iter().any(|i| i.get_opcode() == InstructionOpcode::Switch
        && matches!(i.get_operand(0), Some(Operand::Value(v)) if as_instr(v).is_some_and(|l| l.get_opcode() == InstructionOpcode::Load
            && matches!(l.get_operand(0), Some(Operand::Value(p)) if ptr_base_off(p).0 == pb))))
}

/// A storage key, kept symbolic: `@key(disc, field, @kb:<builder>)` when it is
/// built by a DataKey builder — so a caller's constant discriminant can name the
/// slot after substitution — else the plain reconstruction. A builder that takes
/// the enum by pointer gets its discriminant / field read from memory at the call.
fn key_expr<'c>(
    k: BasicValueEnum<'c>,
    g: FunctionValue<'c>,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
    depth: u32,
) -> Expr {
    let mut cur = k;
    for _ in 0..8 {
        let Some(i) = as_instr(cur) else { break };
        let Some(n) = callee_name(i) else { break };
        if is_wrapper(&n) || n.contains("from_payload") || n.contains("val.payload") {
            if let Some(Operand::Value(x)) = i.get_operand(0) {
                cur = x;
                continue;
            }
            break;
        }
        if let Some(b) = module.get_function(&n) {
            if is_datakey_builder(b) {
                let kb = Expr::Opaque(format!("@kb:{n}"), vec![]);
                let arg = |j: u32| match i.get_operand(j) { Some(Operand::Value(x)) => Some(x), _ => None };
                // by pointer: the enum lives in memory (discriminant, then payload).
                if kb_by_pointer(b) {
                    if let Some(a) = arg(0) {
                        let (base, o) = if a.is_pointer_value() { ptr_base_off(a) } else { addr_base_off(a) };
                        let cfg = Cfg::build(g);
                        if let Some(blk) = i.get_parent().and_then(|bb| cfg.bidx(bb)) {
                            // the enum in our caller's memory (through our pointer param),
                            // or a constant one in the data section.
                            let pj = (0..g.count_params()).find(|&q| g.get_nth_param(q).map(fmt) == Some(base.clone()));
                            let konst = match a { BasicValueEnum::IntValue(c) => c.get_zero_extended_constant(), _ => None };
                            let segs = rodata_segs(module);
                            let rd = |off: i64, memo: &mut HashMap<String, Option<Expr>>| {
                                if let Some(addr) = konst {
                                    return rodata_u32(&segs, addr + (off - o) as u64).map_or(Expr::Opaque("?".into(), vec![]), |d| Expr::Const(d as i64));
                                }
                                let mut seen = MemCtx::default();
                                mem_before(i.get_previous_instruction(), blk, &(base.clone(), off), g, &cfg, module, memo, depth, &mut seen)
                                    .or_else(|| pj.map(|j| Expr::Opaque("@deref".into(), vec![Expr::Param(j as usize), Expr::Const(off)])))
                                    .unwrap_or(Expr::Opaque("?".into(), vec![]))
                            };
                            let d = rd(o, memo);
                            let fld = rd(o + 8, memo);
                            // each variant's full payload (`Minter(contract, minter)`),
                            // as `@case:<disc>(fields…)`, read at this call.
                            let mut v = vec![d, fld, kb];
                            for (disc, cb) in kb_cases(b) {
                                if let Some(fs) = kb_case_fields(b, cb, module, memo, depth) {
                                    let fs: Vec<Expr> = fs.iter().map(|e| subst_call(e, i, g, &cfg, module, memo, depth)).collect();
                                    v.push(Expr::Opaque(format!("@case:{}", disc.map_or("*".into(), |d| d.to_string())), fs));
                                }
                            }
                            return Expr::Opaque("@key".into(), v);
                        }
                    }
                }
                let mut v = |j: u32| match arg(j) {
                    Some(x) => value_expr(x, g, module, memo, depth),
                    None => Expr::Opaque("?".into(), vec![]),
                };
                return Expr::Opaque("@key".into(), vec![v(0), v(1), kb]);
            }
        }
        break;
    }
    value_expr(k, g, module, memo, depth)
}

/// The switch cases of a pointer-taking DataKey builder `kb`: (discriminant, or
/// None for the default, case block).
fn kb_cases(kb: FunctionValue) -> Vec<(Option<i64>, BasicBlock)> {
    let Some(sw) = all_instrs(kb).into_iter().find(|i| i.get_opcode() == InstructionOpcode::Switch) else {
        // a two-variant enum: `if disc & 1 == 0 { A } else { B }` on the entry.
        let Some(br) = kb.get_first_basic_block().and_then(|b| b.get_terminator()) else { return vec![] };
        let (Some(Operand::Value(c)), Some(Operand::Block(f)), Some(Operand::Block(t))) = (br.get_operand(0), br.get_operand(1), br.get_operand(2)) else { return vec![] };
        let Some(cmp) = as_instr(c).filter(|i| i.get_opcode() == InstructionOpcode::ICmp) else { return vec![] };
        let and = match (cmp.get_operand(0), cmp.get_operand(1)) {
            (Some(Operand::Value(a)), Some(Operand::Value(BasicValueEnum::IntValue(z)))) if z.get_zero_extended_constant() == Some(0) => as_instr(a),
            _ => None,
        };
        let is_bit = and.is_some_and(|a| {
            a.get_opcode() == InstructionOpcode::And
                && matches!(a.get_operand(1), Some(Operand::Value(BasicValueEnum::IntValue(k))) if k.get_zero_extended_constant() == Some(1))
                && matches!(a.get_operand(0), Some(Operand::Value(p)) if param_index(p, kb).is_some())
        });
        return match (is_bit, cmp.get_icmp_predicate()) {
            // LLVM lays a conditional branch out as [cond, false, true].
            (true, Some(inkwell::IntPredicate::EQ)) => vec![(Some(0), t), (Some(1), f)],
            (true, Some(inkwell::IntPredicate::NE)) => vec![(Some(0), f), (Some(1), t)],
            _ => vec![],
        };
    };
    let mut out = vec![];
    if let Some(Operand::Block(db)) = sw.get_operand(1) {
        out.push((None, db));
    }
    let mut k = 2; // switch operands: 0=cond, 1=default, then (value, block) pairs.
    while k + 1 < sw.get_num_operands() {
        if let (Some(Operand::Value(BasicValueEnum::IntValue(c))), Some(Operand::Block(b))) = (sw.get_operand(k), sw.get_operand(k + 1)) {
            if let Some(d) = c.get_sign_extended_constant() {
                out.push((Some(d), b));
            }
        }
        k += 2;
    }
    out
}

/// The payload of the key Vec `[Symbol(variant), fields…]` that builder `kb`
/// builds in the case starting at block `case`: the fields, in Vec order, over
/// `kb`'s params — memory resolved along that case's paths only.
fn kb_case_fields<'c>(
    kb: FunctionValue<'c>,
    case: BasicBlock<'c>,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
    depth: u32,
) -> Option<Vec<Expr>> {
    let cfg = Cfg::build(kb);
    let start = cfg.bidx(case)?;
    // the case's blocks: everything reachable from it, plus what reaches it.
    let mut allow: HashSet<usize> = HashSet::new();
    let mut work = vec![start];
    while let Some(b) = work.pop() {
        if allow.insert(b) {
            work.extend(cfg.succ[b].iter().copied());
        }
    }
    let mut work: Vec<usize> = (0..cfg.blocks.len()).filter(|&u| cfg.succ[u].contains(&start)).collect();
    while let Some(b) = work.pop() {
        if allow.insert(b) {
            work.extend((0..cfg.blocks.len()).filter(|&u| cfg.succ[u].contains(&b)));
        }
    }
    let pick = |v: BasicValueEnum<'c>| -> BasicValueEnum<'c> {
        let Some(phi) = as_instr(v).and_then(|i| inkwell::values::PhiValue::try_from(i).ok()) else { return v };
        let ins: Vec<BasicValueEnum> = (0..phi.count_incoming())
            .filter_map(|k| phi.get_incoming(k))
            .filter(|(_, b)| cfg.bidx(*b).is_some_and(|b| allow.contains(&b)))
            .map(|(x, _)| x)
            .collect();
        if ins.len() == 1 { ins[0] } else { v }
    };
    let vec = allow
        .iter()
        .flat_map(|&b| cfg.blocks[b].get_instructions())
        .find(|i| callee_has(*i, "vec_new_from_linear_memory"))?;
    let op = |k: u32| match vec.get_operand(k) { Some(Operand::Value(x)) => Some(x), _ => None };
    let len = u32_val_in(op(1)?, &pick)?;
    let at = val_addr_in(op(0)?, &pick)?;
    let blk = cfg.bidx(vec.get_parent()?)?;
    (1..len as i64)
        .map(|k| {
            let mut seen = MemCtx { allow: Some(allow.clone()), ..Default::default() };
            mem_before(vec.get_previous_instruction(), blk, &(at.0.clone(), at.1 + 8 * k), kb, &cfg, module, memo, depth, &mut seen)
        })
        .collect()
}

/// For a DataKey builder `kb`, which discriminants are data variants (carry a
/// field): an integer builder uses its field param in that case; a pointer
/// builder reads the enum's payload (offset ≥ 8 off its pointer) in that case.
fn kb_usage(kb: FunctionValue) -> (BTreeMap<i64, bool>, bool) {
    if kb.count_params() >= 2 {
        return kb_field_usage(kb);
    }
    let mut cases: BTreeMap<i64, bool> = BTreeMap::new();
    let Some(p0) = kb.get_nth_param(0) else { return (cases, false) };
    let pbase = fmt(p0);
    let Some(sw) = all_instrs(kb).into_iter().find(|i| i.get_opcode() == InstructionOpcode::Switch) else {
        return (cases, false);
    };
    let cfg = Cfg::build(kb);
    let reads_field = |start: usize| -> bool {
        // within the case: follow forward until a block reached from >1 case.
        let mut seen = vec![false; cfg.blocks.len()];
        let mut work = vec![start];
        while let Some(b) = work.pop() {
            if std::mem::replace(&mut seen[b], true) {
                continue;
            }
            for i in cfg.blocks[b].get_instructions() {
                if i.get_opcode() == InstructionOpcode::Load {
                    if let Some(Operand::Value(pp)) = i.get_operand(0) {
                        let (bs, o) = ptr_base_off(pp);
                        if bs == pbase && o >= 8 {
                            return true;
                        }
                    }
                }
            }
            for &n in &cfg.succ[b] {
                let preds = (0..cfg.succ.len()).filter(|&u| cfg.succ[u].contains(&n)).count();
                if preds == 1 {
                    work.push(n);
                }
            }
        }
        false
    };
    let n = sw.get_num_operands();
    let mut k = 2;
    let mut dflt = false;
    if let Some(Operand::Block(db)) = sw.get_operand(1) {
        if let Some(d) = cfg.bidx(db) {
            dflt = reads_field(d);
        }
    }
    while k + 1 < n {
        if let (Some(Operand::Value(BasicValueEnum::IntValue(c))), Some(Operand::Block(b))) = (sw.get_operand(k), sw.get_operand(k + 1)) {
            if let (Some(v), Some(bi)) = (c.get_sign_extended_constant(), cfg.bidx(b)) {
                cases.insert(v, reads_field(bi));
            }
        }
        k += 2;
    }
    (cases, dflt)
}

/// After reconstruction + substitution: turn each `@slot(@key(d, field))` with a
/// constant discriminant into the named slot — `Slot(Name, 0)` for a unit
/// variant, `@map:Name(field)` for a mapping — using the DataKey names from the
/// data section. Unresolved keys are left as they are.
fn name_slots<'c>(
    e: &Expr,
    module: &inkwell::module::Module<'c>,
    kb: Option<(FunctionValue<'c>, &(BTreeMap<i64, bool>, bool))>,
    segs: &[(u64, Vec<u8>)],
) -> Expr {
    let r = name_slots_raw(e, module, kb, segs);
    // remember which named keys live in temporary storage (they can expire).
    if let (Expr::Opaque(l, _), true) = (e, rich()) {
        if let Some(dur) = l.strip_prefix("@slot:") {
            let name = match &r {
                Expr::Slot(n, _) => Some(n.clone()),
                Expr::Opaque(m, _) => m.strip_prefix("@map:").or_else(|| m.strip_prefix("@tup:")).map(String::from),
                _ => None,
            };
            if let Some(n) = name {
                DURABILITY.with(|d| { d.borrow_mut().insert(n, dur.to_string()); });
            }
        }
    }
    r
}

thread_local! {
    /// Each named storage key's durability (`instance`, `persistent`, `temporary`).
    static DURABILITY: std::cell::RefCell<BTreeMap<String, String>> = const { std::cell::RefCell::new(BTreeMap::new()) };
}

fn name_slots_raw<'c>(
    e: &Expr,
    module: &inkwell::module::Module<'c>,
    kb: Option<(FunctionValue<'c>, &(BTreeMap<i64, bool>, bool))>,
    segs: &[(u64, Vec<u8>)],
) -> Expr {
    let rec = |x: &Expr| name_slots(x, module, kb, segs);
    match e {
        Expr::Opaque(l, xs) if l.starts_with("@slot:") && (xs.len() == 1 || xs.len() == 2) => {
            let tag = xs.get(1).cloned(); // the read's program point (@at), if any
            let tagn = match &tag {
                Some(Expr::Opaque(a, k)) if a == "@at" => match k.first() { Some(Expr::Const(t)) => *t as usize + 1, _ => 0 },
                _ => 0,
            };
            // the builder this key came from (a contract can have several).
            let own_kb = match &xs[0] {
                Expr::Opaque(kl, kx) if kl == "@key" && kx.len() >= 3 => match &kx[2] {
                    Expr::Opaque(n, _) if n.starts_with("@kb:") => module.get_function(&n["@kb:".len()..]),
                    _ => None,
                },
                _ => None,
            };
            let own_usage = own_kb.map(kb_usage);
            let kb = match (own_kb, own_usage.as_ref()) { (Some(f), Some(u)) => Some((f, u)), _ => kb };
            if let (Expr::Opaque(kl, kx), Some((kbf, usage))) = (&xs[0], kb) {
                // a key whose discriminant is chosen by a condition: the slot is too.
                if kl == "@key" && kx.len() >= 2 {
                    let mk = |d: &Expr| {
                        let mut v = vec![Expr::Opaque("@key".into(), {
                            let mut kv = vec![d.clone()];
                            kv.extend(kx[1..].iter().cloned());
                            kv
                        })];
                        v.extend(tag.clone());
                        Expr::Opaque(l.clone(), v)
                    };
                    if let Expr::Opaque(sl, sx) = &kx[0] {
                        if sl == "Select" && sx.len() == 3 {
                            return Expr::Opaque("Select".into(), vec![rec(&sx[0]), rec(&mk(&sx[1])), rec(&mk(&sx[2]))]);
                        }
                    }
                    // a discriminant computed from one decoded bool: evaluate both cases.
                    if !matches!(kx[0], Expr::Const(_)) {
                        if let Some(b) = sole_bool(&kx[0]) {
                            if let (Some(d0), Some(d1)) = (eval_bool_fn(&kx[0], &b, 0), eval_bool_fn(&kx[0], &b, 1)) {
                                let cond = Expr::Opaque("@isfalse".into(), vec![b.clone()]);
                                return Expr::Opaque("Select".into(), vec![cond, rec(&mk(&Expr::Const(d0))), rec(&mk(&Expr::Const(d1)))]);
                            }
                        }
                    }
                }
                if kl == "@key" && kx.len() >= 2 {
                    if let Expr::Const(d) = kx[0] {
                        if let Some(name) = datakey_name(kbf, d, module, segs) {
                            // the variant's full payload, when the builder's case was read.
                            let case = |c: &str| kx.iter().skip(3).find_map(|x| match x {
                                Expr::Opaque(l, fs) if l.strip_prefix("@case:") == Some(c) => Some(fs.clone()),
                                _ => None,
                            });
                            if let Some(fs) = case(&d.to_string()).or_else(|| case("*")) {
                                return match fs.len() {
                                    0 => Expr::Slot(name, tagn),
                                    1 => Expr::Opaque(format!("@map:{name}"), std::iter::once(rec(&fs[0])).chain(tag.clone()).collect()),
                                    _ => Expr::Opaque(format!("@tup:{name}"), vec![Expr::Opaque("@ks".into(), fs.iter().map(rec).collect())].into_iter().chain(tag.clone()).collect()),
                                };
                            }
                            let mapping = usage.0.get(&d).copied().unwrap_or(usage.1);
                            return if mapping {
                                let mut v = vec![rec(&kx[1])];
                                v.extend(tag.clone());
                                Expr::Opaque(format!("@map:{name}"), v)
                            } else {
                                Expr::Slot(name, tagn)
                            };
                        }
                    }
                }
            }
            // a key built inline: a bare Symbol (`symbol_short!("COUNTER")`) or
            // `Vec[Symbol(variant), fields…]` (a contracttype enum variant).
            let sym_name = |e: &Expr| -> Option<String> {
                match e {
                    Expr::Const(k) if (*k as u64) & 0xff == 14 => decode_symbol(*k as u64),
                    Expr::Opaque(n, v) if n.starts_with("@sym:") && v.is_empty() => Some(n["@sym:".len()..].to_string()),
                    _ => None,
                }
            };
            if let Some(name) = sym_name(&xs[0]) {
                return Expr::Slot(name, tagn);
            }
            if let Expr::Opaque(vl, els) = &xs[0] {
                if vl == "@vec" && !els.is_empty() {
                    if let Some(name) = sym_name(&els[0]) {
                        if els.len() == 1 {
                            return Expr::Slot(name, tagn);
                        }
                        if els.len() > 2 {
                            let ks = Expr::Opaque("@ks".into(), els[1..].iter().map(rec).collect());
                            return Expr::Opaque(format!("@tup:{name}"), std::iter::once(ks).chain(tag.clone()).collect());
                        }
                        let mut v = vec![rec(&els[1])];
                        v.extend(tag.clone());
                        return Expr::Opaque(format!("@map:{name}"), v);
                    }
                }
            }
            Expr::Opaque(l.clone(), xs.iter().map(rec).collect())
        }
        Expr::Bin(o, a, b) => fold_named(Expr::Bin(*o, Box::new(rec(a)), Box::new(rec(b)))),
        Expr::VecGet(a, b) => Expr::VecGet(Box::new(rec(a)), Box::new(rec(b))),
        Expr::Opaque(l, xs) => fold_named(Expr::Opaque(l.clone(), xs.iter().map(rec).collect())),
        other => other.clone(),
    }
}

/// When the returned Val is a decision tree over constants (a `Result<_, Error>`
/// lowered to `Void` / `Error(code)` payloads), the condition under which the call
/// returns Ok — an `Err` return fails the invocation like a panic. None when the
/// return isn't such a tree or can never be an error.
fn ok_condition(e: &Expr) -> Option<Expr> {
    fn ok(e: &Expr) -> Option<Expr> {
        match e {
            Expr::Const(k) => Some(Expr::Opaque(if k & 0xff == 3 { "@false" } else { "@true" }.into(), vec![])),
            Expr::Opaque(l, xs) if l == "Select" && xs.len() == 3 => {
                let (c, a, b) = (&xs[0], ok(&xs[1])?, ok(&xs[2])?);
                let is = |x: &Expr, n: &str| matches!(x, Expr::Opaque(l, v) if l == n && v.is_empty());
                let and = |p: Expr, q: Expr| if is(&q, "@true") { p } else if is(&q, "@false") { q } else { Expr::Opaque("@and".into(), vec![p, q]) };
                let nc = Expr::Opaque("@not".into(), vec![c.clone()]);
                let l = and(c.clone(), a);
                let r = and(nc, b);
                Some(if is(&l, "@false") { r } else if is(&r, "@false") { l } else { Expr::Opaque("@or".into(), vec![l, r]) })
            }
            _ => None,
        }
    }
    let has_err = |e: &Expr| -> bool {
        fn go(e: &Expr) -> bool {
            match e {
                Expr::Const(k) => k & 0xff == 3,
                Expr::Opaque(l, xs) if l == "Select" => xs.iter().skip(1).any(go),
                _ => false,
            }
        }
        go(e)
    };
    if !has_err(e) {
        return None;
    }
    ok(e)
}

/// A Val read straight from a source (a storage slot / map entry / an arg).
fn is_val_source(e: &Expr) -> bool {
    match e {
        Expr::Slot(..) | Expr::Param(_) => true,
        Expr::Opaque(l, _) => ["@map:", "@field:", "@tup:", "@env:", "@len"].iter().any(|p| l.starts_with(p)),
        // `has(k) ? get(k) : 0` of such a source
        _ => false,
    }
}

/// The single decoded bool (`@bool(x)`) an expression depends on, if exactly one.
fn sole_bool(e: &Expr) -> Option<Expr> {
    fn go(e: &Expr, out: &mut Vec<Expr>) -> bool {
        match e {
            Expr::Opaque(l, xs) if l == "@bool" && xs.len() == 1 => {
                if !out.contains(&xs[0]) {
                    out.push(xs[0].clone());
                }
                true
            }
            Expr::Const(_) => true,
            Expr::Bin(_, a, b) => go(a, out) && go(b, out),
            Expr::Opaque(l, xs) if matches!(l.as_str(), "And" | "Or" | "Xor") => xs.iter().all(|x| go(x, out)),
            _ => false, // depends on something else
        }
    }
    let mut v = vec![];
    (go(e, &mut v) && v.len() == 1).then(|| v.pop().unwrap())
}

/// Evaluate an expression over one decoded bool `b` set to `bit`.
fn eval_bool_fn(e: &Expr, b: &Expr, bit: i64) -> Option<i64> {
    let r = |x: &Expr| eval_bool_fn(x, b, bit);
    match e {
        Expr::Const(k) => Some(*k),
        Expr::Opaque(l, xs) if l == "@bool" && xs.len() == 1 && xs[0] == *b => Some(bit),
        Expr::Opaque(l, xs) if l == "And" && xs.len() == 2 => Some(r(&xs[0])? & r(&xs[1])?),
        Expr::Opaque(l, xs) if l == "Or" && xs.len() == 2 => Some(r(&xs[0])? | r(&xs[1])?),
        Expr::Opaque(l, xs) if l == "Xor" && xs.len() == 2 => Some(r(&xs[0])? ^ r(&xs[1])?),
        Expr::Bin('+', a, c) => Some(r(a)? + r(c)?),
        Expr::Bin('-', a, c) => Some(r(a)? - r(c)?),
        Expr::Bin('*', a, c) => Some(r(a)? * r(c)?),
        _ => None,
    }
}

/// Folds that need named slots: `Or(x, x)` is `x`; `Or(a, b) = 0` is
/// `a = 0 ∧ b = 0` (bitwise, exact); Val encode/decode of named sources. A
/// `get(k).unwrap_or(0)` (`has(k) ? get(k) : 0`) stays as it is — the model does
/// not assume an absent key holds 0 (it renders as `getOr0`).
fn fold_named(e: Expr) -> Expr {
    // u32/i32 small-Val ENCODE: (v << 32) + ((k << 32) | tag) is v + k, tag 4/5.
    if let Expr::Bin('+', a, b) = &e {
        if let (Expr::Opaque(sl, sx), Expr::Const(c)) = (a.as_ref(), b.as_ref()) {
            if sl == "Shl" && sx.len() == 2 && sx[1] == Expr::Const(32) && matches!(c & 0xff, 4 | 5) {
                let k = c >> 32;
                return if k == 0 { sx[0].clone() } else { Expr::Bin('+', Box::new(sx[0].clone()), Box::new(Expr::Const(k))) };
            }
        }
    }
    if let Expr::Opaque(ol, ox) = &e {
        if ol == "Or" && ox.len() == 2 {
            if let (Expr::Opaque(sl, sx), Expr::Const(c)) = (&ox[0], &ox[1]) {
                if sl == "Shl" && sx.len() == 2 && sx[1] == Expr::Const(32) && matches!(c & 0xff, 4 | 5) && c >> 32 == 0 {
                    return sx[0].clone();
                }
            }
        }
    }
    // a 0/1 flag `Select(c, a, b)` (consts): `& 1` keeps it; `== k` is `c` / `¬c`.
    let flag = |x: &Expr| matches!(x, Expr::Opaque(s, v) if s == "Select" && v.len() == 3
        && matches!((&v[1], &v[2]), (Expr::Const(a), Expr::Const(b)) if a != b && (0..=1).contains(a) && (0..=1).contains(b)));
    match &e {
        Expr::Opaque(l, xs) if l == "And" && xs.len() == 2 && xs[1] == Expr::Const(1) && flag(&xs[0]) => return xs[0].clone(),
        // `c ? c : false` (an i128 `== 0` from two limb tests that fold alike) is `c`.
        Expr::Opaque(l, xs) if l == "Select" && xs.len() == 3 && xs[0] == xs[1] && xs[2] == Expr::Const(0) => return xs[0].clone(),
        Expr::Opaque(l, xs) if (l == "ICmp_EQ" || l == "ICmp_NE") && xs.len() == 2 && flag(&xs[0]) && matches!(xs[1], Expr::Const(_)) => {
            let Expr::Opaque(_, v) = &xs[0] else { unreachable!() };
            let not = |c: &Expr| match c { Expr::Opaque(n, i) if n == "@not" && i.len() == 1 => i[0].clone(), c => Expr::Opaque("@not".into(), vec![c.clone()]) };
            let eq = if v[1] == xs[1] { v[0].clone() } else if v[2] == xs[1] { not(&v[0]) } else { return e };
            return fold_named(if l == "ICmp_EQ" { eq } else { not(&eq) });
        }
        _ => {}
    }
    match &e {
        Expr::Opaque(l, xs) if l == "Or" && xs.len() == 2 && xs[0] == xs[1] => xs[0].clone(),
        // decode through `c ? v : 0` (an `unwrap_or(0)` of a u32): `c ? (v >> 32) : 0`.
        Expr::Opaque(l, xs) if l == "LShr" && xs.len() == 2 && xs[1] == Expr::Const(32)
            && matches!(&xs[0], Expr::Opaque(s, v) if s == "Select" && v.len() == 3 && v[2] == Expr::Const(0)) =>
        {
            let Expr::Opaque(_, v) = &xs[0] else { unreachable!() };
            let dec = fold_named(Expr::Opaque("LShr".into(), vec![v[1].clone(), Expr::Const(32)]));
            Expr::Opaque("Select".into(), vec![v[0].clone(), dec, Expr::Const(0)])
        }
        // u32/i32 small-Val DECODE of a Val source: `payload >> 32` is the value.
        Expr::Opaque(l, xs) if l == "LShr" && xs.len() == 2 && xs[1] == Expr::Const(32) && is_val_source(&xs[0]) => xs[0].clone(),
        Expr::Opaque(l, xs) if l == "ICmp_EQ" && xs.len() == 2 && xs[1] == Expr::Const(0) => {
            if let Expr::Opaque(o, ab) = &xs[0] {
                if o == "Or" && ab.len() == 2 {
                    let z = |x: &Expr| fold_named(Expr::Opaque("ICmp_EQ".into(), vec![x.clone(), Expr::Const(0)]));
                    let parts: Vec<Expr> = ab.iter().map(z).flat_map(|p| match p {
                        Expr::Opaque(n, v) if n == "@and" => v,
                        p => vec![p],
                    }).collect();
                    let mut uniq: Vec<Expr> = vec![];
                    for p in parts {
                        if !uniq.contains(&p) {
                            uniq.push(p);
                        }
                    }
                    return if uniq.len() == 1 { uniq.pop().unwrap() } else { Expr::Opaque("@and".into(), uniq) };
                }
            }
            e
        }
        _ => e,
    }
}

thread_local! {
    static WRITE_OFFS: std::cell::RefCell<HashMap<(String, usize), Option<Vec<(i64, i64)>>>> =
        std::cell::RefCell::new(HashMap::new());
}

/// The byte ranges `(offset, size)` callee `h` writes through its pointer param
/// `k` (directly or through helpers it forwards the pointer to); `None` when
/// unknown (a body-less callee, or a store whose address isn't param+constant).
fn callee_write_offsets(h: FunctionValue, k: usize, fuel: u32) -> Option<Vec<(i64, i64)>> {
    let key = (h.get_name().to_string_lossy().into_owned(), k);
    if let Some(r) = WRITE_OFFS.with(|m| m.borrow().get(&key).cloned()) {
        return r;
    }
    WRITE_OFFS.with(|m| m.borrow_mut().insert(key.clone(), None)); // recursion guard
    let r = (|| {
        if fuel == 0 || h.count_basic_blocks() == 0 {
            return None;
        }
        let pbase = fmt(h.get_nth_param(k as u32)?);
        let mut out = vec![];
        for i in all_instrs(h) {
            match i.get_opcode() {
                InstructionOpcode::Store => {
                    let Some(Operand::Value(sp)) = i.get_operand(1) else { continue };
                    let (b, o) = ptr_base_off(sp);
                    let other_param = h.get_params().iter().any(|q| fmt(*q) == b);
                    let global = sp.is_pointer_value() && sp.into_pointer_value().as_instruction().is_none() && !h.get_params().iter().any(|q| fmt(*q) == fmt(sp));
                    if b == pbase {
                        let size = match i.get_operand(0) {
                            Some(Operand::Value(BasicValueEnum::IntValue(v))) => (v.get_type().get_bit_width() as i64 + 7) / 8,
                            _ => 8,
                        };
                        out.push((o, size));
                    } else if !ptr_is_clean(sp) && !other_param && !global {
                        return None; // a store we can't attribute: it may be through our pointer
                    }
                }
                InstructionOpcode::Call => {
                    if let Some(d) = linmem_dest(i) {
                        match d {
                            Some(((b, o), len)) if b == pbase => out.push((o, len)),
                            Some(_) => {}
                            None => return None,
                        }
                        continue;
                    }
                    let nargs = i.get_num_operands().saturating_sub(1);
                    for j in 0..nargs {
                        let Some(Operand::Value(a)) = i.get_operand(j) else { continue };
                        let (b, o) = if a.is_pointer_value() { ptr_base_off(a) } else { addr_base_off(a) };
                        if b != pbase {
                            continue;
                        }
                        let h2 = inkwell::values::CallSiteValue::try_from(i).ok()?.get_called_fn_value()?;
                        for (w, sz) in callee_write_offsets(h2, j as usize, fuel - 1)? {
                            out.push((o + w, sz));
                        }
                    }
                }
                _ => {}
            }
        }
        Some(out)
    })();
    WRITE_OFFS.with(|m| m.borrow_mut().insert(key, r.clone()));
    r
}

/// What `*(param k + off)` holds when callee `h` returns, as an expression over
/// `h`'s params: the memory there at each (non-trapping) return, gated by the
/// exact condition of reaching it. A path that never writes it leaves the
/// caller's value (`@deref(Param k, off)`).
fn callee_store_at<'c>(
    h: FunctionValue<'c>,
    k: usize,
    off: i64,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
    depth: u32,
    fuel: u32,
) -> Option<Expr> {
    if fuel == 0 || depth == 0 {
        return None;
    }
    let target = (fmt(h.get_nth_param(k as u32)?), off);
    let cfg = Cfg::build(h);
    let mut arms: Vec<(usize, Expr)> = vec![];
    for (b, bb) in cfg.blocks.iter().enumerate() {
        let Some(t) = bb.get_terminator().filter(|t| t.get_opcode() == InstructionOpcode::Return) else { continue };
        let mut seen = MemCtx::default();
        arms.push((b, mem_before(Some(t), b, &target, h, &cfg, module, memo, depth - 1, &mut seen)?));
    }
    gate_by_reach(h, &cfg, arms, None, module, memo)
}

/// One value per block (each block's value at its end), as the value at the
/// point those blocks lead to: `Select(reach(b₁) [∧ edge b₁→join], v₁, …)` over
/// the exact path conditions; equal values merge. Unrenderable conditions make
/// it an (open) `phi`.
fn gate_by_reach<'c>(
    g: FunctionValue<'c>,
    cfg: &Cfg<'c>,
    arms: Vec<(usize, Expr)>,
    join: Option<usize>,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
) -> Option<Expr> {
    // each arm under the panic checks every path to it passed.
    let by_state = BY_STATE.with(|b| b.get());
    let arms: Vec<(usize, Expr)> = arms.into_iter().map(|(b, v)| {
        let fs = facts_at(g, cfg, b, module);
        let r = simplify_under(&v, &fs, false);
        (b, r)
    }).collect();
    BY_STATE.with(|b| b.set(by_state));
    let first = arms.first()?.1.clone();
    if arms.iter().all(|(_, v)| *v == first) {
        return Some(first);
    }
    let open = || Some(Expr::Opaque("phi".into(), arms.iter().map(|(_, v)| v.clone()).collect()));
    let mut rmemo = HashMap::new();
    let mut gated: Vec<(Expr, Expr)> = vec![];
    for (b, v) in &arms {
        let Some(ds) = reach_dnf(cfg, *b, &mut rmemo, &mut HashSet::new()) else { return open() };
        let Some(mut c) = dnf_expr(g, cfg, &ds, module, memo) else { return open() };
        if let Some(j) = join {
            if cfg.succ[*b].iter().filter(|&&s| !forces_trap(cfg.blocks[s], 6)).count() > 1 {
                let Some(e) = edge_cond(g, cfg, *b, j, module, memo) else { return open() };
                c = Expr::Opaque("@and".into(), vec![c, e]);
            }
        }
        gated.push((c, v.clone()));
    }
    let (_, mut acc) = gated.pop()?;
    while let Some((c, v)) = gated.pop() {
        if v != acc {
            acc = Expr::Opaque("Select".into(), vec![c, v, acc]);
        }
    }
    Some(acc)
}

/// Substitute a callee's param-relative expression with the caller's arg exprs.
fn subst(e: &Expr, actuals: &[Expr]) -> Expr {
    match e {
        Expr::Param(i) => actuals.get(*i).cloned().unwrap_or(Expr::Opaque("arg".into(), vec![])),
        Expr::Opaque(l, xs) if l == "@done" && xs.len() == 1 => xs[0].clone(),
        Expr::Bin(op, a, b) => Expr::Bin(*op, Box::new(subst(a, actuals)), Box::new(subst(b, actuals))),
        Expr::VecGet(h, i) => Expr::VecGet(Box::new(subst(h, actuals)), Box::new(subst(i, actuals))),
        Expr::Opaque(l, xs) => Expr::Opaque(l.clone(), xs.iter().map(|x| subst(x, actuals)).collect()),
        other => other.clone(),
    }
}

fn sanitize(s: &str) -> String {
    s.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '_' }).collect()
}

/// Transitive storage-write summary of `g`, as (slot, value-expr) over g's own
/// parameters. Descends `fastcc` helpers, substituting call-site args.
fn write_summary<'c>(
    g: FunctionValue<'c>,
    module: &inkwell::module::Module<'c>,
    wmemo: &mut HashMap<String, Vec<(String, usize, Expr)>>,
    vmemo: &mut HashMap<String, Option<Expr>>,
    depth: u32,
) -> Vec<(String, usize, Expr)> {
    let key = g.get_name().to_string_lossy().into_owned();
    if let Some(w) = wmemo.get(&key) {
        return w.clone();
    }
    wmemo.insert(key.clone(), vec![]);
    if depth == 0 {
        return vec![];
    }
    let gargs = arg_table(g);
    let mut out = vec![];
    for i in all_instrs(g) {
        if callee_has(i, "put_contract_data") {
            // put_contract_data(key, value, durability): dur is operand 2, key operand 0.
            let dur = match i.get_operand(2) {
                Some(Operand::Value(x)) => durability(x),
                _ => "?".into(),
            };
            let arity = match i.get_operand(0) {
                Some(Operand::Value(k)) => key_params(k, &gargs).len(),
                _ => 0,
            };
            let ve = match i.get_operand(1) {
                Some(Operand::Value(val)) => simplify(value_expr(val, g, module, vmemo, depth)),
                _ => Expr::Opaque("?".into(), vec![]),
            };
            out.push((dur, arity, ve));
            continue;
        }
        let Some(cn) = callee_name(i) else { continue };
        let Some(h) = module.get_function(&cn) else { continue };
        if h.count_basic_blocks() == 0 {
            continue;
        }
        let hs = write_summary(h, module, wmemo, vmemo, depth - 1);
        if hs.is_empty() {
            continue;
        }
        let actuals: Vec<Expr> = (0..i.get_num_operands().saturating_sub(1))
            .map(|k| match i.get_operand(k) {
                Some(Operand::Value(x)) => value_expr(x, g, module, vmemo, depth),
                _ => Expr::Opaque("?".into(), vec![]),
            })
            .collect();
        for (dur, arity, ve) in hs {
            out.push((dur, arity, subst(&ve, &actuals)));
        }
    }
    wmemo.insert(key, out.clone());
    out
}

/// `v & 0xffffffff` — the low 32-bit limb of v.
fn lo_limb(e: &Expr) -> Option<&Expr> {
    if let Expr::Opaque(l, xs) = e {
        if l == "And" && xs.len() == 2 && xs[1] == Expr::Const(4294967295) {
            return Some(&xs[0]);
        }
    }
    None
}
/// `v >> 32` — the high 32-bit limb of v.
fn hi_limb(e: &Expr) -> Option<&Expr> {
    if let Expr::Opaque(l, xs) = e {
        if l == "LShr" && xs.len() == 2 && xs[1] == Expr::Const(32) {
            return Some(&xs[0]);
        }
    }
    None
}

/// Either limb (low via `&mask`, or high via `>>32`) of a value.
fn limb_of(e: &Expr) -> Option<&Expr> {
    lo_limb(e).or_else(|| hi_limb(e))
}

/// Does an expr's tree mention an op whose label contains `needle`?
fn mentions(e: &Expr, needle: &str) -> bool {
    match e {
        Expr::Opaque(l, xs) => l.contains(needle) || xs.iter().any(|x| mentions(x, needle)),
        Expr::Bin(_, a, b) => mentions(a, needle) || mentions(b, needle),
        Expr::VecGet(h, i) => mentions(h, needle) || mentions(i, needle),
        _ => false,
    }
}

/// Collapse the 64-bit-multiply-from-32-bit-limbs idiom back to a Mul:
///   (lo A * hi B + hi A * lo B) << 32  +  lo A * lo B   ==>   A * B
/// (bottom-up), so a native i64 `y*dx` lowered to limb products reads as `y*dx`.
fn simplify(e: Expr) -> Expr {
    let e = match e {
        Expr::Bin(op, a, b) => Expr::Bin(op, Box::new(simplify(*a)), Box::new(simplify(*b))),
        Expr::VecGet(h, i) => Expr::VecGet(Box::new(simplify(*h)), Box::new(simplify(*i))),
        Expr::Opaque(l, xs) => Expr::Opaque(l, xs.into_iter().map(simplify).collect()),
        x => x,
    };
    // storage-present default: Select(has_contract_data?, present, 0) -> present.
    // Models the pool as initialized (the no-drain precondition), as the absent
    // branch is the 0-default a get-or-default returns.
    if let Expr::Opaque(l, xs) = &e {
        if l == "Select" && xs.len() == 3 && xs[2] == Expr::Const(0) && mentions(&xs[0], "has_contract_data") {
            return xs[1].clone();
        }
    }
    if let Expr::Bin('+', shl, low) = &e {
        if let (Expr::Opaque(sl, sx), Expr::Bin('*', la, lb)) = (&**shl, &**low) {
            if sl == "Shl" && sx.len() == 2 && sx[1] == Expr::Const(32) {
                if let (Some(a), Some(b)) = (lo_limb(la), lo_limb(lb)) {
                    // the low term is lo(a)*lo(b) and a <<32 cross term is present:
                    // the standard low-64-bits-of-(a*b) shape. Verify the cross term
                    // is built from the limbs of a and b (one hi, one lo each).
                    let cross_ok = |c: &Expr| matches!(c, Expr::Bin('*', m, n)
                        if {
                            let (lm, ln) = (limb_of(m), limb_of(n));
                            (lm == Some(a) && ln == Some(b)) || (lm == Some(b) && ln == Some(a))
                        });
                    let shl_ok = match &sx[0] {
                        Expr::Bin('+', c1, c2) => cross_ok(c1) && cross_ok(c2),
                        c => cross_ok(c),
                    };
                    if shl_ok {
                        return Expr::Bin('*', Box::new(a.clone()), Box::new(b.clone()));
                    }
                }
            }
        }
    }
    e
}

/// Render an Expr for humans, using the entry's arg names for Param.
fn render_expr(e: &Expr, args: &Args) -> String {
    match e {
        Expr::Param(i) => args.get(*i).map(|(_, n, _)| n.clone()).unwrap_or(format!("p{i}")),
        Expr::Slot(dur, ar) => format!("storage.{dur}/{ar}"),
        Expr::Const(k) => k.to_string(),
        Expr::Bin(op, a, b) => format!("({} {} {})", render_expr(a, args), op, render_expr(b, args)),
        Expr::VecGet(h, i) => format!("{}[{}]", render_expr(h, args), render_expr(i, args)),
        Expr::Opaque(l, xs) if xs.is_empty() => l.clone(),
        Expr::Opaque(l, xs) => {
            let inner: Vec<String> = xs.iter().map(|x| render_expr(x, args)).collect();
            format!("{l}({})", inner.join(", "))
        }
    }
}

/// How many arithmetic operators a recovered expr contains (recovery signal).
fn expr_ops(e: &Expr) -> usize {
    match e {
        Expr::Bin(_, a, b) => 1 + expr_ops(a) + expr_ops(b),
        Expr::VecGet(h, i) => expr_ops(h) + expr_ops(i),
        Expr::Opaque(_, xs) => xs.iter().map(expr_ops).sum(),
        _ => 0,
    }
}

/// Which conservation "party" a transfer endpoint maps to.
fn party(r: ARef) -> &'static str {
    match r {
        ARef::Contract => "pool",   // the AMM contract itself
        ARef::Param(_) => "ext",    // an external address arg (caller / destination)
        ARef::Other => "other",     // unresolved recipient (potential leak — flagged)
    }
}

/// One entrypoint's recovered shape, for the relational Lean model.
struct ModelEntry {
    name: String,
    args: Vec<(String, String)>, // (spec.name, spec.type) of the ABI args
    guards: Vec<Guard>,          // recovered panic guards (pass conditions)
    rich: RichBody,              // reconstructed effects, auths, Ok condition, return
}

/// Does block `b` unavoidably trap — it traps directly, or its terminator is an
/// UNCONDITIONAL branch to a block that forces a trap? (This is the `if bad {
/// panic }` target: a short forced path to `soroban.trap`, not a conditional
/// edge that merely *could* reach some downstream trap.)
fn forces_trap(b: BasicBlock, depth: u32) -> bool {
    let mut it = b.get_first_instruction();
    while let Some(i) = it {
        if i.get_opcode() == InstructionOpcode::Unreachable
            || callee_name(i).map_or(false, |n| n.contains("trap"))
        {
            return true;
        }
        it = i.get_next_instruction();
    }
    if depth == 0 {
        return false;
    }
    match b.get_terminator() {
        Some(t) => {
            let blocks: Vec<BasicBlock> = (0..t.get_num_operands())
                .filter_map(|k| match t.get_operand(k) {
                    Some(Operand::Block(nb)) => Some(nb),
                    _ => None,
                })
                .collect();
            blocks.len() == 1 && forces_trap(blocks[0], depth - 1)
        }
        None => false,
    }
}

// ===================== generic guard recovery =====================

/// The relation a branch condition encodes, as the two compared values: a plain
/// `icmp`, or the i128/i256 limb-compare idiom `select (icmp eq hi) cmplo cmphi`.
fn gate_vals(cond: BasicValueEnum) -> Option<(RelOp, BasicValueEnum, BasicValueEnum)> {
    use inkwell::IntPredicate::*;
    let pred = |p| match p {
        SLT | ULT => RelOp::Lt, SLE | ULE => RelOp::Le, SGT | UGT => RelOp::Gt,
        SGE | UGE => RelOp::Ge, EQ => RelOp::Eq, NE => RelOp::Ne,
    };
    let i = as_instr(cond)?;
    // the i128/i256 idiom `select (icmp eq hi) cmplo cmphi`: its DIRECTION is the
    // hi-limb comparison's predicate (`slt`⇒`<`, `sgt`⇒`>`, …), not always `<`.
    if i.get_opcode() == InstructionOpcode::Select {
        let hv = match i.get_operand(2) { Some(Operand::Value(v)) => v, _ => return None };
        let hi = as_instr(hv)?;
        if hi.get_opcode() != InstructionOpcode::ICmp {
            return None;
        }
        // …whose condition is `hi_a == hi_b` on the same limbs (else it is a plain
        // boolean `select`, e.g. a match on an enum choosing which test applies).
        let eq = match i.get_operand(0) { Some(Operand::Value(v)) => as_instr(v)?, _ => return None };
        fn ops(x: InstructionValue<'_>) -> [Option<BasicValueEnum<'_>>; 2] {
            [x.get_operand(0), x.get_operand(1)].map(|o| o.and_then(|o| o.value()))
        }
        let (e, h) = (ops(eq), ops(hi));
        if eq.get_icmp_predicate() != Some(EQ) || !(e == h || e == [h[1], h[0]]) {
            return None;
        }
        // operands from the LO-limb compare (the lo limb carries the value; the
        // hi limb drops carries, e.g. the `+ 1` of `q + 1`), direction from the
        // signed HI-limb compare.
        let lo = match i.get_operand(1) { Some(Operand::Value(v)) => as_instr(v), _ => None };
        // (the two limb compares may list their operands in opposite orders, so
        // the direction is taken from the same compare as the operands.)
        let src = match lo { Some(l) if l.get_opcode() == InstructionOpcode::ICmp => l, _ => hi };
        let a = match src.get_operand(0) { Some(Operand::Value(v)) => v, _ => return None };
        let b = match src.get_operand(1) { Some(Operand::Value(v)) => v, _ => return None };
        return Some((pred(src.get_icmp_predicate()?), a, b));
    }
    if i.get_opcode() == InstructionOpcode::ICmp {
        let a = match i.get_operand(0) { Some(Operand::Value(v)) => v, _ => return None };
        let b = match i.get_operand(1) { Some(Operand::Value(v)) => v, _ => return None };
        return Some((pred(i.get_icmp_predicate()?), a, b));
    }
    None
}


/// The MEANINGFUL trap (panic) guards of `f`, generically: every branch that
/// gates a panic, each side reconstructed as an expression over the call's
/// arguments and storage reads (via `value_expr`, the storage-write
/// reconstructor), keeping only guards that mention such a quantity. This drops
/// the low-level plumbing (Val tag checks, i128 sign/overflow checks, and the
/// uninterpreted arithmetic internals) that every entrypoint is full of.
fn entry_guards<'c>(f: FunctionValue<'c>, module: &inkwell::module::Module<'c>) -> GuardSet {
    CUR_ENTRY.with(|e| *e.borrow_mut() = f.get_name().to_string_lossy().chars().map(|c| if c.is_alphanumeric() { c } else { '_' }).collect());
    let cfg = Cfg::build(f);
    let args = arg_table(f);
    let structs = spec_structs(module);
    let kbf = datakey_builder(module);
    let usage = kbf.map(kb_field_usage);
    let kb = kbf.zip(usage.as_ref());
    let segs = rodata_segs(module);
    let fnid: String = f.get_name().to_string_lossy().chars()
        .map(|ch| if ch.is_alphanumeric() { ch } else { '_' }).collect();
    let mut vmemo: HashMap<String, Option<Expr>> = HashMap::new();
    let mut opmap: HashMap<String, String> = HashMap::new();
    let (mut oc, mut decls): (usize, Vec<String>) = (0, vec![]);
    let (mut gs, mut seen): (Vec<Guard>, HashSet<String>) = (vec![], HashSet::new());
    // A guard is a conditional branch one of whose immediate edges goes straight
    // to a panic (`if bad { panic }`). The PASS condition is the other edge's
    // value of the branch condition — polarity read from which edge panics, not
    // from any particular trap sink.
    for (bi, blk) in cfg.blocks.iter().enumerate() {
        let Some(term) = blk.get_terminator() else { continue };
        if term.get_opcode() != InstructionOpcode::Br {
            continue;
        }
        let Some(Operand::Value(cond)) = term.get_operand(0) else { continue };
        if !is_bool(cond) {
            continue; // unconditional branch
        }
        let succs = &cfg.succ[bi];
        if succs.len() != 2 {
            continue;
        }
        // LLVM lays conditional-branch block operands out as [cond, false, true],
        // so succs[0] is the FALSE target and succs[1] the TRUE target.
        let (false_traps, true_traps) =
            (forces_trap(cfg.blocks[succs[0]], 6), forces_trap(cfg.blocks[succs[1]], 6));
        let negate = match (true_traps, false_traps) {
            (true, false) => true,   // the true edge panics -> pass = ¬cond
            (false, true) => false,  // the false edge panics -> pass = cond
            _ => continue,           // both or neither: not a clean guard
        };
        EXCLUDE.with(|x| x.set(Some(bi)));
        // the guard binds only when its branch is reached: `reach → pass`. A
        // reach condition we can't render drops the guard (weaker, still sound).
        let pcs = with_rich(|| path_conds(f, &cfg, bi, module, &mut vmemo));
        let pc: Option<Vec<String>> = pcs
            .iter()
            .map(|c| match apply_facts(&assume_arg_types(&name_slots(c, module, kb, &segs), &args, &structs)) {
                Expr::Opaque(l, x) if l == "@not" && x.len() == 1 => lean_cond(&x[0], &args, &mut opmap, &mut oc, &mut decls, &fnid).map(|s| format!("¬({s})")),
                c => lean_cond(&c, &args, &mut opmap, &mut oc, &mut decls, &fnid),
            })
            .collect();
        let Some(pc) = pc else { continue };
        let first = gs.len();
        // split so each leaf is a conjunct of the PASS condition: ¬(a∨b)=¬a∧¬b
        // when negating, (a∧b) when keeping.
        let mut leaves = vec![];
        bool_split(cond, negate, 8, &mut leaves);
        for leaf in leaves {
            // a boolean `select c, a, b` (one test or another, chosen by c).
            if gate_vals(leaf).is_none() && as_instr(leaf).is_some_and(|i| i.get_opcode() == InstructionOpcode::Select) {
                let e = with_rich(|| fold_rich(simplify(value_expr(leaf, f, module, &mut vmemo, 40))));
                let e = apply_facts(&assume_arg_types(&name_slots(&e, module, kb, &segs), &args, &structs));
                if !expr_has_named(&e) || has_cycle(&e) {
                    continue;
                }
                let Some(c) = lean_cond(&e, &args, &mut opmap, &mut oc, &mut decls, &fnid) else { continue };
                let (comment, lean) = if negate { (format!("¬{}", render_expr(&e, &args)), format!("¬{c}")) } else { (render_expr(&e, &args), c) };
                if seen.insert(comment.clone()) {
                    gs.push(Guard { comment, lean });
                }
                continue;
            }
            let Some((op0, l, r)) = gate_vals(leaf) else { continue };
            let op = if negate { op0.negate() } else { op0 };
            if matches!(op, RelOp::Eq | RelOp::Ne) {
                // Val-tag / sign / overflow equality plumbing — but a presence test
                // (`if has(k) { panic }`) is a real guard.
                let has = with_rich(|| matches!(simplify(value_expr(l, f, module, &mut vmemo, 40)), Expr::Opaque(h, _) if h == "@has"));
                if !has {
                    continue;
                }
            }
            let (le, re) = with_rich(|| {
                (simplify(value_expr(l, f, module, &mut vmemo, 40)), simplify(value_expr(r, f, module, &mut vmemo, 40)))
            });
            let (le, re) = (apply_facts(&assume_arg_types(&name_slots(&le, module, kb, &segs), &args, &structs)), apply_facts(&assume_arg_types(&name_slots(&re, module, kb, &segs), &args, &structs)));
            if !(expr_has_named(&le) || expr_has_named(&re)) {
                continue;
            }
            // drop i128 signed-overflow checks: `And(Xor(a-b,a), Xor(a,b)) < 0`.
            let zm1 = |x: &Expr| matches!(x, Expr::Const(0) | Expr::Const(-1));
            if (zm1(&re) && (is_sub_overflow(&le) || is_ovf_flag(&le))) || (zm1(&le) && is_ovf_flag(&re)) {
                continue;
            }
            if has_cycle(&le) || has_cycle(&re) || has_label(&le, "llvm_") || has_label(&re, "llvm_") {
                continue;
            }
            let (le, re) = (i128_sext(&le), i128_sext(&re));
            if let Some((a, r, b)) = cmp_rel(&le, op.lean(), &re) {
                let comment = format!("{} {r} {}", render_expr(&a, &args), render_expr(&b, &args));
                if seen.insert(comment.clone()) {
                    let lean = format!("{} {r} {}", lean_guard_term(&a, &args, &mut opmap, &mut oc, &mut decls, &fnid), lean_guard_term(&b, &args, &mut opmap, &mut oc, &mut decls, &fnid));
                    gs.push(Guard { comment, lean });
                }
                continue;
            }
            if let Some((p, r, k)) = raw_small_cmp(&le, op.lean(), &re, &args) {
                let comment = format!("{} {r} {k}", render_expr(&p, &args));
                if seen.insert(comment.clone()) {
                    let lean = format!("{} {r} {k}", lean_guard_term(&p, &args, &mut opmap, &mut oc, &mut decls, &fnid));
                    gs.push(Guard { comment, lean });
                }
                continue;
            }
            let comment = format!("{} {} {}", render_expr(&le, &args), op.lean(), render_expr(&re, &args));
            if !seen.insert(comment.clone()) {
                continue;
            }
            let lean = format!(
                "{} {} {}",
                lean_guard_term(&le, &args, &mut opmap, &mut oc, &mut decls, &fnid),
                op.lean(),
                lean_guard_term(&re, &args, &mut opmap, &mut oc, &mut decls, &fnid),
            );
            gs.push(Guard { comment, lean });
        }
        if !pc.is_empty() {
            for g in &mut gs[first..] {
                g.lean = format!("(({}) → {})", pc.join(" ∧ "), g.lean);
                g.comment = format!("{}   [when {}]", g.comment, pc.join(" ∧ "));
            }
        }
    }
    EXCLUDE.with(|x| x.set(None));
    let _ = decls;
    GuardSet { guards: gs }
}

/// A recovered transition guard: its human-readable form and its Lean conjunct.
struct Guard { comment: String, lean: String }
struct GuardSet { guards: Vec<Guard> }

/// Split an i1 into conjuncts: when `split_or` (we are negating, De Morgan turns
/// `¬(a∨b)` into `¬a ∧ ¬b`) descend through Or; otherwise descend through And.
/// Never descend Select — the i128 compare idiom must stay whole for gate_vals.
fn bool_split<'c>(v: BasicValueEnum<'c>, split_or: bool, depth: u32, out: &mut Vec<BasicValueEnum<'c>>) {
    if depth > 0 {
        if let Some(i) = as_instr(v) {
            let want = if split_or { InstructionOpcode::Or } else { InstructionOpcode::And };
            if is_bool(v) && i.get_opcode() == want {
                for k in 0..i.get_num_operands() {
                    if let Some(Operand::Value(o)) = i.get_operand(k) {
                        if is_bool(o) {
                            bool_split(o, split_or, depth - 1, out);
                        }
                    }
                }
                return;
            }
        }
    }
    out.push(v);
}

/// A Select condition as a Lean `Prop` (a compare or a decoded-bool test), its
/// operands rendered as Lean terms; None for anything else.
fn lean_cond(
    c: &Expr,
    args: &Args,
    opmap: &mut HashMap<String, String>,
    oc: &mut usize,
    decls: &mut Vec<String>,
    fnid: &str,
) -> Option<String> {
    match c {
        Expr::Opaque(l, xs) if l == "@and" => {
            let parts: Option<Vec<String>> = xs.iter().map(|x| lean_cond(x, args, opmap, oc, decls, fnid)).collect();
            Some(parts?.iter().map(|p| format!("({p})")).collect::<Vec<_>>().join(" ∧ "))
        }
        Expr::Opaque(l, xs) if l == "@or" => {
            let parts: Option<Vec<String>> = xs.iter().map(|x| lean_cond(x, args, opmap, oc, decls, fnid)).collect();
            Some(parts?.iter().map(|p| format!("({p})")).collect::<Vec<_>>().join(" ∨ "))
        }
        Expr::Opaque(l, xs) if l == "@true" && xs.is_empty() => Some("True".into()),
        // a choice between two tests.
        Expr::Opaque(l, xs) if l == "Select" && xs.len() == 3 => {
            let c = lean_cond(&xs[0], args, opmap, oc, decls, fnid)?;
            let a = lean_cond(&xs[1], args, opmap, oc, decls, fnid)?;
            let b = lean_cond(&xs[2], args, opmap, oc, decls, fnid)?;
            Some(format!("(if {c} then {a} else {b})"))
        }
        Expr::Opaque(l, xs) if l == "@false" && xs.is_empty() => Some("False".into()),
        Expr::Opaque(l, xs) if l == "@not" && xs.len() == 1 => match &xs[0] {
            // `¬(a < b)` reads as `b ≤ a`, `¬¬c` as `c`.
            x @ Expr::Opaque(il, _) if il.starts_with("ICmp_") && !matches!(negate_bool(x), Expr::Opaque(ref n, _) if n == "@not") => {
                lean_cond(&negate_bool(x), args, opmap, oc, decls, fnid)
            }
            Expr::Opaque(il, ys) if il == "@not" && ys.len() == 1 => lean_cond(&ys[0], args, opmap, oc, decls, fnid),
            Expr::Opaque(il, ys) if il == "@isfalse" && ys.len() == 1 => Some(format!("{} ≠ 0", lean_guard_term(&ys[0], args, opmap, oc, decls, fnid))),
            x => Some(format!("¬({})", lean_cond(x, args, opmap, oc, decls, fnid)?)),
        },
        Expr::Opaque(l, xs) if l == "@isfalse" && xs.len() == 1 => {
            Some(format!("{} = 0", lean_guard_term(&xs[0], args, opmap, oc, decls, fnid)))
        }
        Expr::Opaque(l, xs) if (l == "ICmp_EQ" || l == "ICmp_NE") && xs.len() == 2
            && matches!(&xs[0], Expr::Opaque(c, ys) if c == "@cmp" && ys.len() == 2) && xs[1] == Expr::Const(0) =>
        {
            let Expr::Opaque(_, ys) = &xs[0] else { unreachable!() };
            let (a, b) = (lean_guard_term(&ys[0], args, opmap, oc, decls, fnid), lean_guard_term(&ys[1], args, opmap, oc, decls, fnid));
            Some(format!("{a} {} {b}", if l == "ICmp_EQ" { "=" } else { "≠" }))
        }
        Expr::Opaque(l, xs) if l.starts_with("ICmp_") && xs.len() == 2 => {
            let rel = match &l["ICmp_".len()..] {
                "EQ" => "=", "NE" => "≠", "SLT" | "ULT" => "<", "SLE" | "ULE" => "≤",
                "SGT" | "UGT" => ">", "SGE" | "UGE" => "≥", _ => return None,
            };
            if let Some((a, r, b)) = cmp_rel(&xs[0], rel, &xs[1]) {
                return Some(format!("{} {r} {}", lean_guard_term(&a, args, opmap, oc, decls, fnid), lean_guard_term(&b, args, opmap, oc, decls, fnid)));
            }
            if let Some((p, r, k)) = raw_small_cmp(&xs[0], rel, &xs[1], args) {
                return Some(format!("{} {r} {k}", lean_guard_term(&p, args, opmap, oc, decls, fnid)));
            }
            let a = lean_guard_term(&xs[0], args, opmap, oc, decls, fnid);
            let b = lean_guard_term(&xs[1], args, opmap, oc, decls, fnid);
            Some(format!("{a} {rel} {b}"))
        }
        _ => None,
    }
}

thread_local! {
    /// The entrypoint being rendered (its inputs are `<entry>.<arg> st`).
    static CUR_ENTRY: std::cell::RefCell<String> = const { std::cell::RefCell::new(String::new()) };
    /// Per entrypoint, the inputs the model refers to: accessor -> is an address.
    static INPUTS: std::cell::RefCell<BTreeMap<String, BTreeMap<String, bool>>> = const { std::cell::RefCell::new(BTreeMap::new()) };
    /// The storage layout: named keys, in definition order (name, params, body).
    static LAYOUT: std::cell::RefCell<Vec<(String, Vec<String>, String)>> = const { std::cell::RefCell::new(vec![]) };
}

/// A Lean identifier for `s` (Lean keywords quoted with «»).
fn lean_ident(s: &str) -> String {
    const KW: &[&str] = &["from", "fun", "at", "by", "have", "show", "let", "in", "do", "then", "else", "if", "match", "with",
        "end", "open", "namespace", "def", "theorem", "where", "deriving", "instance", "structure", "class", "mut", "return",
        "for", "unless", "try", "catch", "finally", "break", "continue", "Type", "Prop", "Sort", "import", "section",
        "variable", "universe", "example", "abbrev", "axiom", "opaque", "inductive", "local", "private", "protected",
        "partial", "unsafe", "noncomputable", "calc", "suffices", "obtain", "nomatch", "forall", "exists", "this"];
    if KW.contains(&s) { format!("«{s}»") } else { s.to_string() }
}

/// An input of the entrypoint being rendered: `(<entry>.<name> st)`.
fn input_ref(name: &str, is_addr: bool) -> String {
    let entry = CUR_ENTRY.with(|e| e.borrow().clone());
    INPUTS.with(|m| { m.borrow_mut().entry(entry.clone()).or_default().insert(name.to_string(), is_addr); });
    let path: Vec<String> = name.split('.').map(lean_ident).collect();
    format!("({}.{} st)", lean_ident(&entry), path.join("."))
}

/// A storage key, named after the contract's layout: a slot `Offer`, a map
/// entry `(Balance a)`, a tuple key `(Minter c m)`, a struct field
/// `Offer.seller` / `(Minter.limit c m)`. Each name is defined once (`LAYOUT`).
#[derive(Clone)]
enum KeyT {
    Var(String),
    Entry(String, String),
    Tup(String, Vec<String>),
    Fld(Box<KeyT>, String),
}

impl KeyT {
    /// (name, parameter kinds, arguments) of the named form.
    fn head(&self) -> (String, Vec<&'static str>, Vec<String>) {
        match self {
            KeyT::Var(n) => (lean_ident(n), vec![], vec![]),
            KeyT::Entry(n, x) => (lean_ident(n), vec!["Addr"], vec![x.clone()]),
            KeyT::Tup(n, xs) => (lean_ident(n), vec!["Int"; xs.len()], xs.clone()),
            KeyT::Fld(b, f) => {
                let (n, ps, xs) = b.head();
                (format!("{n}.{}", lean_ident(f)), ps, xs)
            }
        }
    }
    /// The definition of the named form, over parameters `k1 … kn`.
    fn body(&self, ks: &[String]) -> String {
        match self {
            KeyT::Var(n) => format!(".var \"{n}\""),
            KeyT::Entry(n, _) => format!(".entry \"{n}\" {}", ks[0]),
            KeyT::Tup(n, _) => format!(".tup \"{n}\" [{}]", ks.join(", ")),
            KeyT::Fld(b, f) => {
                let (bn, _, _) = b.head();
                let base = if ks.is_empty() { bn } else { format!("({bn} {})", ks.join(" ")) };
                format!(".fld {base} \"{f}\"")
            }
        }
    }
    fn render(&self) -> String {
        if let KeyT::Fld(b, _) = self {
            b.render(); // the base is defined first
        }
        let (name, ps, xs) = self.head();
        let ks: Vec<String> = (1..=ps.len()).map(|k| format!("k{k}")).collect();
        let params: Vec<String> = ps.iter().zip(&ks).map(|(t, k)| format!("({k} : {t})")).collect();
        let body = self.body(&ks);
        let ok = LAYOUT.with(|l| {
            let mut l = l.borrow_mut();
            match l.iter().find(|(n, _, _)| *n == name) {
                Some((_, p, b)) => *p == params && *b == body,
                None => {
                    l.push((name.clone(), params.clone(), body.clone()));
                    true
                }
            }
        });
        if !ok {
            return self.raw(); // a clashing shape: written out in full
        }
        if xs.is_empty() { name } else { format!("({name} {})", xs.iter().map(|x| format!("({x})")).collect::<Vec<_>>().join(" ")) }
    }
    fn raw(&self) -> String {
        match self {
            KeyT::Var(n) => format!(".var \"{n}\""),
            KeyT::Entry(n, x) => format!(".entry \"{n}\" ({x})"),
            KeyT::Tup(n, xs) => format!(".tup \"{n}\" [{}]", xs.join(", ")),
            KeyT::Fld(b, f) => format!(".fld ({}) \"{f}\"", b.raw()),
        }
    }
}

/// The storage `Key` a read/write addresses — a named slot (`.var`), a map
/// entry (`.entry`), or a field of a `#[contracttype]` struct stored in one
/// (`.fld`) — with the state a read of it sees (from its `@at` program point).
fn lean_key(
    e: &Expr,
    args: &Args,
    opmap: &mut HashMap<String, String>,
    oc: &mut usize,
    decls: &mut Vec<String>,
    fnid: &str,
) -> Option<(String, String)> {
    let (k, st) = key_t(e, args, opmap, oc, decls, fnid)?;
    Some((k.render(), st))
}

fn key_t(
    e: &Expr,
    args: &Args,
    opmap: &mut HashMap<String, String>,
    oc: &mut usize,
    decls: &mut Vec<String>,
    fnid: &str,
) -> Option<(KeyT, String)> {
    let at = |x: Option<&Expr>| match x {
        Some(Expr::Opaque(a, k)) if a == "@at" => match k.first() { Some(Expr::Const(t)) => state_at(*t as usize), _ => "st.pre".into() },
        _ => "st.pre".into(),
    };
    match e {
        Expr::Slot(n, t) if !matches!(n.as_str(), "instance" | "persistent" | "temporary" | "?") => {
            Some((KeyT::Var(n.clone()), if *t > 0 { state_at(*t - 1) } else { "st.pre".into() }))
        }
        // a variant whose payload is a struct (`Allowance(AllowanceDataKey { from,
        // spender })`): keyed by the struct's fields.
        Expr::Opaque(l, xs) if l.starts_with("@map:") && (xs.len() == 1 || xs.len() == 2)
            && matches!(&xs[0], Expr::Opaque(sl, _) if sl.starts_with("@struct:")) =>
        {
            let Expr::Opaque(_, fs) = &xs[0] else { unreachable!() };
            let mut v = vec![Expr::Opaque("@ks".into(), fs.clone())];
            v.extend(xs.get(1).cloned());
            key_t(&Expr::Opaque(format!("@tup:{}", &l["@map:".len()..]), v), args, opmap, oc, decls, fnid)
        }
        Expr::Opaque(l, xs) if l.starts_with("@map:") && (xs.len() == 1 || xs.len() == 2) => {
            let k = lean_guard_term(&xs[0], args, opmap, oc, decls, fnid);
            Some((KeyT::Entry(l["@map:".len()..].to_string(), k), at(xs.get(1))))
        }
        Expr::Opaque(l, xs) if l.starts_with("@tup:") && (xs.len() == 1 || xs.len() == 2) => {
            let Expr::Opaque(_, ks) = &xs[0] else { return None };
            let ks: Vec<String> = ks.iter().map(|k| lean_guard_term(k, args, opmap, oc, decls, fnid)).collect();
            Some((KeyT::Tup(l["@tup:".len()..].to_string(), ks), at(xs.get(1))))
        }
        Expr::Opaque(l, xs) if l.starts_with("@field:") && xs.len() == 1 => {
            let (k, st) = key_t(&xs[0], args, opmap, oc, decls, fnid)?;
            Some((KeyT::Fld(Box::new(k), l["@field:".len()..].to_string()), st))
        }
        _ => None,
    }
}

/// `Select(has(base) == 1, k, 0)` (either polarity): `(base, k)` when `k` is a
/// read of `base` (itself, or a field of the struct stored there).
fn getor0_parts(xs: &[Expr]) -> Option<(&Expr, &Expr)> {
    fn has_eq1(c: &Expr) -> Option<&Expr> {
        match c {
            Expr::Opaque(l, v) if l == "ICmp_EQ" && v.len() == 2 && v[1] == Expr::Const(1) => match &v[0] {
                Expr::Opaque(h, k) if h == "@has" && k.len() == 1 => Some(&k[0]),
                _ => None,
            },
            _ => None,
        }
    }
    let (base, k) = match (&xs[0], &xs[1], &xs[2]) {
        (c, k, Expr::Const(0)) if has_eq1(c).is_some() => (has_eq1(c)?, k),
        (Expr::Opaque(n, c), Expr::Const(0), k) if n == "@not" && c.len() == 1 => (has_eq1(&c[0])?, k),
        _ => return None,
    };
    // same key, ignoring program points: `k` is `base` or `.fld … base`.
    fn strip(e: &Expr) -> Expr {
        match e {
            Expr::Slot(n, _) => Expr::Slot(n.clone(), 0),
            Expr::Opaque(l, xs) => Expr::Opaque(l.clone(), xs.iter().filter(|x| !matches!(x, Expr::Opaque(a, _) if a == "@at")).map(strip).collect()),
            e => e.clone(),
        }
    }
    let mut r = k;
    loop {
        if strip(r) == strip(base) {
            return Some((base, k));
        }
        match r {
            Expr::Opaque(l, v) if l.starts_with("@field:") && v.len() == 1 => r = &v[0],
            _ => return None,
        }
    }
}

/// `obj_cmp(a, b) ⋈ k` (the host's -1/0/1 object ordering) against a constant,
/// as the same comparison of `a` and `b` themselves: `cmp(a, b) ≤ -1` is `a < b`.
fn cmp_rel(l: &Expr, rel: &str, r: &Expr) -> Option<(Expr, &'static str, Expr)> {
    let (Expr::Opaque(c, ab), Expr::Const(k)) = (l, r) else { return None };
    if c != "@cmp" || ab.len() != 2 {
        return None;
    }
    // the set of orderings {-1, 0, 1} the comparison admits.
    let ok: Vec<i64> = (-1..=1)
        .filter(|&o| match rel { "<" => o < *k, "≤" => o <= *k, ">" => o > *k, "≥" => o >= *k, "=" => o == *k, "≠" => o != *k, _ => false })
        .collect();
    let rel = match ok.as_slice() {
        [-1] => "<", [-1, 0] => "≤", [0] => "=", [1] => ">", [0, 1] => "≥", [-1, 1] => "≠",
        _ => return None,
    };
    Some((ab[0].clone(), rel, ab[1].clone()))
}

/// A u32 compared as its raw Val (`v·2^32 + 4`) against a constant `c` — a u32
/// argument or a `vec.len()`: the same test on the value, as `(v, "<" | "≥", k)`.
/// `raw < c` iff `v < ⌈(c-4)/2^32⌉`, e.g. `raw < 2^32` is `v < 1` (`v = 0`), and
/// `raw > 11·2^32 - 1` is `v ≥ 11`. (An i32 is only taken against multiples of
/// 2^32, where the tag cannot matter.)
fn raw_small_cmp(a: &Expr, rel: &str, b: &Expr, args: &Args) -> Option<(Expr, &'static str, i64)> {
    let kind = |x: &Expr| match x {
        Expr::Param(i) => args.get(*i).map(|(_, _, t)| t.as_str()).filter(|t| *t == "u32" || *t == "i32"),
        Expr::Opaque(l, v) if l == "@len" && v.len() == 1 => Some("u32"),
        _ => None,
    };
    let (p, rel, c) = match (kind(a), kind(b), a, b) {
        (Some(_), _, _, Expr::Const(c)) => (a, rel, *c),
        (None, Some(_), Expr::Const(c), _) => (b, match rel { "<" => ">", "≤" => "≥", ">" => "<", "≥" => "≤", r => r }, *c),
        _ => return None,
    };
    let two32 = 1i128 << 32;
    let ceil = |n: i128| (n + two32 - 1).div_euclid(two32);
    let lt = |c: i128| ceil(c - 4); // raw < c  ⇔  v < lt(c)
    let c = c as i128;
    if kind(p) == Some("i32") && (c == 0 || c % two32 != 0) {
        return None;
    }
    let (r, k) = match rel {
        "<" => ("<", lt(c)),
        "≤" => ("<", lt(c + 1)),
        ">" => ("≥", lt(c + 1)),
        "≥" => ("≥", lt(c)),
        _ => return None,
    };
    Some((p.clone(), r, i64::try_from(k).ok()?))
}

fn lean_guard_term(
    e: &Expr,
    args: &Args,
    opmap: &mut HashMap<String, String>,
    oc: &mut usize,
    decls: &mut Vec<String>,
    fnid: &str,
) -> String {
    match e {
        Expr::Param(i) => match args.get(*i) {
            Some((_, n, t)) if t == "Address" => input_ref(n, true),
            Some((_, n, _)) => input_ref(n, false),
            None => format!("st.call.arg \"p{i}\""),
        },
        Expr::Const(k) => k.to_string(),
        // Rust's `/` and `%` truncate toward zero: Int.tdiv / Int.tmod.
        Expr::Bin(o @ ('/' | '%'), a, b) => format!(
            "(Int.{} {} {})",
            if *o == '/' { "tdiv" } else { "tmod" },
            lean_guard_term(a, args, opmap, oc, decls, fnid),
            lean_guard_term(b, args, opmap, oc, decls, fnid),
        ),
        Expr::Bin(o, a, b) => format!(
            "({} {} {})",
            lean_guard_term(a, args, opmap, oc, decls, fnid),
            o,
            lean_guard_term(b, args, opmap, oc, decls, fnid),
        ),
        // a storage read (a named slot, a map entry, a struct field of one), in
        // the state at its program point.
        e if lean_key(e, args, &mut HashMap::new(), &mut 0, &mut vec![], fnid).is_some() => {
            let (k, st) = lean_key(e, args, opmap, oc, decls, fnid).unwrap();
            format!("({st} ({k}))")
        }
        Expr::Opaque(l, xs) if l == "@pool" && xs.is_empty() => "(pool st)".into(),
        // `has(k)`: k's presence bit, as a Soroban bool (1 = present).
        Expr::Opaque(l, xs) if l == "@has" && xs.len() == 1 && lean_key(&xs[0], args, &mut HashMap::new(), &mut 0, &mut vec![], fnid).is_some() => {
            let (k, st) = lean_key(&xs[0], args, opmap, oc, decls, fnid).unwrap();
            format!("({st} (.has ({k})))")
        }
        Expr::Opaque(l, xs) if l.starts_with("@env:") && xs.is_empty() => format!("(st.call.env \"{}\")", &l["@env:".len()..]),
        // the length of a Vec argument: `claimants.len`.
        Expr::Opaque(l, xs) if l == "@len" && matches!(xs.as_slice(), [Expr::Param(i)] if args.get(*i).is_some()) => {
            let Expr::Param(i) = &xs[0] else { unreachable!() };
            input_ref(&format!("{}.len", args[*i].1), false)
        }
        // a field of a struct ARGUMENT: `config.limit`.
        Expr::Opaque(l, xs) if l.starts_with("@field:") && matches!(xs.as_slice(), [Expr::Param(i)] if args.get(*i).is_some()) => {
            let Expr::Param(i) = &xs[0] else { unreachable!() };
            input_ref(&format!("{}.{}", args[*i].1, &l["@field:".len()..]), false)
        }
        // the address carried by an address-like argument (MuxedAddress etc.)
        Expr::Opaque(l, xs) if l == "@addrof" && xs.len() == 1 => match &xs[0] {
            Expr::Param(i) => args.get(*i).map(|(_, n, _)| input_ref(n, true)).unwrap_or_else(|| "(pool st)".into()),
            x => lean_guard_term(x, args, opmap, oc, decls, fnid),
        },
        // SEP-41 `token.balance(who)` on a named token slot: that token's ledger.
        Expr::Opaque(l, xs) if l == "@call:balance" && (xs.len() == 2 || xs.len() == 3)
            && matches!(&xs[1], Expr::Opaque(v, w) if v == "@vec" && w.len() == 1) =>
        {
            let tok = lean_guard_term(&xs[0], args, opmap, oc, decls, fnid);
            let Expr::Opaque(_, who) = &xs[1] else { unreachable!() };
            // the ledger state at the read's program point (after earlier transfers).
            let state = match xs.get(2) {
                Some(Expr::Opaque(a, k)) if a == "@at" => match k.first() { Some(Expr::Const(site)) => state_at(*site as usize), _ => "st.pre".into() },
                _ => "st.pre".into(),
            };
            format!("(bal {tok} {state} {})", lean_guard_term(&who[0], args, opmap, oc, decls, fnid))
        }
        Expr::Opaque(l, xs) if l == "@bool" && xs.len() == 1 => lean_guard_term(&xs[0], args, opmap, oc, decls, fnid),
        // `get(k).unwrap_or(0)`: `has(base) ? k : 0`, read in one state.
        Expr::Opaque(l, xs) if l == "Select" && xs.len() == 3 && getor0_parts(xs).is_some_and(|(b, k)| {
            lean_key(b, args, &mut HashMap::new(), &mut 0, &mut vec![], fnid).is_some() && lean_key(k, args, &mut HashMap::new(), &mut 0, &mut vec![], fnid).is_some()
        }) => {
            let (base, k) = getor0_parts(xs).unwrap();
            let (kb, sb) = lean_key(base, args, &mut HashMap::new(), &mut 0, &mut vec![], fnid).unwrap();
            let (kk, sk) = lean_key(k, args, &mut HashMap::new(), &mut 0, &mut vec![], fnid).unwrap();
            if sb == sk {
                let (kk, _) = lean_key(k, args, opmap, oc, decls, fnid).unwrap();
                if kb == kk { format!("(getOr0 {sk} ({kk}))") } else { format!("(getOr0 {sk} ({kk}) (base := {kb}))") }
            } else {
                let _ = kk;
                format!("(if ({sb} (.has ({kb}))) = 1 then {} else 0)", lean_guard_term(k, args, opmap, oc, decls, fnid))
            }
        }
        Expr::Opaque(l, xs) if l == "Select" && xs.len() == 3
            && matches!(&xs[0], Expr::Opaque(n, _) if n == "@isfalse" || n == "@and" || n == "@or" || n == "@not" || n.starts_with("ICmp_"))
            && lean_cond(&xs[0], args, &mut HashMap::new(), &mut 0, &mut vec![], fnid).is_some() =>
        {
            let c = lean_cond(&xs[0], args, opmap, oc, decls, fnid).unwrap_or_else(|| "False".into());
            let t = format!(
                "(if {c} then {} else {})",
                lean_guard_term(&xs[1], args, opmap, oc, decls, fnid),
                lean_guard_term(&xs[2], args, opmap, oc, decls, fnid)
            );
            // built only from open values: it is just one open value.
            if !t.contains("st") {
                *oc += 1;
                let nm = format!("(u.{} {oc})", if fnid.ends_with("_e") { "i" } else { "g" });
                decls.push(nm.clone());
                return nm;
            }
            t
        }
        // storage read / vec read / unrecognized op: a fresh opaque Step-term.
        // (We do NOT merge by rendered shape — different i128 reconstructions
        // print identically once their loads are opaque, and merging them would
        // wrongly tie distinct quantities together into contradictory guards.)
        _ => {
            let _ = &opmap;
            *oc += 1;
            // body unknowns are `u.i n`, guard unknowns `u.g n` (distinct counters).
            let nm = format!("(u.{} {oc})", if fnid.ends_with("_e") { "i" } else { "g" });
            decls.push(nm.clone());
            nm
        }
    }
}


/// Recognize the i128 sign-extension of the hi limb, `phi(x, AShr(x, 63))`, and
/// collapse it to `x` (so an i128 argument/value reads as itself, not its limb).
fn i128_sext(e: &Expr) -> Expr {
    if let Expr::Opaque(op, xs) = e {
        if op == "phi" && xs.len() == 2 {
            if let Expr::Opaque(a, ax) = &xs[1] {
                if a == "AShr" && ax.len() == 2 && ax[0] == xs[0] && matches!(ax[1], Expr::Const(63)) {
                    return i128_sext(&xs[0]);
                }
            }
        }
    }
    match e {
        Expr::Bin(o, a, b) => Expr::Bin(*o, Box::new(i128_sext(a)), Box::new(i128_sext(b))),
        Expr::VecGet(a, b) => Expr::VecGet(Box::new(i128_sext(a)), Box::new(i128_sext(b))),
        Expr::Opaque(l, xs) => Expr::Opaque(l.clone(), xs.iter().map(i128_sext).collect()),
        other => other.clone(),
    }
}

/// The signed-subtraction-overflow idiom `And(Xor(a-b, a), Xor(a, b))` (its sign
/// bit is the overflow flag) — a compiler-inserted check, not a contract guard.
fn is_sub_overflow(e: &Expr) -> bool {
    if let Expr::Opaque(op, xs) = e {
        if op == "And" && xs.len() == 2 {
            if let (Expr::Opaque(x1, a1), Expr::Opaque(x2, a2)) = (&xs[0], &xs[1]) {
                if x1 == "Xor" && x2 == "Xor" && a1.len() == 2 && a2.len() == 2 {
                    // one Xor is (a-b)^a, the other is a^b, sharing a and b.
                    if let Expr::Bin('-', sa, _sb) = &a1[0] {
                        return **sa == a1[1] && (a2[0] == a1[1] || a2[1] == a1[1]);
                    }
                }
            }
        }
    }
    false
}

/// The signed add/sub overflow flag idiom `And(Xor(..), Xor(..))` (its sign bit
/// is the overflow bit) — compiler-inserted, not a contract guard.
fn is_ovf_flag(e: &Expr) -> bool {
    matches!(e, Expr::Opaque(op, xs) if op == "And" && xs.len() == 2
        && xs.iter().any(|x| matches!(x, Expr::Opaque(n, _) if n == "Xor")))
}

/// Does `e` contain an uninterpreted op whose label starts with `prefix`?
fn has_label(e: &Expr, prefix: &str) -> bool {
    match e {
        Expr::Opaque(l, xs) => l.starts_with(prefix) || xs.iter().any(|x| has_label(x, prefix)),
        Expr::Bin(_, a, b) | Expr::VecGet(a, b) => has_label(a, prefix) || has_label(b, prefix),
        _ => false,
    }
}

/// Does `e` contain a loop-carried value (`cyc`: a cycle in the reconstruction,
/// e.g. the iteration variables of the isqrt routine)? Those are internals of a
/// numeric routine, not quantities a guard can be stated over.
fn has_cycle(e: &Expr) -> bool {
    match e {
        Expr::Opaque(l, xs) => l == "cyc" || xs.iter().any(has_cycle),
        Expr::Bin(_, a, b) | Expr::VecGet(a, b) => has_cycle(a) || has_cycle(b),
        _ => false,
    }
}

/// Does a reconstructed expression mention an argument or a storage slot?
fn expr_has_named(e: &Expr) -> bool {
    match e {
        Expr::Param(_) | Expr::Slot(..) => true,
        Expr::Bin(_, a, b) | Expr::VecGet(a, b) => expr_has_named(a) || expr_has_named(b),
        Expr::Opaque(_, xs) => xs.iter().any(expr_has_named),
        Expr::Const(_) => false,
    }
}

// ===================== rich entrypoint bodies (transfers + writes) =====================

thread_local! {
    /// Program points (paths of instruction ordinals down the call chain), interned.
    static PATHS: std::cell::RefCell<(Vec<Vec<usize>>, HashMap<Vec<usize>, usize>)> = std::cell::RefCell::new((vec![], HashMap::new()));
    /// Each function's instruction -> execution-order ordinal.
    static ORDINALS: std::cell::RefCell<HashMap<usize, HashMap<usize, usize>>> = std::cell::RefCell::new(HashMap::new());
    /// The program points of the entrypoint's effects, in order (for states).
    static TX_SITES: std::cell::RefCell<Vec<usize>> = const { std::cell::RefCell::new(vec![]) };
}

/// Run `body` with `f` as the entrypoint being modeled.
fn with_entry<T>(_f: FunctionValue, body: impl FnOnce() -> T) -> T {
    let r = body();
    TX_SITES.with(|t| t.borrow_mut().clear());
    r
}

/// The id of program point `path` (a call path: ordinals in each function).
fn intern(path: Vec<usize>) -> usize {
    PATHS.with(|p| {
        let mut p = p.borrow_mut();
        if let Some(&id) = p.1.get(&path) {
            return id;
        }
        let id = p.0.len();
        p.0.push(path.clone());
        p.1.insert(path, id);
        id
    })
}

fn path_of(id: usize) -> Vec<usize> {
    PATHS.with(|p| p.borrow().0.get(id).cloned().unwrap_or_default())
}

/// `i`'s ordinal in `g`, in execution (reverse postorder) order.
fn local_ordinal(g: FunctionValue, i: InstructionValue) -> usize {
    use inkwell::values::AsValueRef;
    let key = g.as_value_ref() as usize;
    ORDINALS.with(|o| {
        let mut o = o.borrow_mut();
        let m = o.entry(key).or_insert_with(|| rpo_instrs(g).iter().enumerate().map(|(k, x)| (x.as_value_ref() as usize, k)).collect());
        m.get(&(i.as_value_ref() as usize)).copied().unwrap_or(usize::MAX)
    })
}

/// The program point of instruction `i` of `g`, relative to `g` (a call site
/// prefixes it when `g`'s expressions are substituted into a caller).
fn entry_site(g: FunctionValue, i: InstructionValue) -> Option<usize> {
    Some(intern(vec![local_ordinal(g, i)]))
}

/// Re-root the program points in callee expression `e` under call `c` (an
/// ordinal in the caller); caller-side parts (`@done`) are left alone.
fn prefix_at(e: &Expr, c: usize) -> Expr {
    match e {
        Expr::Opaque(l, xs) if l == "@done" => e.clone(),
        Expr::Opaque(l, xs) if l == "@at" && xs.len() == 1 => match xs[0] {
            Expr::Const(id) => {
                let mut p = vec![c];
                p.extend(path_of(id as usize));
                Expr::Opaque("@at".into(), vec![Expr::Const(intern(p) as i64)])
            }
            _ => e.clone(),
        },
        Expr::Bin(o, a, b) => Expr::Bin(*o, Box::new(prefix_at(a, c)), Box::new(prefix_at(b, c))),
        Expr::VecGet(a, b) => Expr::VecGet(Box::new(prefix_at(a, c)), Box::new(prefix_at(b, c))),
        Expr::Opaque(l, xs) => annotate_at(&Expr::Opaque(l.clone(), xs.iter().map(|x| prefix_at(x, c)).collect()), intern(vec![c])),
        other => other.clone(),
    }
}

/// Tag every not-yet-tagged `balance()` read in `e` with the program point it
/// happens at (so it reads the ledger state after the transfers before it).
fn annotate_at(e: &Expr, site: usize) -> Expr {
    match e {
        Expr::Opaque(l, _) if l == "@done" => e.clone(),
        Expr::Opaque(l, xs) if (l == "@call:balance" && xs.len() == 2) || (l.starts_with("@slot:") && xs.len() == 1) => {
            let mut v: Vec<Expr> = xs.iter().map(|x| annotate_at(x, site)).collect();
            v.push(Expr::Opaque("@at".into(), vec![Expr::Const(site as i64)]));
            Expr::Opaque(l.clone(), v)
        }
        Expr::Bin(o, a, b) => Expr::Bin(*o, Box::new(annotate_at(a, site)), Box::new(annotate_at(b, site))),
        Expr::VecGet(a, b) => Expr::VecGet(Box::new(annotate_at(a, site)), Box::new(annotate_at(b, site))),
        Expr::Opaque(l, xs) => Expr::Opaque(l.clone(), xs.iter().map(|x| annotate_at(x, site)).collect()),
        other => other.clone(),
    }
}

/// The state a read at program point `site` sees: after the effects that come
/// before it in execution order (`st.pre` when none).
fn state_at(site: usize) -> String {
    let at = path_of(site);
    let n = TX_SITES.with(|t| t.borrow().iter().filter(|&&s| path_of(s) < at).count());
    if n == 0 { "st.pre".into() } else { format!("@D:s{n}@") }
}

/// One path's branch decisions: `(block, successor taken)` pairs.
type PathConj = BTreeSet<(usize, usize)>;

/// Each block's loop (strongly connected component with a cycle), if any.
fn loop_of(cfg: &Cfg) -> Vec<Option<usize>> {
    let n = cfg.succ.len();
    let reach: Vec<Vec<bool>> = (0..n)
        .map(|b| {
            let mut seen = vec![false; n];
            let mut work: Vec<usize> = cfg.succ[b].clone();
            while let Some(x) = work.pop() {
                if !std::mem::replace(&mut seen[x], true) {
                    work.extend(cfg.succ[x].iter().copied());
                }
            }
            seen
        })
        .collect();
    (0..n).map(|b| reach[b][b].then(|| (0..n).find(|&c| reach[b][c] && reach[c][b]).unwrap_or(b))).collect()
}

/// The exact condition under which `blk` executes, as a disjunction over paths
/// (from the entry) of the branch edges they take. A branch whose other edge
/// panics adds nothing (a step only describes non-panicking runs), and paths
/// that differ only in which way they went at some branch — rejoining after it
/// — merge. None for a block inside a loop, or past `cap` disjuncts.
fn reach_dnf(cfg: &Cfg, blk: usize, memo: &mut HashMap<usize, Option<Vec<PathConj>>>, active: &mut HashSet<usize>) -> Option<Vec<PathConj>> {
    let loops = loop_of(cfg);
    reach_dnf_in(cfg, &loops, blk, memo, active)
}

fn reach_dnf_in(cfg: &Cfg, loops: &[Option<usize>], blk: usize, memo: &mut HashMap<usize, Option<Vec<PathConj>>>, active: &mut HashSet<usize>) -> Option<Vec<PathConj>> {
    if let Some(r) = memo.get(&blk) {
        return r.clone();
    }
    if blk == 0 {
        return Some(vec![PathConj::new()]);
    }
    if loops[blk].is_some() || !active.insert(blk) {
        return None; // inside a loop: how often / whether it runs is not tracked
    }
    let live = |p: usize| -> Vec<usize> {
        let mut v: Vec<usize> = cfg.succ[p].iter().copied().filter(|&s| !forces_trap(cfg.blocks[s], 6)).collect();
        v.sort();
        v.dedup();
        v
    };
    // the edges into blk: a loop's exit stands for entering the loop (a loop
    // with this as its only exit leaves it once it terminates).
    let mut ins: Vec<(usize, usize)> = vec![];
    for p in (0..cfg.succ.len()).filter(|&u| cfg.succ[u].contains(&blk)) {
        match loops[p] {
            None => ins.push((p, blk)),
            Some(l) => {
                let body: Vec<usize> = (0..cfg.succ.len()).filter(|&b| loops[b] == Some(l)).collect();
                let exits: BTreeSet<usize> = body.iter().flat_map(|&b| live(b)).filter(|&t| loops[t] != Some(l)).collect();
                if exits.len() != 1 {
                    return None;
                }
                for (q, h) in (0..cfg.succ.len()).filter(|&q| loops[q] != Some(l)).flat_map(|q| cfg.succ[q].iter().map(move |&h| (q, h))) {
                    if loops[h] == Some(l) && !ins.contains(&(q, h)) {
                        ins.push((q, h));
                    }
                }
            }
        }
    }
    let mut out: Option<Vec<PathConj>> = Some(vec![]);
    for (p, t) in ins {
        let Some(rp) = reach_dnf_in(cfg, loops, p, memo, active) else { out = None; break };
        let decides = live(p).len() > 1; // a real (non-guard) choice at p
        for mut d in rp {
            if decides {
                d.insert((p, t));
            }
            out.as_mut().unwrap().push(d);
        }
    }
    active.remove(&blk);
    // merge: {R ∪ (p, t)} over every live successor t of p  ==>  R.
    let out = out.map(|mut ds| {
        loop {
            ds.sort();
            ds.dedup();
            let mut merged = None;
            'find: for d in &ds {
                for &(p, _) in d {
                    let rest: PathConj = d.iter().copied().filter(|&(q, _)| q != p).collect();
                    let all = live(p).iter().all(|&t| {
                        let mut want = rest.clone();
                        want.insert((p, t));
                        ds.contains(&want)
                    });
                    if all {
                        merged = Some((p, rest));
                        break 'find;
                    }
                }
            }
            let Some((p, rest)) = merged else { break };
            ds.retain(|d| !(d.iter().any(|&(q, _)| q == p) && d.iter().filter(|&&(q, _)| q != p).copied().collect::<PathConj>() == rest));
            ds.push(rest);
        }
        // absorption: a path condition implied by a weaker one is redundant.
        let snapshot = ds.clone();
        ds.retain(|d| !snapshot.iter().any(|e| e != d && e.is_subset(d)));
        ds
    });
    let out = out.filter(|ds| ds.len() <= 16);
    memo.insert(blk, out.clone());
    out
}

/// The condition of branch edge `p → t` of `f`, as an expression.
fn edge_cond<'c>(f: FunctionValue<'c>, cfg: &Cfg<'c>, p: usize, t: usize, module: &inkwell::module::Module<'c>, memo: &mut HashMap<String, Option<Expr>>) -> Option<Expr> {
    let term = cfg.blocks[p].get_terminator()?;
    let Some(Operand::Value(c)) = term.get_operand(0) else { return None };
    let ce = fold_rich(simplify(value_expr(c, f, module, memo, 40)));
    // its storage reads see the state at the branch.
    let ce = match entry_site(f, term) { Some(site) => annotate_at(&ce, site), None => ce };
    match term.get_opcode() {
        InstructionOpcode::Br => {
            let (fb, tb) = (cfg.succ[p][0], cfg.succ[p][1]); // [false, true]
            if t == tb && t != fb { Some(ce) } else if t == fb && t != tb { Some(Expr::Opaque("@not".into(), vec![ce])) } else { None }
        }
        InstructionOpcode::Switch => {
            let n = term.get_num_operands();
            let mut hit = vec![];
            let mut others = vec![];
            let mut k = 2; // 0 = cond, 1 = default, then (value, block) pairs
            while k + 1 < n {
                if let (Some(Operand::Value(BasicValueEnum::IntValue(v))), Some(Operand::Block(b))) = (term.get_operand(k), term.get_operand(k + 1)) {
                    let v = Expr::Const(v.get_sign_extended_constant()?);
                    if cfg.bidx(b) == Some(t) { hit.push(v) } else { others.push(v) }
                }
                k += 2;
            }
            let is_default = matches!(term.get_operand(1), Some(Operand::Block(d)) if cfg.bidx(d) == Some(t));
            let eqs: Vec<Expr> = hit.into_iter().map(|v| Expr::Opaque("ICmp_EQ".into(), vec![ce.clone(), v])).collect();
            if is_default {
                let nes: Vec<Expr> = others.into_iter().map(|v| Expr::Opaque("ICmp_NE".into(), vec![ce.clone(), v])).collect();
                let d = if nes.len() == 1 { nes[0].clone() } else { Expr::Opaque("@and".into(), nes) };
                return Some(if eqs.is_empty() { d } else { Expr::Opaque("@or".into(), eqs.into_iter().chain([d]).collect()) });
            }
            match eqs.len() {
                0 => None,
                1 => eqs.into_iter().next(),
                _ => Some(Expr::Opaque("@or".into(), eqs)),
            }
        }
        _ => None,
    }
}

/// A path-condition DNF as one expression (`@true` for "always").
fn dnf_expr<'c>(f: FunctionValue<'c>, cfg: &Cfg<'c>, ds: &[PathConj], module: &inkwell::module::Module<'c>, memo: &mut HashMap<String, Option<Expr>>) -> Option<Expr> {
    let mut disj = vec![];
    for d in ds {
        let lits: Vec<Expr> = d.iter().map(|&(p, t)| edge_cond(f, cfg, p, t, module, memo)).collect::<Option<_>>()?;
        disj.push(match lits.len() {
            0 => return Some(Expr::Opaque("@true".into(), vec![])),
            1 => lits.into_iter().next()?,
            _ => Expr::Opaque("@and".into(), lits),
        });
    }
    Some(match disj.len() {
        0 => Expr::Opaque("@false".into(), vec![]),
        1 => disj.pop()?,
        _ => Expr::Opaque("@or".into(), disj),
    })
}

/// The (non-panic) branch conditions block `blk` of `f` executes under: for each
/// conditional branch that is not a guard (neither edge forces a trap) and whose
/// one edge reaches `blk` while the other doesn't, that edge's condition.
fn path_conds<'c>(
    f: FunctionValue<'c>,
    cfg: &Cfg<'c>,
    blk: usize,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
) -> Vec<Expr> {
    let unknown = || vec![Expr::Opaque("?cond".into(), vec![])];
    let Some(ds) = reach_dnf(cfg, blk, &mut HashMap::new(), &mut HashSet::new()) else { return unknown() };
    match ds.as_slice() {
        // one path: its decisions, as conjuncts.
        [d] => d.iter().map(|&(p, t)| edge_cond(f, cfg, p, t, module, memo).unwrap_or_else(|| Expr::Opaque("?cond".into(), vec![]))).collect(),
        _ => dnf_expr(f, cfg, &ds, module, memo).map(|e| vec![e]).unwrap_or_else(unknown),
    }
}

/// A transfer: (token, from, to, amount), relative to the function it's in.
type Tx = (Expr, Expr, Expr, Expr);
/// A storage write: (key slot, value), relative to the function it's in.
type Wr = (Expr, Expr);

/// The SEP-41 transfers and storage writes `h` performs (transitively), in
/// program order, over `h`'s params. `site` maps a call/put in `h` to its
/// ordinal when `h` is the entrypoint (so each event knows where it happens).
/// A constant where a Val is expected (a stored value, a struct field, a
/// transfer argument, a return) is a literal Val payload: the value it encodes
/// (`0i128` is `11`, `7u32` is `7 << 32 | 4`); Void / bools stay as payloads.
fn val_literal(e: Expr) -> Expr {
    match e {
        Expr::Const(c) => Expr::Const(match c & 0xff {
            4 => ((c as u64) >> 32) as i64,
            5 => ((c >> 32) as i32) as i64,
            6 | 10 => ((c as u64) >> 8) as i64,
            7 | 11 => c >> 8,
            _ => c,
        }),
        e => e,
    }
}

/// A cross-contract call the model does not interpret: anything but a SEP-41
/// `transfer` (modeled) or one of its read-only queries.
fn foreign_effect(i: InstructionValue) -> bool {
    let Some(cn) = callee_name(i) else { return false };
    if cn.contains("update_current_contract_wasm") {
        return true;
    }
    if cn != "call.call" && cn != "call.try_call" {
        return false;
    }
    !matches!(call_symbol(i).as_deref(), Some("balance" | "decimals" | "name" | "symbol" | "allowance"))
}

/// Can `h` (transitively) change storage or call another contract?
fn may_effect(h: FunctionValue) -> bool {
    use inkwell::values::AsValueRef;
    thread_local! {
        static MAY: std::cell::RefCell<HashMap<usize, bool>> = std::cell::RefCell::new(HashMap::new());
    }
    let key = h.as_value_ref() as usize;
    if let Some(r) = MAY.with(|m| m.borrow().get(&key).copied()) {
        return r;
    }
    MAY.with(|m| m.borrow_mut().insert(key, true)); // a cycle: assume it may
    let r = all_instrs(h).into_iter().any(|i| {
        let Some(cn) = callee_name(i) else { return false };
        cn.contains("put_contract_data") || cn.contains("del_contract_data") || foreign_effect(i)
            || inkwell::values::CallSiteValue::try_from(i).ok().and_then(|c| c.get_called_fn_value())
                .is_some_and(|g| g.count_basic_blocks() > 0 && may_effect(g))
    });
    MAY.with(|m| m.borrow_mut().insert(key, r));
    r
}

/// An effect the model does not reconstruct: the token ledgers (`@ledgers`, an
/// uninterpreted cross-contract call) or all of storage (`@all`: effects inside
/// a loop, or past the analysis depth) become unknown.
fn havoc(what: &str) -> Option<Wr> {
    Some((Expr::Opaque("@havoc".into(), vec![]), Expr::Opaque(format!("@{what}"), vec![])))
}

/// One effect of `h`: the `h`-level instruction it happens at, its program
/// point (a call path relative to `h`), and the transfer or write.
type Effect<'c> = (InstructionValue<'c>, Vec<usize>, Option<Tx>, Option<Wr>);

/// The SEP-41 transfers and storage writes `h` performs (transitively), in
/// execution order, over `h`'s params — and, where it can't reconstruct an
/// effect, a havoc of what that effect could touch (never nothing).
fn effects<'c>(
    h: FunctionValue<'c>,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
    fuel: u32,
) -> Vec<Effect<'c>> {
    let mut out = vec![];
    let Some(first) = h.get_first_basic_block().and_then(|b| b.get_first_instruction()) else { return out };
    if fuel == 0 {
        if may_effect(h) {
            out.push((first, vec![0], None, havoc("all")));
        }
        return out;
    }
    let cfg = Cfg::build(h);
    let loops = loop_of(&cfg);
    for i in rpo_instrs(h) {
        let Some(cn) = callee_name(i) else { continue };
        let at = vec![local_ordinal(h, i)];
        let op = |k: u32| match i.get_operand(k) { Some(Operand::Value(x)) => Some(x), _ => None };
        let callee = module.get_function(&cn).filter(|g| g.count_basic_blocks() > 0);
        let effectful = cn.contains("put_contract_data") || cn.contains("del_contract_data") || foreign_effect(i)
            || (cn == "call.call" && call_symbol(i).as_deref() == Some("transfer"))
            || callee.is_some_and(may_effect);
        // inside a loop: how many times it runs is not tracked.
        if effectful && i.get_parent().and_then(|b| cfg.bidx(b)).is_some_and(|b| loops[b].is_some()) {
            out.push((i, at, None, havoc("all")));
            continue;
        }
        if cn == "call.call" && call_symbol(i).as_deref() == Some("transfer") {
            let tok = op(0).map(|x| value_expr(x, h, module, memo, 40)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            let parts: Vec<Expr> = op(2)
                .map(linmem_vals_ordered)
                .unwrap_or_default()
                .into_iter()
                .map(|x| value_expr(x, h, module, memo, 40))
                .collect();
            if parts.len() == 3 {
                let p = |k: usize| val_literal(parts[k].clone());
                out.push((i, at, Some((tok, p(0), p(1), p(2))), None));
            } else {
                out.push((i, at, None, havoc("ledgers")));
            }
            continue;
        }
        if foreign_effect(i) {
            out.push((i, at, None, havoc(if cn.contains("update_current_contract_wasm") { "all" } else { "ledgers" })));
            continue;
        }
        if cn.contains("del_contract_data") {
            let dur = op(1).map(durability).unwrap_or_else(|| "?".into());
            let key = op(0).map(|x| key_expr(x, h, module, memo, 40)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            out.push((i, at, None, Some((Expr::Opaque(format!("@slot:{dur}"), vec![key]), Expr::Opaque("@del".into(), vec![])))));
            continue;
        }
        if cn.contains("put_contract_data") {
            let dur = op(2).map(durability).unwrap_or_else(|| "?".into());
            let key = op(0).map(|x| key_expr(x, h, module, memo, 40)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            let val = op(1).map(|x| val_literal(value_expr(x, h, module, memo, 40))).unwrap_or(Expr::Opaque("?".into(), vec![]));
            out.push((i, at, None, Some((Expr::Opaque(format!("@slot:{dur}"), vec![key]), val))));
            continue;
        }
        let Some(g2) = callee else { continue };
        for (_, inner, tx, wr) in effects(g2, module, memo, fuel - 1) {
            let sub = |e: &Expr, memo: &mut HashMap<String, Option<Expr>>| subst_call(e, i, h, &cfg, module, memo, 40);
            let tx = tx.map(|(a, b, c, d)| (sub(&a, memo), sub(&b, memo), sub(&c, memo), sub(&d, memo)));
            let wr = wr.map(|(k, v)| (sub(&k, memo), sub(&v, memo)));
            let mut path = at.clone();
            path.extend(inner);
            out.push((i, path, tx, wr));
        }
    }
    out
}

/// The rendered Lean body of one entrypoint: the state chain, its conjuncts
/// (auth, Ok), post state, the keys its effects name, and the returned value.
struct RichBody {
    defs: Vec<(String, &'static str, String)>, // named (name, type, body): amounts `amtN`, states `sN`; refs `@D:name@`
    post: String,
    writes: Vec<String>,
    events: Vec<String>,           // human-readable, for the doc comment
    ret: String,                   // the returned value (`(u.i 0)` when not reconstructed)
    conjs: Vec<(String, String)>,  // (label, Lean Prop): auths, then the Ok condition
    unk_key: bool,                 // some write goes to a key the model leaves open
}

/// Build the rich body of entrypoint `f` (call inside `with_entry(f, …)`).
fn rich_body<'c>(f: FunctionValue<'c>, module: &inkwell::module::Module<'c>) -> RichBody {
    let args = arg_table(f);
    CUR_ENTRY.with(|e| *e.borrow_mut() = f.get_name().to_string_lossy().chars().map(|c| if c.is_alphanumeric() { c } else { '_' }).collect());
    let kbf = datakey_builder(module);
    let usage = kbf.map(kb_field_usage);
    let kb = kbf.zip(usage.as_ref());
    let segs = rodata_segs(module);
    let cfg = Cfg::build(f);
    let fnid: String = f.get_name().to_string_lossy().chars().map(|c| if c.is_alphanumeric() { c } else { '_' }).collect();
    let tid = format!("{fnid}_e");
    let (mut opmap, mut oc, mut decls) = (HashMap::new(), 0usize, vec![]);
    let structs = spec_structs(module);
    let named = |e: &Expr| ctx_simplify(&apply_facts(&assume_arg_types(&name_slots(e, module, kb, &segs), &args, &structs)));
    let raw = with_rich(|| {
        let mut memo = HashMap::new();
        let evs = effects(f, module, &mut memo, 6);
        // each event's program point and the condition its block runs under.
        evs.into_iter()
            .map(|(i, path, tx, wr)| {
                let site = intern(path);
                let conds = i.get_parent().and_then(|b| cfg.bidx(b)).map(|b| path_conds(f, &cfg, b, module, &mut memo)).unwrap_or_default();
                let fix = |e: Expr| annotate_at(&fold_rich(simplify(e)), site);
                (site, conds, tx.map(|(a, b, c, d)| (fix(a), fix(b), fix(c), fix(d))), wr.map(|(k, v)| (fix(k), fix(v))))
            })
            .collect::<Vec<_>>()
    });
    // every effect is a state; a read sees the state after the effects before it.
    TX_SITES.with(|t| *t.borrow_mut() = raw.iter().map(|e| e.0).collect());
    let evs: Vec<_> = raw
        .into_iter()
        .map(|(site, conds, tx, wr)| {
            // each conjunct of the condition assumes the ones before it.
            let mut conds_n: Vec<Expr> = vec![];
            for c in &conds {
                let prev: Vec<(Expr, bool)> = conds_n.iter().map(|x: &Expr| (x.clone(), true)).collect();
                conds_n.push(assuming(&named(c), &prev));
            }
            let conds = conds_n;
            // an effect only happens under its condition: its values assume it.
            let cs: Vec<(Expr, bool)> = conds.iter().map(|c| (c.clone(), true)).collect();
            let at = |e: &Expr| assuming(&named(e), &cs);
            (site, conds, tx.map(|(a, b, c, d)| (at(&a), at(&b), at(&c), at(&d))), wr.map(|(k, v)| (at(&k), at(&v))))
        })
        .collect();
    // a condition as a Lean Prop; a part we can't render is an open Bool, never
    // `False` (which would claim the guarded effect cannot happen).
    let cond_str = |cs: &[Expr], opmap: &mut HashMap<String, String>, oc: &mut usize, decls: &mut Vec<String>| -> Option<String> {
        if cs.is_empty() {
            return None;
        }
        let unknown = |oc: &mut usize| {
            *oc += 1;
            format!("(u.b {oc}) = true")
        };
        let parts: Vec<String> = cs
            .iter()
            .map(|c| match c {
                Expr::Opaque(l, x) if l == "@not" && x.len() == 1 => match lean_cond(c, &args, opmap, oc, decls, &tid) {
                    Some(s) => s,
                    None => format!("¬({})", unknown(oc)),
                },
                c => lean_cond(c, &args, opmap, oc, decls, &tid).unwrap_or_else(|| unknown(oc)),
            })
            .collect();
        Some(parts.join(" ∧ "))
    };
    let (mut defs, mut writes, mut events): (Vec<(String, &'static str, String)>, Vec<String>, Vec<String>) = (vec![], vec![], vec![]);
    let mut conjs_tx: Vec<(String, String)> = vec![];
    let mut upd_vals: Vec<(String, String)> = vec![];
    let mut unk_key = false;
    let mut cur = "st.pre".to_string();
    let mut nstate = 0;
    for (_site, conds, tx, wr) in &evs {
        let cs = cond_str(conds, &mut opmap, &mut oc, &mut decls);
        let when = cs.as_ref().map(|c| format!(", when `{c}`")).unwrap_or_default();
        let next = |x: String, cur: &str| match &cs { Some(c) => format!("if {c} then {x} else {cur}"), None => x };
        if let Some((tok, from, to, amt)) = tx {
            let ledger = lean_guard_term(tok, &args, &mut opmap, &mut oc, &mut decls, &tid);
            let (fr, tr, ar) = (
                lean_guard_term(from, &args, &mut opmap, &mut oc, &mut decls, &tid),
                lean_guard_term(to, &args, &mut opmap, &mut oc, &mut decls, &tid),
                lean_guard_term(amt, &args, &mut opmap, &mut oc, &mut decls, &tid),
            );
            nstate += 1;
            let aname = format!("amt{}", defs.iter().filter(|d: &&(String, &str, String)| d.0.starts_with("amt")).count() + 1);
            defs.push((aname.clone(), "Int", ar.clone()));
            // the token (SEP-41) accepts the transfer only if `from` holds a
            // non-negative amount — part of the call succeeding.
            let ok = format!("xferOk ({ledger}) {cur} ({fr}) ({tr}) @D:{aname}@");
            conjs_tx.push((format!("token transfer {} accepted", aname), match &cs { Some(c) => format!("(({c}) → {ok})"), None => ok }));
            defs.push((format!("s{nstate}"), "Storage", next(format!("xfer ({ledger}) {cur} ({fr}) ({tr}) @D:{aname}@"), &cur)));
            for p in [&fr, &tr] {
                let k = format!(".bal ({ledger}) ({p})");
                if !writes.contains(&k) {
                    writes.push(k);
                }
            }
            events.push(format!("transfer `@D:{aname}@` of token `{ledger}` from `{fr}` to `{tr}`{when}"));
            cur = format!("@D:s{nstate}@");
        }
        let Some((k, v)) = wr else { continue };
        // an effect the model doesn't interpret: what it could touch is open.
        if matches!(k, Expr::Opaque(l, x) if l == "@havoc" && x.is_empty()) {
            oc += 1;
            let all = matches!(v, Expr::Opaque(l, _) if l == "@all");
            let h = if all { format!("(u.s {oc})") } else { format!("havoc {cur} (u.s {oc})") };
            events.push(format!("{}{when}", if all { "an effect the model doesn't interpret (in a loop, or too deep): all storage open" } else { "a call into another contract: token ledgers open" }));
            nstate += 1;
            defs.push((format!("s{nstate}"), "Storage", next(h, &cur)));
            cur = format!("@D:s{nstate}@");
            continue;
        }
        // an unnameable key is still a write — to SOME key (open), never dropped.
        let kt = key_t(k, &args, &mut opmap, &mut oc, &mut decls, &tid).map(|(k, _)| k);
        let key = match &kt {
            Some(k) => k.render(),
            None => {
                oc += 1;
                unk_key = true;
                format!("(u.k {oc})")
            }
        };
        events.push(if matches!(v, Expr::Opaque(l, x) if l == "@del" && x.is_empty()) { format!("remove `{key}`{when}") } else { format!("write `{key}`{when}") });
        // a struct value is stored field by field (nested structs recursively),
        // each field a named key of the layout.
        fn flatten(key: Option<KeyT>, raw: String, v: &Expr, out: &mut Vec<(String, Expr)>) {
            match v {
                Expr::Opaque(l, xs) if l.starts_with("@struct:") && l["@struct:".len()..].split(',').count() == xs.len() => {
                    for (f, x) in l["@struct:".len()..].split(',').zip(xs) {
                        let fk = key.clone().map(|k| KeyT::Fld(Box::new(k), f.to_string()));
                        let fr = fk.as_ref().map(|k| k.render()).unwrap_or_else(|| format!(".fld ({raw}) \"{f}\""));
                        flatten(fk, fr, x, out);
                    }
                }
                _ => out.push((raw, v.clone())),
            }
        }
        let mut sets = vec![];
        let del = matches!(v, Expr::Opaque(l, x) if l == "@del" && x.is_empty());
        if !del {
            flatten(kt.clone(), key.clone(), v, &mut sets);
        }
        // the key's presence: set → 1, remove → 0.
        sets.push((format!(".has ({key})"), Expr::Const(if del { 0 } else { 1 })));
        // a long key gets a name: `key_MinterStats` (fields: `key_MinterStats_consumed_limit`).
        let name_key = |k: &str, defs: &mut Vec<(String, &'static str, String)>| -> String {
            if k.len() <= 60 || !k.contains(' ') {
                return k.to_string();
            }
            let name = format!("key_{}", key_name(k));
            if !defs.iter().any(|d| d.0 == name) {
                defs.push((name.clone(), "Key", k.to_string()));
            }
            format!("@D:{name}@")
        };
        let sets: Vec<(String, Expr)> = sets
            .into_iter()
            .map(|(k, v)| match k.strip_prefix(".has (").and_then(|r| r.strip_suffix(')')) {
                Some(root) => (format!(".has ({})", name_key(root, &mut defs)), v),
                None => (name_key(&k, &mut defs), v),
            })
            .collect();
        let mut upd = cur.clone();
        for (key, v) in &sets {
            let mut val = lean_guard_term(v, &args, &mut opmap, &mut oc, &mut decls, &tid);
            // a computed value gets a name, after its key: `new_ReserveA`.
            let simple = !val.contains(' ') || (val.starts_with('(') && val.matches(' ').count() == 1);
            if !simple {
                let k = key.strip_prefix("@D:key_").and_then(|k| k.strip_suffix('@')).unwrap_or(key);
                let base = format!("new_{}", key_name(k));
                let mut name = base.clone();
                let mut k = 1;
                while defs.iter().any(|d| d.0 == name) {
                    k += 1;
                    name = format!("{base}_{k}");
                }
                defs.push((name.clone(), "Int", val));
                val = format!("@D:{name}@");
            }
            if !key.starts_with(".has") {
                upd_vals.push((key.clone(), val.clone()));
            }
            upd = format!("({upd}).set ({key}) ({val})");
            if !writes.contains(key) {
                writes.push(key.clone());
            }
        }
        // the event says what was stored: `ReserveA := new_ReserveA`, or the fields.
        if !del {
            let vals: Vec<&(String, Expr)> = sets.iter().filter(|(k, _)| !k.starts_with(".has")).collect();
            let shown: Vec<String> = upd_vals.iter().take(vals.len()).map(|(k, v)| format!("`{k}` := `{v}`")).collect();
            if let Some(ev) = events.last_mut() {
                *ev = format!("write {}{when}", shown.join(", "));
            }
        }
        upd_vals.clear();
        nstate += 1;
        defs.push((format!("s{nstate}"), "Storage", next(upd, &cur)));
        cur = format!("@D:s{nstate}@");
    }
    let post = cur;
    // the returned value, read in the state at the return.
    let ret = with_rich(|| {
        let mut memo = HashMap::new();
        let mut vals: Vec<Expr> = vec![];
        for r in all_instrs(f).into_iter().filter(|i| i.get_opcode() == InstructionOpcode::Return) {
            let Some(Operand::Value(v)) = r.get_operand(0) else { return None };
            let e = named(&val_literal(fold_rich(simplify(value_expr(v, f, module, &mut memo, 40)))));
            if !vals.contains(&e) {
                vals.push(e);
            }
        }
        match vals.as_slice() {
            [e] => Some(e.clone()),
            _ => None,
        }
    });
    let mut conjs: Vec<(String, String)> = conjs_tx;
    // every `x.require_auth()` (and `_for_args`) of the entrypoint: x signed —
    // under the condition the call runs in.
    with_rich(|| {
        let mut memo = HashMap::new();
        for i in rpo_instrs(f) {
            if !callee_name(i).is_some_and(|n| n.contains("require_auth")) {
                continue;
            }
            let Some(Operand::Value(v)) = i.get_operand(0) else { continue };
            let e = named(&fold_rich(simplify(value_expr(v, f, module, &mut memo, 40))));
            let who = match &e {
                Expr::Param(_) => lean_guard_term(&e, &args, &mut opmap, &mut oc, &mut decls, &tid),
                e if lean_key(e, &args, &mut HashMap::new(), &mut 0, &mut vec![], &tid).is_some() => lean_guard_term(e, &args, &mut opmap, &mut oc, &mut decls, &tid),
                _ => continue, // an address we can't name: the auth is dropped (weaker, sound)
            };
            let pcs: Vec<Expr> = i.get_parent().and_then(|b| cfg.bidx(b)).map(|b| path_conds(f, &cfg, b, module, &mut memo)).unwrap_or_default();
            let pc = cond_str(&pcs.iter().map(named).collect::<Vec<_>>(), &mut opmap, &mut oc, &mut decls);
            let p = match pc {
                Some(pc) => format!("(({pc}) → {who} ∈ st.call.signers)"),
                None => format!("{who} ∈ st.call.signers"),
            };
            let label = format!("require_auth {}", render_expr(&e, &args));
            if !conjs.iter().any(|(_, q)| *q == p) {
                conjs.push((label, p));
            }
        }
    });
    // a Result-returning entrypoint: it succeeds only when it returns Ok.
    if let Some(c) = ret.as_ref().and_then(ok_condition).and_then(|c| lean_cond(&c, &args, &mut opmap, &mut oc, &mut decls, &tid)) {
        conjs.push(("returns Ok".into(), format!("({c})")));
    }
    let ret = ret
        .filter(|e| !matches!(e, Expr::Opaque(l, _) if l == "@vec" || l == "big"))
        .map(|e| lean_guard_term(&e, &args, &mut opmap, &mut oc, &mut decls, &tid))
        .unwrap_or_else(|| "(u.i 0)".into());
    RichBody { defs, post, writes, events, ret, conjs, unk_key }
}

/// Emit a relational abstraction of the contract: one `Step → Prop` per
/// entrypoint, in the style of stellar-lean-playground's `SorobanAmm.lean`,
/// built to OVER-approximate the contract: every successful invocation is a
/// step its entrypoint's predicate admits (for some choice of the values the
/// reconstruction leaves open), so a property proved of all admitted steps
/// holds of the contract. With `check`, also emit per-entrypoint checkers that
/// evaluate the same conjuncts on concrete steps (the conformance harness).
fn emit_lean_model(entries: &[ModelEntry], check: bool) {
    let san = |s: &str| s.chars().map(|c| if c.is_alphanumeric() { c } else { '_' }).collect::<String>();
    print!("{}", LEAN_PRELUDE);
    // the storage layout every entrypoint names its keys by.
    let layout = LAYOUT.with(|l| l.borrow().clone());
    if !layout.is_empty() {
        println!("/-! ## Storage layout -/\n");
        for (name, params, body) in &layout {
            let ps = if params.is_empty() { String::new() } else { format!(" {}", params.join(" ")) };
            println!("@[simp] def {name}{ps} : Key := {}", tidy(body));
        }
        println!();
    }
    for e in entries {
        let fn_id = san(&e.name);
        let ns = lean_ident(&fn_id);
        let rb = &e.rich;
        // the conjuncts, labelled (the checker evaluates exactly these).
        let mut conjs: Vec<(String, String)> = vec![
            ("fn".into(), format!("st.call.fn = \"{}\"", e.name)),
            ("not re-entrant".into(), "st.call.caller ≠ pool st".into()),
        ];
        conjs.extend(rb.conjs.iter().cloned());
        for g in &e.guards {
            if !conjs.iter().any(|(_, p)| *p == g.lean) {
                conjs.push((format!("gate: {}", g.comment), g.lean.clone()));
            }
        }
        // a named amount's / value's term is referred to by name wherever it
        // recurs (as a whole parenthesized term, so precedence can't change).
        let mut defs = rb.defs.clone();
        let (mut rpost, mut rret, mut rwrites) = (rb.post.clone(), rb.ret.clone(), format!("[{}]", rb.writes.join(", ")));
        // a pre-state read that recurs is named after its key: `pre_Minter_epoch_length`.
        {
            let all: String = defs.iter().map(|d| d.2.clone()).chain(conjs.iter().map(|c| c.1.clone())).chain([rpost.clone(), rret.clone()]).collect::<Vec<_>>().join("\n");
            let mut reads: BTreeMap<String, usize> = BTreeMap::new();
            for (i, _) in all.match_indices("(st.pre (") {
                let b: Vec<char> = all[i..].chars().collect();
                let mut depth = 0;
                let mut end = None;
                for (k, c) in b.iter().enumerate() {
                    match c {
                        '(' => depth += 1,
                        ')' => {
                            depth -= 1;
                            if depth == 0 {
                                end = Some(k);
                                break;
                            }
                        }
                        _ => {}
                    }
                }
                if let Some(k) = end {
                    let t: String = b[..=k].iter().collect();
                    if t.len() > 40 && !t.contains("@D:") {
                        *reads.entry(t).or_default() += 1;
                    }
                }
            }
            let mut named: Vec<(String, &'static str, String)> = vec![];
            for (t, n) in reads {
                if n < 2 {
                    continue;
                }
                let key = &t["(st.pre (".len()..t.len() - 2];
                let base = format!("pre_{}", key_name(key));
                let mut name = base.clone();
                let mut k = 1;
                while named.iter().any(|d| d.0 == name) || defs.iter().any(|d| d.0 == name) {
                    k += 1;
                    name = format!("{base}_{k}");
                }
                let by = format!("@D:{name}@");
                for d in defs.iter_mut() {
                    d.2 = d.2.replace(&t, &by);
                }
                for c in conjs.iter_mut() {
                    c.1 = c.1.replace(&t, &by);
                }
                for x in [&mut rpost, &mut rret, &mut rwrites] {
                    *x = x.replace(&t, &by);
                }
                named.push((name, "Int", t[1..t.len() - 1].to_string()));
            }
            named.extend(defs);
            defs = named;
        }
        for j in 0..defs.len() {
            let (n, ty, body) = defs[j].clone();
            if ty == "Storage" || !body.contains(' ') {
                continue;
            }
            let pat = if body.starts_with('(') && unparen(&body) != body { body.clone() } else { format!("({body})") };
            let by = format!("@D:{n}@");
            for d in defs.iter_mut().skip(j + 1) {
                d.2 = d.2.replace(&pat, &by);
            }
            for c in conjs.iter_mut() {
                c.1 = c.1.replace(&pat, &by);
            }
            for t in [&mut rpost, &mut rret, &mut rwrites] {
                *t = t.replace(&pat, &by);
            }
        }
        // named defs: which depend on the open values `u` (directly or through earlier ones).
        let mut open: Vec<(String, bool)> = vec![];
        for (n, _, body) in &defs {
            let o = body.contains("(u.") || open.iter().any(|(m, o)| *o && body.contains(&format!("@D:{m}@")));
            open.push((n.clone(), o));
        }
        let resolve = |t: &str| {
            let mut t = t.to_string();
            for (n, o) in &open {
                t = t.replace(&format!("@D:{n}@"), &if *o { format!("({ns}.{n} st u)") } else { format!("({ns}.{n} st)") });
            }
            tidy(&t)
        };
        let conjs: Vec<(String, String)> = conjs.into_iter().map(|(l, p)| (l, resolve(&p))).collect();
        let (post, ret) = (resolve(&rpost), resolve(&rret));
        let writes = resolve(&rwrites);
        // inputs: the scalar ABI args, and every input the model refers to.
        let mut inputs: BTreeMap<String, bool> = INPUTS.with(|m| m.borrow().get(&fn_id).cloned().unwrap_or_default());
        for (n, t) in &e.args {
            if matches!(t.as_str(), "Address" | "MuxedAddress") {
                inputs.entry(n.clone()).or_insert(true);
            } else if matches!(t.as_str(), "u32" | "i32" | "u64" | "i64" | "u128" | "i128" | "bool") {
                inputs.entry(n.clone()).or_insert(false);
            }
        }
        if !inputs.is_empty() || !defs.is_empty() {
            println!("namespace {ns}");
            for (n, addr) in &inputs {
                let path: Vec<String> = n.split('.').map(lean_ident).collect();
                let (ty, get) = if *addr { ("Addr", "argA") } else { ("Int", "arg") };
                println!("@[simp] def {} (st : Step) : {ty} := st.call.{get} \"{n}\"", path.join("."));
            }
            for ((n, ty, body), (_, o)) in defs.iter().zip(&open) {
                let u = if *o { " (u : Unk)" } else { "" };
                let b = resolve(body);
                // `st` as a whole word (an open value alone doesn't read it).
                let uses_st = b.match_indices("st").any(|(i, _)| {
                    let ok = |c: Option<char>| !c.is_some_and(|c| c.is_alphanumeric() || c == '_');
                    ok(b[..i].chars().last()) && ok(b[i + 2..].chars().next())
                });
                let st = if uses_st { "st" } else { "_st" };
                println!("@[simp] def {n} ({st} : Step){u} : {ty} :=\n  {}", unparen(&b));
            }
            println!("end {ns}\n");
        }
        let sig: Vec<String> = e.args.iter().map(|(n, t)| format!("{n}: {t}")).collect();
        println!("/-- `{}({})`: it succeeds exactly when `{ns}.Spec` holds.", e.name, sig.join(", "));
        if !rb.events.is_empty() {
            println!("    Its effects, in execution order:");
            for (j, ev) in rb.events.iter().enumerate() {
                let ev = resolve(ev);
                // `(x)` in a code span reads as `x`.
                let ev = ev.split('`').enumerate().map(|(i, part)| if i % 2 == 1 { unparen(part) } else { part.to_string() }).collect::<Vec<_>>().join("`");
                println!("    * `{ns}.s{}`: {ev}", j + 1);
            }
        }
        println!("-/");
        let text = format!("{} {post} {writes} {ret}", conjs.iter().map(|c| c.1.clone()).collect::<Vec<_>>().join(" "));
        let open = text.contains("(u.") || text.contains(" st u)");
        // the conditions as named fields: proofs say `h.post`, `h.auth_buyer`, `h.gate2`.
        let (mut ng, mut nx, mut na) = (0, 0, 0);
        let mut used: Vec<String> = vec![];
        let fields: Vec<(String, String, String)> = conjs
            .iter()
            .map(|(label, p)| {
                let name = if label == "fn" {
                    "fn".to_string()
                } else if label == "not re-entrant" {
                    "notReentrant".into()
                } else if label == "returns Ok" {
                    "ok".into()
                } else if label.starts_with("token transfer") {
                    nx += 1;
                    format!("xfer{nx}")
                } else if label.starts_with("require_auth ") {
                    na += 1;
                    // named after who signs: `auth_buyer`, `auth_Offer_seller`, `auth_Admin`.
                    let who = auth_who(p);
                    let who = who.strip_prefix("st.pre ").unwrap_or(&who).trim_end_matches(" st");
                    let who = who.rsplit_once('.').filter(|(h, _)| *h == ns).map(|(_, t)| t).unwrap_or(who);
                    let id: String = who.chars().map(|c| if c.is_alphanumeric() { c } else { '_' }).collect();
                    let n = if !id.is_empty() && id.len() < 40 { format!("auth_{}", id.trim_matches('_')) } else { format!("auth{na}") };
                    if used.contains(&n) { format!("auth{na}") } else { n }
                } else {
                    ng += 1;
                    format!("gate{ng}")
                };
                used.push(name.clone());
                (name, label.clone(), p.clone())
            })
            .collect();
        let uparam = if open { " (u : Unk)" } else { "" };
        println!("structure {ns}.Spec (st : Step){uparam} : Prop where");
        for (name, label, p) in &fields {
            let doc = if name == "notReentrant" {
                "not called by the contract itself (Soroban forbids re-entry)".to_string()
            } else if name.starts_with("xfer") {
                "the token accepts the transfer (SEP-41: a non-negative amount the sender holds)".to_string()
            } else if name.starts_with("auth") {
                let _ = label;
                format!("`{}` authorized the call (`require_auth`)", auth_who(p))
            } else if name == "ok" {
                "the call returns `Ok` (an `Err` fails it)".to_string()
            } else if name.starts_with("gate") {
                "the call panics unless this holds".to_string()
            } else {
                String::new()
            };
            if !doc.is_empty() {
                println!("  /-- {doc} -/");
            }
            println!("  {name} : {p}");
        }
        println!("  post : st.post = {post}");
        println!("  writes : st.writes = {writes}");
        println!("  ret : st.ret = {ret}\n");
        if open {
            println!("def {fn_id} : Step → Prop := fun st => ∃ u : Unk, {ns}.Spec st u\n");
        } else {
            println!("abbrev {fn_id} : Step → Prop := fun st => {ns}.Spec st\n");
        }
        if check {
            // the same terms, evaluated: (labelled conjuncts, post, writes, open key?).
            println!("def {fn_id}.check (st : Step) (u : Unk) : List (String × Bool) × Storage × List Key × Bool :=");
            println!("  let _ := u");
            let mut items: Vec<String> = conjs.iter().map(|(l, p)| format!("({:?}, decide ({p}))", l)).collect();
            items.push(format!("(\"ret\", decide (st.ret = {ret}))"));
            println!("  ([{}],\n   {post}, {writes}, {})\n", items.join(",\n    "), rb.unk_key);
        }
    }
    let names: Vec<String> = entries.iter().map(|e| san(&e.name)).filter(|n| n != "__constructor").collect();
    println!("/-- the contract's entry points (each a `Step → Prop`; the constructor runs");
    println!("    only at deployment, so it is not one of them). -/");
    println!("def entries : List (Step → Prop) := [{}]\n", names.join(", "));
    // what can change between two calls without the contract.
    let durs = DURABILITY.with(|d| d.borrow().clone());
    let expiring: Vec<(String, String)> = layout
        .iter()
        .filter(|(n, _, _)| !n.contains('.') && durs.get(n).is_none_or(|d| d == "temporary" || d == "?"))
        .filter_map(|(_, ps, body)| {
            let name = body.split('"').nth(1)?.to_string();
            let pat = if ps.is_empty() { format!(".var \"{name}\"") } else if body.starts_with(".entry") { format!(".entry \"{name}\" _") } else { format!(".tup \"{name}\" _") };
            Some((name, pat))
        })
        .collect();
    println!("/-- Keys in temporary storage: they can expire between calls. -/");
    println!("def temporary : Key → Bool");
    for (_, pat) in &expiring {
        println!("  | {pat} => true");
    }
    println!("  | .fld k _ => temporary k");
    println!("  | .has k => temporary k");
    println!("  | _ => false\n");
    println!("{}", LEAN_RUN);
    if check {
        let cs: Vec<String> = entries.iter().map(|e| format!("(\"{}\", {}.check)", e.name, san(&e.name))).collect();
        println!("def checkers : List (String × (Step → Unk → List (String × Bool) × Storage × List Key × Bool)) :=\n  [{}]\n", cs.join(",\n   "));
    }
    println!("end Contract");
}

/// The address of an auth conjunct `[(pc) →] who ∈ st.call.signers`.
fn auth_who(p: &str) -> String {
    let before = p.split(" ∈ st.call.signers").next().unwrap_or("");
    let who = match before.rsplit_once("→ ") {
        Some((_, w)) => w,
        None => before,
    };
    unparen(who)
}

/// An identifier for a rendered key: its layout name (`Minter.limit c m` ->
/// `Minter_limit`, `.has (Minter c m)` -> `has_Minter`).
fn key_name(k: &str) -> String {
    let t = k.trim_start_matches(['(', '.']);
    let (head, rest) = t.split_once(' ').unwrap_or((t, ""));
    let id = |s: &str| s.chars().map(|c| if c.is_alphanumeric() { c } else { '_' }).collect::<String>().trim_matches('_').to_string();
    if head == "has" {
        format!("has_{}", key_name(rest))
    } else {
        let h = id(head);
        if h.is_empty() { "v".into() } else { h }
    }
}

/// `t` without one pair of enclosing parentheses, if it has them.
fn unparen(t: &str) -> String {
    let t = t.trim();
    if t.starts_with('(') && t.ends_with(')') {
        let mut depth = 0;
        for (i, c) in t.char_indices() {
            match c {
                '(' => depth += 1,
                ')' => {
                    depth -= 1;
                    if depth == 0 && i + 1 < t.len() {
                        return t.to_string(); // `(a) (b)`: not one group
                    }
                }
                _ => {}
            }
        }
        return t[1..t.len() - 1].to_string();
    }
    t.to_string()
}

/// Drop redundant parentheses from a rendered Lean term: around an atom
/// (`(Offer)`, `(st.pre)`), and doubled ones (`((f x))`). Kept: `(-5)`, and a
/// group followed by `.` (`(s).set`).
fn tidy(t: &str) -> String {
    let b: Vec<char> = t.chars().collect();
    let mut close = vec![usize::MAX; b.len()];
    let mut stack = vec![];
    for (i, &c) in b.iter().enumerate() {
        match c {
            '(' => stack.push(i),
            ')' => {
                if let Some(o) = stack.pop() {
                    close[o] = i;
                }
            }
            '"' => {}
            _ => {}
        }
    }
    let mut drop = vec![false; b.len()];
    for o in 0..b.len() {
        let c = close[o];
        if b[o] != '(' || c == usize::MAX || drop[o] {
            continue;
        }
        let inner: String = b[o + 1..c].iter().collect();
        let atom = !inner.is_empty() && !inner.starts_with('-') && !inner.contains(' ') && !inner.contains('"') && !inner.contains('(');
        let doubled = b[o + 1] == '(' && close[o + 1] == c - 1;
        let dotted = b.get(c + 1) == Some(&'.');
        if doubled {
            // `((x))`: one pair goes — the inner one when the group is dotted.
            let (a, z) = if dotted { (o + 1, c - 1) } else { (o, c) };
            drop[a] = true;
            drop[z] = true;
        } else if atom && !dotted {
            drop[o] = true;
            drop[c] = true;
        }
    }
    b.iter().enumerate().filter(|(i, _)| !drop[*i]).map(|(_, c)| c).collect()
}

/// Outside activity and runs, after `entries` / `temporary`.
const LEAN_RUN: &str = r#"/-- What the rest of the ledger can do between two calls of the contract at `me`.
    Any token balance can change: other people's transfers, mints, tokens sent
    straight to the contract. The exception is the contract's own balances,
    which can only grow, since lowering them needs its authorization. The
    contract's own storage is untouched (only the contract writes it), except
    that temporary entries can expire. -/
def Outside (me : Addr) (s s' : Storage) : Prop :=
  ∀ k : Key, match k with
    | .bal t a => a = me → s (.bal t a) ≤ s' (.bal t a)
    | k => temporary k = true ∨ s' k = s k

/-- A history of the contract at `me`, from storage `s` to `t`: its calls (each
    admitted by one of its entry points) interleaved with outside activity. -/
inductive Run (me : Addr) : Storage → Storage → Prop
  | refl (s : Storage) : Run me s s
  | call {s : Storage} (st : Step) : Run me s st.pre → st.call.self = me →
      (∃ e ∈ entries, e st) → Run me s st.post
  | outside {s t t' : Storage} : Run me s t → Outside me t t' → Run me s t'
"#;

/// The fixed part of every emitted model.
const LEAN_PRELUDE: &str = r#"-- Auto-emitted by stellar-diver: a relational model of the contract, one
-- `Step → Prop` per entrypoint (in the style of SorobanAmm.lean), reconstructed
-- from the bytecode over call arguments, signers, storage and token ledgers.
--
-- It is built to OVER-approximate the contract: every successful invocation is
-- a step its entrypoint admits, for some choice of `u : Unk` (the values the
-- reconstruction leaves open). So a property proved of every admitted step
-- holds of the contract. Concretely:
--   * effects run in execution order as states s1, s2, …, each under the exact
--     condition its code runs in; a read sees the state at its program point;
--   * an effect the model doesn't interpret is not dropped: a call into another
--     contract leaves every token ledger open (`havoc`), an effect inside a
--     loop or past the analysis depth leaves all storage open;
--   * conditions to succeed: `require_auth` (the address is among the signers),
--     panics (`reach → pass`) and `Err` returns; a guard that can't be stated
--     is dropped, never guessed.
-- Storage keys: `.var` (unit variant), `.entry` / `.tup` (variants with one /
-- several fields), `.fld k f` (field f of the #[contracttype] struct at k),
-- `.has k` (k's presence: set → 1, remove → 0), `.bal t a` (token t's balance
-- of a). Struct arguments' fields are args named like `config.limit`.
--
-- Assumes: tokens the contract calls `transfer` / `balance` on behave per
-- SEP-41; addresses are encoded as `Addr` in the host's order (`obj_cmp`).

namespace Contract

abbrev Addr := Int

inductive Key where
  | var   (name : String)
  | entry (map : String) (k : Addr)
  | tup   (map : String) (ks : List Int)
  | fld   (base : Key) (f : String)
  | has   (k : Key)
  | bal   (t : Addr) (a : Addr)
  deriving DecidableEq, Inhabited, Repr

abbrev Storage := Key → Int
def Storage.set (s : Storage) (k : Key) (v : Int) : Storage := fun k' => if k' = k then v else s k'

structure Call where
  fn      : String
  caller  : Addr
  self    : Addr           -- the contract's own address
  arg     : String → Int   -- numeric args by name
  argA    : String → Addr  -- address args by name
  signers : List Addr      -- addresses that authorized the call (require_auth)
  env     : String → Int   -- ledger info (`sequence`, `timestamp`)

structure Step where
  call   : Call
  pre    : Storage
  post   : Storage
  writes : List Key
  ret    : Int

/-- Values the reconstruction leaves open, chosen per step. -/
structure Unk where
  i : Nat → Int      -- values
  g : Nat → Int      -- guard operands
  b : Nat → Bool     -- branch conditions
  k : Nat → Key      -- storage keys
  s : Nat → Storage  -- storage after an effect the model doesn't interpret

/-- the contract's own address (`e.current_contract_address()`). -/
@[simp] def pool (st : Step) : Addr := st.call.self

/-- token `t`'s balance of `a`. -/
def bal (t : Addr) (s : Storage) (a : Addr) : Int := s (.bal t a)
/-- storage after token `t` moves `amt` from `src` to `dst` (a self-transfer nets to zero). -/
def xfer (t : Addr) (s : Storage) (src dst : Addr) (amt : Int) : Storage :=
  let s1 := s.set (.bal t src) (bal t s src - amt)
  s1.set (.bal t dst) (bal t s1 dst + amt)
@[simp] theorem Storage.set_get (s : Storage) (k k' : Key) (v : Int) :
    (s.set k v) k' = if k' = k then v else s k' := rfl
/-- a balance after a transfer: plus what came in, minus what went out. -/
@[simp] theorem bal_xfer (t t' : Addr) (s : Storage) (src dst : Addr) (amt : Int) (a : Addr) :
    bal t (xfer t' s src dst amt) a
      = bal t s a + (if t = t' ∧ a = dst then amt else 0) - (if t = t' ∧ a = src then amt else 0) := by
  simp only [bal, xfer, Storage.set_get, Key.bal.injEq]
  by_cases h1 : a = dst <;> by_cases h2 : a = src <;> by_cases h3 : t = t' <;> simp_all <;> omega
/-- a transfer touches only balances. -/
@[simp] theorem xfer_other (t : Addr) (s : Storage) (src dst : Addr) (amt : Int) (k : Key)
    (h : ∀ t a, k ≠ .bal t a) : xfer t s src dst amt k = s k := by
  simp only [xfer, Storage.set_get]; simp [h]
/-- a write to a key that isn't a balance leaves every balance alone. -/
@[simp] theorem bal_set (t : Addr) (s : Storage) (k : Key) (v : Int) (a : Addr) (h : ∀ t a, k ≠ .bal t a) :
    bal t (s.set k v) a = bal t s a := by
  simp only [bal, Storage.set_get]; simp [Ne.symm (h t a)]

/-- SEP-41: a transfer succeeds only for a non-negative amount the sender holds. -/
abbrev xferOk (t : Addr) (s : Storage) (src _dst : Addr) (amt : Int) : Prop := 0 ≤ amt ∧ amt ≤ bal t s src
/-- storage after a call into another contract the model doesn't interpret: the
    contract's own storage is unchanged (Soroban forbids re-entry); token
    ledgers take `h`'s values. -/
def havoc (s h : Storage) : Storage := fun k => match k with
  | .bal t a => h (.bal t a)
  | _ => s k
/-- `get(k).unwrap_or(0)`: the value at `k`, or 0 when `base` (k's struct) is absent. -/
def getOr0 (s : Storage) (k : Key) (base : Key := k) : Int := if s (.has base) = 1 then s k else 0

"#;

/// Emit a Lean token-conservation model for an AMM: every SEP-41 transfer (found
/// transitively, any depth) moves an amount between `ext` (external parties),
/// `pool` (the contract) and `other` (unresolved). The amounts are action inputs
/// (the nonlinear swap output is just another input), so conservation of the
/// total is LINEAR and `omega` proves it across every entrypoint.
fn emit_lean_amm(entries: &[(String, Vec<(&'static str, &'static str, bool)>)]) {
    println!("-- Auto-emitted by stellar-diver from lifted LLVM IR (real AMM, any depth).");
    println!("-- Token movements are the SEP-41 transfers recovered transitively through the");
    println!("-- contract's fastcc helpers. Amounts are action inputs (the nonlinear swap");
    println!("-- output is just an unconstrained input), so conservation is linear: `omega`.");
    println!("-- Parties: ext = external caller/destination, pool = the AMM, other = UNRESOLVED.\n");
    println!("namespace AMM\n");
    println!("structure State where");
    println!("  ext : Int   -- aggregate external-party token holdings");
    println!("  pool : Int  -- the AMM's token holdings");
    println!("  other : Int -- tokens sent to unresolved recipients (should stay 0)");
    println!("  c0 : Int    -- initial total (constant)\n");

    println!("inductive Action where");
    for (name, pairs) in entries {
        let c = lean_ctor(name);
        if pairs.is_empty() {
            println!("  | {c} : Action");
        } else {
            let ps: Vec<String> = (0..pairs.len()).map(|k| format!("(a{k} : Int)")).collect();
            println!("  | {c} {} : Action", ps.join(" "));
        }
    }
    println!();

    // guard: transfer amounts are non-negative (SEP-41).
    println!("def guard : Action → Prop");
    for (name, pairs) in entries {
        let c = lean_ctor(name);
        let bind: String = (0..pairs.len()).map(|k| format!(" a{k}")).collect();
        if pairs.is_empty() {
            println!("  | .{c} => True");
        } else {
            let conj: Vec<String> = (0..pairs.len()).map(|k| format!("a{k} ≥ 0")).collect();
            println!("  | .{c}{bind} => {}", conj.join(" ∧ "));
        }
    }
    println!();

    // step: apply each transfer's delta to its two parties.
    println!("def step (s : State) : Action → State");
    for (name, pairs) in entries {
        let c = lean_ctor(name);
        let bind: String = (0..pairs.len()).map(|k| format!(" a{k}")).collect();
        if pairs.is_empty() {
            println!("  | .{c} => s");
            continue;
        }
        let mut upd = vec![];
        for p in ["ext", "pool", "other"] {
            let mut e = format!("s.{p}");
            let mut touched = false;
            for (k, (from, to, _)) in pairs.iter().enumerate() {
                if *to == p {
                    e.push_str(&format!(" + a{k}"));
                    touched = true;
                }
                if *from == p {
                    e.push_str(&format!(" - a{k}"));
                    touched = true;
                }
            }
            if touched {
                upd.push(format!("{p} := {e}"));
            }
        }
        if upd.is_empty() {
            println!("  | .{c}{bind} => s");
        } else {
            println!("  | .{c}{bind} => {{ s with {} }}", upd.join(", "));
        }
    }
    println!();

    println!("def init (e p o : Int) : State := {{ ext := e, pool := p, other := o, c0 := e + p + o }}\n");

    println!("-- ===== INVARIANT: the AMM creates/destroys no tokens (aggregate conservation) =====");
    println!("def Inv (s : State) : Prop := s.ext + s.pool + s.other = s.c0\n");

    println!("theorem init_holds (e p o : Int) : Inv (init e p o) := by");
    println!("  simp only [Inv, init] <;> omega\n");

    println!("-- PROVED across EVERY entrypoint of the real AMM, by omega (amounts arbitrary):");
    println!("theorem conserved (s : State) (a : Action) (h : Inv s) (g : guard a) :");
    println!("    Inv (step s a) := by");
    println!("  cases a <;> simp_all [Inv, step] <;> omega\n");

    // provenance: list each entry's recovered transfers and flag unresolved recipients.
    println!("/- recovered transfer structure (provenance):");
    for (name, pairs) in entries {
        if pairs.is_empty() {
            continue;
        }
        let leak = pairs.iter().any(|(_, _, resolved)| !*resolved);
        let flag = if leak { "   <-- UNRESOLVED recipient (review)" } else { "" };
        print!("   {name}:{flag}\n");
        for (from, to, _) in pairs {
            println!("      {from} -> {to}");
        }
    }
    println!("-/");
    println!("\nend AMM");
}

/// Render a recovered value Expr as Lean, over the entry's args; None if any
/// part is opaque (unrecovered), which makes the slot not provably updated.
fn lean_of_expr(e: &Expr, args: &Args) -> Option<String> {
    match e {
        Expr::Slot(dur, _) => Some(format!("s.{dur}")),
        Expr::Param(i) => args.get(*i).map(|(_, n, _)| n.clone()),
        Expr::Const(k) => Some(k.to_string()),
        Expr::Bin(op, a, b) => {
            let a = lean_of_expr(a, args)?;
            let b = lean_of_expr(b, args)?;
            Some(format!("({a} {op} {b})"))
        }
        Expr::VecGet(_, _) => None, // handled by the array-aware CPMM recognizer
        Expr::Opaque(_, _) => None,
    }
}

/// One entry's pool transition: name, amount arg, per-slot recovered update
/// (None = opaque), recovered success guards, whether a SEP-41 transfer occurs.
struct PoolEntry {
    name: String,
    amount: Option<String>,
    updates: Vec<(String, Option<String>, bool)>, // (slot dur, lean update expr | None, is-arithmetic)
    guards: Vec<String>,
    has_transfer: bool,
}

/// Emit a Lean no-drain proof: tracked storage slots never go negative, proved
/// over the RECOVERED update expressions and guards. Only slots with numeric
/// (arithmetic) updates are tracked; the theorem is emitted only when every
/// tracked update recovered cleanly, otherwise the opaque ones are reported.
fn emit_lean_pool(entries: &[PoolEntry]) {
    // tracked slots = durabilities that get an ARITHMETIC (read-modify-write)
    // update somewhere — a balance/reserve, not a plain address store. Tracked
    // even when the operands are opaque, so an unrecovered reserve update is
    // flagged infeasible rather than silently dropped into a vacuous Inv.
    let mut tracked: BTreeSet<String> = BTreeSet::new();
    for e in entries {
        for (dur, _upd, arith) in &e.updates {
            if *arith {
                tracked.insert(dur.clone());
            }
        }
    }
    // feasibility: a tracked slot must never be written opaquely.
    let mut opaque_hits = vec![];
    for e in entries {
        for (dur, upd, _) in &e.updates {
            if tracked.contains(dur) && upd.is_none() {
                opaque_hits.push((e.name.clone(), dur.clone()));
            }
        }
    }

    println!("-- Auto-emitted by stellar-diver from lifted LLVM IR.");
    println!("-- No-drain: each tracked storage slot (a balance/reserve) stays >= 0 across every");
    println!("-- entrypoint, proved over the RECOVERED update expressions and guards.");
    println!("-- i128/u128 modelled as unbounded Int (sound under the contract's range checks).\n");
    println!("namespace Pool\n");
    println!("structure State where");
    for d in &tracked {
        println!("  {d} : Int   -- storage.{d}[user] (a balance/reserve)");
    }
    println!();

    println!("inductive Action where");
    for e in entries {
        let c = lean_ctor(&e.name);
        match &e.amount {
            Some(a) => println!("  | {c} ({a} : Int) : Action"),
            None => println!("  | {c} : Action"),
        }
    }
    println!();

    println!("def guard (s : State) : Action → Prop");
    for e in entries {
        let c = lean_ctor(&e.name);
        let bind = e.amount.as_ref().map(|a| format!(" {a}")).unwrap_or_default();
        let mut parts = e.guards.clone();
        if e.has_transfer {
            if let Some(a) = &e.amount {
                parts.push(format!("{a} ≥ 0"));
            }
        }
        let body = if parts.is_empty() { "True".into() } else { parts.join(" ∧ ") };
        println!("  | .{c}{bind} => {body}");
    }
    println!();

    println!("def step (s : State) : Action → State");
    for e in entries {
        let c = lean_ctor(&e.name);
        let bind = e.amount.as_ref().map(|a| format!(" {a}")).unwrap_or_default();
        let upd: Vec<String> = e
            .updates
            .iter()
            .filter(|(d, _, _)| tracked.contains(d))
            .filter_map(|(d, u, _)| u.as_ref().map(|e| format!("{d} := {e}")))
            .collect();
        if upd.is_empty() {
            println!("  | .{c}{bind} => s");
        } else {
            println!("  | .{c}{bind} => {{ s with {} }}", upd.join(", "));
        }
    }
    println!();

    println!("def Inv (s : State) : Prop :=");
    let conj: Vec<String> = tracked.iter().map(|d| format!("s.{d} ≥ 0")).collect();
    println!("  {}\n", if conj.is_empty() { "True".into() } else { conj.join(" ∧ ") });

    if opaque_hits.is_empty() {
        println!("-- NO-DRAIN, proved across every entrypoint by omega (over recovered updates):");
        println!("theorem no_drain (s : State) (a : Action) (h : Inv s) (g : guard s a) :");
        println!("    Inv (step s a) := by");
        println!("  cases a <;> simp_all [Inv, guard, step] <;> omega");
    } else {
        println!("-- NOT YET FEASIBLE: these entrypoints write a tracked slot with an update the");
        println!("-- abstraction could not recover (opaque, interprocedurally spilled):");
        for (n, d) in &opaque_hits {
            println!("--   {n} writes storage.{d} opaquely");
        }
        println!("-- (model emitted above; the no_drain theorem is withheld until these recover.)");
    }
    println!("\nend Pool");
}

/// Recognize the constant-product swap in an entry's recovered storage writes:
///   x-reserve := x + dx        and        y-reserve := y - (y*dx)/(x+dx)
/// Returns (x durability, y durability, dx arg name) when it matches. This is
/// what ties the emitted no-drain proof to the actual bytecode.
fn recognize_cpmm(writes: &[(String, usize, Expr)], args: &Args) -> Option<(String, String, String)> {
    let slot = |e: &Expr| if let Expr::Slot(d, _) = e { Some(d.clone()) } else { None };
    let param = |e: &Expr| if let Expr::Param(i) = e { Some(*i) } else { None };
    // x-reserve: d := Slot(d) + Param(dx)
    let mut xinfo: Option<(String, usize)> = None;
    for (d, _, e) in writes {
        if let Expr::Bin('+', a, b) = e {
            if slot(a).as_deref() == Some(d) {
                if let Some(dx) = param(b) {
                    xinfo = Some((d.clone(), dx));
                }
            }
        }
    }
    let (xdur, dx) = xinfo?;
    // y-reserve: d := Slot(d) - ((Slot(d) * Param(dx)) / (Slot(xdur) + Param(dx)))
    for (d, _, e) in writes {
        if let Expr::Bin('-', y1, divv) = e {
            if slot(y1).as_deref() != Some(d) {
                continue;
            }
            if let Expr::Bin('/', num, den) = &**divv {
                if let (Expr::Bin('*', ya, dxa), Expr::Bin('+', xa, dxb)) = (&**num, &**den) {
                    let ok = slot(ya).as_deref() == Some(d)
                        && param(dxa) == Some(dx)
                        && slot(xa).as_deref() == Some(&xdur)
                        && param(dxb) == Some(dx);
                    if ok {
                        let dxname = args.get(dx).map(|(_, n, _)| n.clone()).unwrap_or_else(|| "dx".into());
                        return Some((xdur, d.clone(), dxname));
                    }
                }
            }
        }
    }
    None
}

/// Emit the constant-product NO-DRAIN proof (core Lean 4, no Mathlib). When the
/// constant-product swap formula is RECOGNIZED in the recovered writes, the
/// anti-drain bound `out*(x+dx) ≤ y*dx` is DISCHARGED from the recovered floor
/// division (Nat.div_mul_le_self) -- not assumed. Otherwise the proof is withheld.
fn emit_lean_cpmm_proved(recognized: &[(String, String, String, String)]) {
    if recognized.is_empty() {
        println!("-- Auto-emitted by stellar-diver: the constant-product swap formula");
        println!("-- (x += dx ; y -= y*dx/(x+dx)) was NOT recognized in any entrypoint's");
        println!("-- recovered storage writes, so the no-drain proof is withheld.");
        println!("-- (Run --expr-dbg to see the recovered update expressions.)");
        return;
    }
    println!("-- Auto-emitted by stellar-diver from lifted LLVM IR.");
    println!("-- Constant-product NO-DRAIN, RECOGNIZED in the recovered bytecode:");
    for (ent, xd, yd, dxn) in recognized {
        println!("--   {ent}: x=storage.{xd}, y=storage.{yd}, dx={dxn}");
        println!("--     x := x + {dxn};  y := y - (y*{dxn})/(x+{dxn})   [matches y*dx/(x+dx)]");
    }
    println!("-- The anti-drain bound out*(x+dx) ≤ y*dx is DISCHARGED from the recovered");
    println!("-- floor division (Nat.div_mul_le_self) -- it is NOT assumed.\n");
    println!("namespace Pool");
    println!("-- Reserves x, y as Nat. Recovered swap: x := x + dx ;  y := y - out,");
    println!("-- where out = y*dx / (x+dx)  (floor division, as in the bytecode).\n");
    println!("def out (x y dx : Nat) : Nat := y * dx / (x + dx)");
    println!("def Inv (x y k0 : Nat) : Prop := k0 ≤ x * y\n");
    println!("theorem no_drain_step (x y dx k0 : Nat) (hi : Inv x y k0) :");
    println!("    Inv (x + dx) (y - out x y dx) k0 := by");
    println!("  unfold Inv at *");
    println!("  have hfloor : out x y dx * (x + dx) ≤ y * dx := Nat.div_mul_le_self (y * dx) (x + dx)");
    println!("  have hdist  : (x + dx) * (y - out x y dx) = (x + dx) * y - (x + dx) * out x y dx := Nat.mul_sub _ _ _");
    println!("  have hxy    : (x + dx) * y = x * y + dx * y := Nat.add_mul x dx y");
    println!("  have hc1    : y * dx = dx * y := Nat.mul_comm y dx");
    println!("  have hc2    : out x y dx * (x + dx) = (x + dx) * out x y dx := Nat.mul_comm _ _");
    println!("  rw [hdist, hxy]; omega\n");
    println!("inductive Reach (x0 y0 : Nat) : Nat → Nat → Prop where");
    println!("  | refl : Reach x0 y0 x0 y0");
    println!("  | step {{x y dx}} : Reach x0 y0 x y → Reach x0 y0 (x + dx) (y - out x y dx)\n");
    println!("-- NO-DRAIN: product ≥ k0 at every reachable state -- the pool cannot be drained.");
    println!("theorem no_drain (x0 y0 k0 x y : Nat) (hi : Inv x0 y0 k0) (r : Reach x0 y0 x y) :");
    println!("    Inv x y k0 := by");
    println!("  induction r with");
    println!("  | refl => exact hi");
    println!("  | step _ ih => exact no_drain_step _ _ _ _ ih\n");
    println!("-- from initial product k0 = x0*y0, every reachable state has x*y ≥ k0.");
    println!("theorem product_floor (x0 y0 x y : Nat) (r : Reach x0 y0 x y) : x0 * y0 ≤ x * y :=");
    println!("  no_drain x0 y0 (x0 * y0) x y (Nat.le_refl _) r\n");
    println!("end Pool");
}

/// Build the transition record for one entry: amount arg, recovered success
/// guards, storage updates, SEP-41 direction, auth. Returns the slot durabilities
/// it touches so the caller can assemble the shared state signature.
fn build_trans<'c>(
    f: FunctionValue<'c>,
    module: &inkwell::module::Module<'c>,
    callee: &str,
) -> (Trans, BTreeSet<String>) {
    let args = arg_table(f);
    let name = f.get_name().to_string_lossy().into_owned();
    let mut slots = BTreeSet::new();

    let amount = args
        .iter()
        .find(|(_, _, t)| matches!(t.as_str(), "i128" | "u128" | "u64" | "i64" | "u32" | "i32"))
        .map(|(_, n, _)| n.clone());

    // success guards = negated revert conditions, with recovered operators.
    let cfg = Cfg::build(f);
    let cd = control_deps(&cfg, &ipostdoms(&cfg));
    let mut guards = vec![];
    let mut seen = HashSet::new();
    for s in find_sinks(&cfg, &[SinkKind::Trap, SinkKind::Error, SinkKind::ErrorReturn], callee, None) {
        let slice = backward_slice(&cfg, &cd, &s.vals, &[s.instr]);
        let r = classify(&slice, s.instr);
        for (_br, c) in &r.guards {
            if let Some((op, a, b)) = gate_rel(*c, &args) {
                if let (Some(ls), Some(rs)) = (side_smt(&a), side_smt(&b)) {
                    for side in [&a, &b] {
                        if let Some(Src::Store { dur, .. }) = side.iter().next() {
                            slots.insert(dur.clone());
                        }
                    }
                    let key = format!("{} {} {}", op.negate().lean(), ls, rs);
                    if seen.insert(key) {
                        guards.push((op.negate(), ls, rs));
                    }
                }
            }
        }
    }

    // storage updates (direct + one-level setters).
    let ups = write_updates(f, module, &args);
    let mut writes: Vec<(String, char, String)> = vec![];
    let mut prov = vec![];
    let sig: Vec<String> = args.iter().filter(|(_, _, t)| !t.is_empty()).map(|(_, n, t)| format!("{n}: {t}")).collect();
    prov.push(format!("action {name}({})", sig.join(", ")));
    for u in &ups {
        let Src::Store { dur, params } = &u.slot else { continue };
        slots.insert(dur.clone());
        let sv = format!("s_{dur}");
        let amt = u.amount.iter().find_map(|s| match s {
            Src::Arg(n) => Some(n.clone()),
            _ => None,
        });
        prov.push(format!(
            "write storage.{dur}[{}]  op '{}'  amount {:?}",
            params.join(","),
            u.op,
            u.amount.iter().map(Src::show).collect::<Vec<_>>()
        ));
        match (u.op, amt) {
            ('-', Some(a)) => writes.push((sv, '-', a)),
            ('+', Some(a)) => writes.push((sv, '+', a)),
            _ => writes.push((sv, '?', format!("h_{dur}_{name}"))),
        }
    }

    let dir = transfer_dirs(f, &args).iter().sum::<i32>().signum();
    let auth = auth_of(f, &args);
    prov.push(format!("sep41 net direction on user: {dir}  (+recv / -send)"));

    (Trans { action: name, amount, guards, writes, ext: dir, auth, prov }, slots)
}

// ======================= storage-schema export =======================

/// The ABI type of a stored/read Val: an arg's spec type, or the Val tag.
fn abi_type_of(v: BasicValueEnum, args: &Args) -> String {
    if let Some((_, _, t)) = args.iter().find(|(pv, _, _)| *pv == v) {
        if !t.is_empty() {
            return t.clone();
        }
    }
    if let Some(i) = as_instr(v) {
        let n = callee_name(i).unwrap_or_default();
        if n.contains("from_payload") {
            if let Some(Operand::Value(BasicValueEnum::IntValue(c))) = i.get_operand(0) {
                if c.is_const() {
                    if let Some(k) = c.get_zero_extended_constant() {
                        return tag_name(k & 0xff).into();
                    }
                }
            }
            if let Some(Operand::Value(inner)) = i.get_operand(0) {
                return abi_type_of(inner, args);
            }
        }
        if n.contains("val.payload") {
            if let Some(Operand::Value(inner)) = i.get_operand(0) {
                return abi_type_of(inner, args);
            }
        }
        if n.contains("obj_from_i128") || n.contains("obj_to_i128") {
            return "i128".into();
        }
        if n.contains("obj_from_u128") || n.contains("obj_to_u128") {
            return "u128".into();
        }
    }
    "?".into()
}

/// The contract's `DataKey` builder: a function with a `switch` (the variant
/// discriminant) whose cases build symbol vectors. One per contract.
fn datakey_builder<'c>(module: &inkwell::module::Module<'c>) -> Option<FunctionValue<'c>> {
    for f in module.get_functions() {
        if f.count_basic_blocks() == 0 || f.get_params().len() < 2 {
            continue;
        }
        let has_switch = all_instrs(f).iter().any(|i| i.get_opcode() == InstructionOpcode::Switch);
        let has_symbol = all_instrs(f).iter().any(|i| callee_has(*i, "symbol_new_from_linear_memory"));
        if has_switch && has_symbol {
            return Some(f);
        }
    }
    None
}

/// For the builder `kb`, which discriminants are *data* variants — i.e. their
/// switch case actually uses the field parameter `%1` (stores it into the key
/// vector). Returns (per-case usage, default-case usage). A used field ⇒ mapping.
fn kb_field_usage<'c>(kb: FunctionValue<'c>) -> (BTreeMap<i64, bool>, bool) {
    let mut cases: BTreeMap<i64, bool> = BTreeMap::new();
    let mut dflt = false;
    let Some(field) = kb.get_nth_param(1) else { return (cases, dflt) };
    let Some(sw) = all_instrs(kb).into_iter().find(|i| i.get_opcode() == InstructionOpcode::Switch) else {
        return (cases, dflt);
    };
    let cfg = Cfg::build(kb);
    let bidx = |b: BasicBlock<'c>| cfg.blocks.iter().position(|x| *x == b);
    // does `field` appear in any instruction reachable from block `start` (within kb)?
    let uses_field_from = |start: usize| -> bool {
        let mut seen = vec![false; cfg.blocks.len()];
        let mut work = vec![start];
        while let Some(b) = work.pop() {
            if seen[b] {
                continue;
            }
            seen[b] = true;
            let mut it = cfg.blocks[b].get_first_instruction();
            while let Some(i) = it {
                for k in 0..i.get_num_operands() {
                    if matches!(i.get_operand(k), Some(Operand::Value(v)) if v == field) {
                        return true;
                    }
                }
                it = i.get_next_instruction();
            }
            work.extend(cfg.succ[b].iter().copied());
        }
        false
    };
    // switch operands: 0=cond, 1=default block, then (value, block) pairs.
    if let Some(Operand::Block(db)) = sw.get_operand(1) {
        if let Some(d) = bidx(db) {
            dflt = uses_field_from(d);
        }
    }
    let n = sw.get_num_operands();
    let mut k = 2;
    while k + 1 < n {
        let val = match sw.get_operand(k) {
            Some(Operand::Value(BasicValueEnum::IntValue(c))) => c.get_sign_extended_constant(),
            _ => None,
        };
        let blk = match sw.get_operand(k + 1) {
            Some(Operand::Block(b)) => bidx(b),
            _ => None,
        };
        if let (Some(v), Some(b)) = (val, blk) {
            cases.insert(v, uses_field_from(b));
        }
        k += 2;
    }
    (cases, dflt)
}

/// Read-only data segments the front-end recorded as `soroban.rodata` metadata
/// (each node is `"<base> <hex>"`), so we can resolve a symbol `(offset, len)`
/// that is constant only at a builder call site back to the text sitting in the
/// data segment. Empty when the front-end could not record rodata (e.g. a wasm
/// whose memory is written, or an IR with no such metadata).
fn rodata_segs(module: &inkwell::module::Module) -> Vec<(u64, Vec<u8>)> {
    let mut segs = vec![];
    for node in module.get_global_metadata("soroban.rodata") {
        let Some(vals) = node.get_node_values() else { continue };
        for v in vals {
            let BasicMetadataValueEnum::MetadataValue(mv) = v else { continue };
            let Some(raw) = mv.get_string_value() else { continue };
            let s = String::from_utf8_lossy(raw);
            let Some((base, hex)) = s.split_once(' ') else { continue };
            let Ok(base) = base.parse::<u64>() else { continue };
            let bytes: Option<Vec<u8>> = (0..hex.len() / 2)
                .map(|j| u8::from_str_radix(&hex[2 * j..2 * j + 2], 16).ok())
                .collect();
            if let Some(bytes) = bytes {
                segs.push((base, bytes));
            }
        }
    }
    segs
}

/// The little-endian u32 at `addr` in the recorded rodata. The encoder trims a
/// segment's trailing zeros, so past a segment's end, up to the next segment,
/// memory is zero (cf. the front end's `Mem::bytes`).
fn rodata_u32(segs: &[(u64, Vec<u8>)], addr: u64) -> Option<u32> {
    let (base, b) = segs.iter().filter(|(base, _)| *base <= addr).max_by_key(|(base, _)| *base)?;
    let next = segs.iter().map(|(b2, _)| *b2).filter(|b2| b2 > base).min()?;
    if addr + 4 > next {
        return None;
    }
    let k = (addr - base) as usize;
    let bytes: Vec<u8> = (k..k + 4).map(|j| b.get(j).copied().unwrap_or(0)).collect();
    Some(u32::from_le_bytes(bytes.try_into().ok()?))
}

/// The text of a `[offset, offset+len)` slice of the recorded rodata.
fn rodata_text(segs: &[(u64, Vec<u8>)], off: u64, len: u64) -> Option<String> {
    for (base, bytes) in segs {
        if off >= *base {
            let s = (off - base) as usize;
            if s + len as usize <= bytes.len() {
                return Some(String::from_utf8_lossy(&bytes[s..s + len as usize]).into_owned());
            }
        }
    }
    None
}

/// A constant `(offset, len)` argument to a symbol builder: either a raw i64
/// literal (the `f(dest, offset, len)` helper style) or a `%Val` made by
/// `from_payload` of a packed u32 (`symbol_new_from_linear_memory(%Val, %Val)`).
fn symbol_arg(i: InstructionValue, k: u32) -> Option<u64> {
    let Some(Operand::Value(op)) = i.get_operand(k) else { return None };
    if let BasicValueEnum::IntValue(v) = op {
        return if v.is_const() { v.get_zero_extended_constant() } else { None };
    }
    let def = as_instr(op)?;
    if callee_name(def)?.contains("from_payload") {
        let Some(Operand::Value(BasicValueEnum::IntValue(c))) = def.get_operand(0) else { return None };
        if !c.is_const() {
            return None;
        }
        let raw = c.get_zero_extended_constant()?;
        // positions/lengths cross the host boundary as U32Vals: tag 4, value in
        // the top 32 bits.
        return Some(if raw & 0xff == 4 { raw >> 32 } else { raw });
    }
    None
}

/// If `i` builds a `Symbol` from linear memory, its `(offset, len)` — directly
/// via `symbol_new_from_linear_memory`, or via a helper (e.g. `f38`) that does,
/// whose two constant args are the offset and length.
fn symbol_off_len<'c>(i: InstructionValue<'c>, module: &inkwell::module::Module<'c>) -> Option<(u64, u64)> {
    let cname = callee_name(i)?;
    if cname.contains("symbol_new_from_linear_memory") {
        return Some((symbol_arg(i, 0)?, symbol_arg(i, 1)?));
    }
    let h = module.get_function(&cname)?;
    if h.count_basic_blocks() > 0 && all_instrs(h).iter().any(|x| callee_has(*x, "symbol_new_from_linear_memory")) {
        let argc = i.get_num_operands().saturating_sub(1); // last operand is the callee
        let consts: Vec<u64> = (0..argc).filter_map(|k| symbol_arg(i, k)).collect();
        if consts.len() >= 2 {
            return Some((consts[consts.len() - 2], consts[consts.len() - 1]));
        }
    }
    None
}

/// The `DataKey` variant *name* for discriminant `disc`: the builder switches on
/// `disc` and each case constructs the variant's `Symbol` from the rodata blob,
/// so we walk to that case's block and read the symbol text.
fn datakey_name<'c>(
    kb: FunctionValue<'c>,
    disc: i64,
    module: &inkwell::module::Module<'c>,
    segs: &[(u64, Vec<u8>)],
) -> Option<String> {
    let cfg = Cfg::build(kb);
    // the block for this discriminant: a matching explicit case, else the default.
    let cases = kb_cases(kb);
    let target = cases.iter().find(|(d, _)| *d == Some(disc)).or_else(|| cases.iter().find(|(d, _)| d.is_none())).and_then(|(_, b)| cfg.bidx(*b));
    // the first symbol builder reachable from that block.
    let mut seen = vec![false; cfg.blocks.len()];
    let mut work = vec![target?];
    while let Some(b) = work.pop() {
        if seen[b] {
            continue;
        }
        seen[b] = true;
        let mut it = cfg.blocks[b].get_first_instruction();
        while let Some(i) = it {
            if let Some((off, len)) = symbol_off_len(i, module) {
                if let Some(t) = rodata_text(segs, off, len) {
                    return Some(t);
                }
            }
            it = i.get_next_instruction();
        }
        work.extend(cfg.succ[b].iter().copied());
    }
    None
}

/// Resolve a storage key to its `DataKey` discriminant and (if a data variant)
/// the field argument — looking through Val wrappers, a direct builder call, or
/// a forwarder helper that calls the builder with a constant discriminant.
fn resolve_disc_field<'c>(
    key: BasicValueEnum<'c>,
    kb: FunctionValue<'c>,
    module: &inkwell::module::Module<'c>,
) -> Option<(i64, Option<BasicValueEnum<'c>>)> {
    let kb_name = kb.get_name().to_string_lossy().into_owned();
    let mut cur = key;
    for _ in 0..8 {
        let i = as_instr(cur)?;
        let n = callee_name(i)?;
        if n == kb_name {
            // direct builder call: first const operand = disc, the other = field.
            let mut disc = None;
            let mut field = None;
            for k in 0..i.get_num_operands().saturating_sub(1) {
                if let Some(Operand::Value(o)) = i.get_operand(k) {
                    match o {
                        BasicValueEnum::IntValue(c) if c.is_const() && disc.is_none() => {
                            disc = c.get_sign_extended_constant();
                        }
                        _ => field = Some(o),
                    }
                }
            }
            return disc.map(|d| (d, field));
        }
        if n.contains("from_payload") || n.contains("val.payload") {
            if let Some(Operand::Value(inner)) = i.get_operand(0) {
                cur = inner;
                continue;
            }
        }
        // a forwarder helper: find its internal call to the builder with a const disc.
        if let Some(h) = module.get_function(&n) {
            if h.count_basic_blocks() > 0 {
                for hi in all_instrs(h) {
                    if callee_name(hi).as_deref() == Some(kb_name.as_str()) {
                        let mut disc = None;
                        let mut fparam: Option<usize> = None;
                        for k in 0..hi.get_num_operands().saturating_sub(1) {
                            if let Some(Operand::Value(o)) = hi.get_operand(k) {
                                match o {
                                    BasicValueEnum::IntValue(c) if c.is_const() && disc.is_none() => {
                                        disc = c.get_sign_extended_constant();
                                    }
                                    _ => fparam = param_index(o, h).or(fparam),
                                }
                            }
                        }
                        if let Some(d) = disc {
                            // map the builder's field param back to this call's arg.
                            let field = fparam.and_then(|j| match i.get_operand(j as u32) {
                                Some(Operand::Value(v)) => Some(v),
                                _ => None,
                            });
                            return Some((d, field));
                        }
                    }
                }
            }
        }
        break;
    }
    None
}

/// The ABI type of helper `g`'s parameter `idx`, propagated from the args its
/// callers pass (one or two levels), since internal helpers carry no spec type.
fn param_type_via_callers<'c>(
    g: FunctionValue<'c>,
    idx: usize,
    module: &inkwell::module::Module<'c>,
    depth: u32,
) -> String {
    if depth == 0 {
        return "?".into();
    }
    let gname = g.get_name().to_string_lossy().into_owned();
    for f in module.get_functions() {
        if f.count_basic_blocks() == 0 || f == g {
            continue;
        }
        let fargs = arg_table(f);
        for i in all_instrs(f) {
            if callee_name(i).as_deref() != Some(gname.as_str()) {
                continue;
            }
            if let Some(Operand::Value(a)) = i.get_operand(idx as u32) {
                let t = abi_type_of(a, &fargs);
                if t != "?" {
                    return t;
                }
                if let Some(j) = param_index(a, f) {
                    let t2 = param_type_via_callers(f, j, module, depth - 1);
                    if t2 != "?" {
                        return t2;
                    }
                }
            }
        }
    }
    "?".into()
}

/// A storage key's identity + the ABI types of its key parameters (for a mapping
/// variant like `Shares(Address)`). Uses the `DataKey` builder's per-variant field
/// usage to distinguish a unit key from a parameterized (mapping) key.
fn storage_key<'c>(
    key: BasicValueEnum<'c>,
    g: FunctionValue<'c>,
    args: &Args,
    kb: Option<(FunctionValue<'c>, &(BTreeMap<i64, bool>, bool))>,
    module: &inkwell::module::Module<'c>,
    segs: &[(u64, Vec<u8>)],
) -> (String, Vec<String>) {
    // a directly-encoded small symbol key (decode the name).
    if let Some(i) = as_instr(key).filter(|i| callee_name(*i).map(|n| n.contains("from_payload")).unwrap_or(false)) {
        if let Some(Operand::Value(BasicValueEnum::IntValue(c))) = i.get_operand(0) {
            if c.is_const() {
                if let Some(k) = c.get_zero_extended_constant() {
                    if (k & 0xff) == 14 {
                        if let Some(s) = decode_symbol(k) {
                            return (s, vec![]);
                        }
                    }
                }
            }
        }
    }
    if let Some((kbf, usage)) = kb {
        if let Some((disc, field)) = resolve_disc_field(key, kbf, module) {
            let is_mapping = usage.0.get(&disc).copied().unwrap_or(usage.1);
            let fields = if is_mapping {
                let t = field
                    .map(|fv| {
                        let t0 = abi_type_of(fv, args);
                        if t0 != "?" {
                            t0
                        } else if let Some(j) = param_index(fv, g) {
                            param_type_via_callers(g, j, module, 4)
                        } else {
                            "?".into()
                        }
                    })
                    .unwrap_or_else(|| "?".into());
                vec![t]
            } else {
                vec![]
            };
            // the real variant name from the data section, else the discriminant.
            let name = datakey_name(kbf, disc, module, segs)
                .unwrap_or_else(|| format!("DataKey#{disc}"));
            return (name, fields);
        }
    }
    ("?".into(), vec![])
}

/// Collect the storage schema across all entrypoints: slot -> value type.
fn emit_storage_schema<'c>(module: &inkwell::module::Module<'c>, path: &std::path::Path) {
    // (durability, key-id) -> (value type, access, mapping key types)
    #[derive(Default)]
    struct Slot { vtype: String, read: bool, written: bool, params: Vec<String> }
    let mut schema: BTreeMap<(String, String), Slot> = BTreeMap::new();
    let mut fn_reads: HashMap<String, Vec<(String, String)>> = HashMap::new();
    // the DataKey builder + its per-variant field usage (computed once).
    let kb = datakey_builder(module);
    let usage = kb.map(kb_field_usage);
    let kb_pair = kb.zip(usage.as_ref());
    let segs = rodata_segs(module);
    for f in module.get_functions() {
        if f.count_basic_blocks() == 0 {
            continue;
        }
        let args = arg_table(f);
        let mut read_here: Vec<(String, String)> = vec![];
        for i in all_instrs(f) {
            let Some(n) = callee_name(i) else { continue };
            let is_put = n.contains("put_contract_data");
            let is_get = n.contains("get_contract_data") || n.contains("has_contract_data");
            if !is_put && !is_get {
                continue;
            }
            // put(key, val, dur): dur = op2; get/has(key, dur): dur = op1.
            let dur = match i.get_operand(if is_put { 2 } else { 1 }) {
                Some(Operand::Value(x)) => durability(x),
                _ => "?".into(),
            };
            let (keyid, params) = match i.get_operand(0) {
                Some(Operand::Value(k)) => storage_key(k, f, &args, kb_pair, module, &segs),
                _ => ("?".into(), vec![]),
            };
            if dur == "?" && keyid == "?" {
                continue; // unclassifiable access
            }
            let e = schema.entry((dur.clone(), keyid.clone())).or_default();
            if e.vtype.is_empty() {
                e.vtype = "?".into();
            }
            if !params.is_empty() {
                e.params = params; // mapping domain (e.g. [Address])
            }
            if is_put {
                e.written = true;
                if let Some(Operand::Value(v)) = i.get_operand(1) {
                    let t = abi_type_of(v, &args);
                    if e.vtype == "?" && t != "?" {
                        e.vtype = t;
                    }
                }
            } else {
                e.read = true;
                read_here.push((dur, keyid));
            }
        }
        read_here.sort();
        read_here.dedup();
        fn_reads.insert(f.get_name().to_string_lossy().into_owned(), read_here);
    }

    // a getter that reads exactly one key (directly or via a one-level helper)
    // and has a known ABI return type pins that key's value type
    // (e.g. balance_shares(user) -> i128, whose read is inside a helper).
    for f in module.get_functions() {
        if f.count_basic_blocks() == 0 {
            continue;
        }
        let rt = f.get_string_attribute(AttributeLoc::Function, "spec.type")
            .or_else(|| f.get_string_attribute(AttributeLoc::Return, "spec.type"))
            .map(|a| a.get_string_value().to_string_lossy().into_owned())
            .unwrap_or_default();
        if rt.is_empty() {
            continue;
        }
        let fname = f.get_name().to_string_lossy().into_owned();
        let mut keys: Vec<(String, String)> = fn_reads.get(&fname).cloned().unwrap_or_default();
        for i in all_instrs(f) {
            if let Some(cn) = callee_name(i) {
                if let Some(ks) = fn_reads.get(&cn) {
                    keys.extend(ks.iter().cloned());
                }
            }
        }
        keys.sort();
        keys.dedup();
        if keys.len() == 1 {
            if let Some(e) = schema.get_mut(&keys[0]) {
                if e.vtype == "?" {
                    e.vtype = rt;
                }
            }
        }
    }

    let acc = |s: &Slot| match (s.read, s.written) {
        (true, true) => "read/write",
        (false, true) => "write",
        (true, false) => "read",
        _ => "—",
    };
    // render a slot's type: a mapping `(K) -> V` when the key is parameterized.
    let shape = |s: &Slot| {
        if s.params.is_empty() {
            s.vtype.clone()
        } else {
            format!("({}) -> {}", s.params.join(", "), s.vtype)
        }
    };
    // ---- Markdown ----
    let mut md = String::from("# Storage schema\n\n");
    md.push_str("Recovered from lifted bytecode: durability, key, value type, and access per\n");
    md.push_str("storage slot. Keys are shown by their `DataKey` variant name, recovered from\n");
    md.push_str("the symbol the builder reads out of the data section (falling back to the\n");
    md.push_str("`DataKey#<n>` discriminant when the name is not recoverable); a parameterized\n");
    md.push_str("key is a mapping, shown as `(key) -> value`; `?` marks a key encoding this\n");
    md.push_str("pass does not decode.\n\n");
    md.push_str("| Durability | Key | Type | Access |\n|---|---|---|---|\n");
    for ((dur, key), s) in &schema {
        md.push_str(&format!("| {dur} | {key} | {} | {} |\n", shape(s), acc(s)));
    }
    // ---- JSON ----
    let mut json = String::from("{\n  \"slots\": [\n");
    let n = schema.len();
    for (idx, ((dur, key), s)) in schema.iter().enumerate() {
        json.push_str(&format!(
            "    {{ \"durability\": \"{dur}\", \"key\": \"{key}\", \"key_params\": [{}], \"value_type\": \"{}\", \"access\": \"{}\" }}{}\n",
            s.params.iter().map(|p| format!("\"{p}\"")).collect::<Vec<_>>().join(", "),
            s.vtype, acc(s),
            if idx + 1 < n { "," } else { "" }
        ));
    }
    json.push_str("  ]\n}\n");

    let md_path = path.with_extension("storage.md");
    let json_path = path.with_extension("storage.json");
    let _ = std::fs::write(&md_path, &md);
    let _ = std::fs::write(&json_path, &json);
    print!("{md}");
    println!("\nwrote {} and {}", md_path.display(), json_path.display());
}

// ======================= driver =======================

const USAGE: &str = "usage: slice <file.ll> [--fn F] [--sink transfer|trap|error|error-ret|all] \
[--callee call] [--sym transfer|any] [--lean sm|amm|pool|cpmm] [--storage-schema]";

/// What each `--lean <mode>` emits. All read the lifted IR and print a complete,
/// self-contained Lean 4 file (no Mathlib) to stdout; redirect to a `.lean` file.
const LEAN_MODES: &str = "\
--lean modes (each prints a self-contained Lean 4 file to stdout):
  sm    per-storage-slot state machine: one `State` field per storage slot, one
        step per entrypoint built from the recovered guards + updates.
  amm   token-conservation: models SEP-41 transfers as moving value between
        external / pool / other, and proves each entrypoint conserves the total.
  pool  no-drain over recovered updates: tracked (arithmetic) slots never go
        negative, proved from the recovered update expressions and guards.
  cpmm  constant-product no-drain: for a recognized x*y pool, proves the product
        never decreases across a swap (floor-division bound); withholds if the
        swap shape is not recovered cleanly.
  model relational abstraction (SorobanAmm.lean style): one `Step → Prop` per
        entrypoint from the recovered transfers (directions) + real storage
        slots; nonlinear amounts/values stay `opaque`. The faithful contract shape.";

fn main() {
    let mut args = std::env::args().skip(1);
    let path = PathBuf::from(
        args.next()
            .expect(USAGE),
    );
    let (mut only_fn, mut callee, mut sym, mut sink_sel, mut raw, mut lean_sm, mut amm_dbg, mut lean_amm, mut expr_dbg, mut lean_pool, mut lean_cpmm, mut storage_schema) =
        (None, "call".to_string(), Some("transfer".to_string()), "all".to_string(), false, false, false, false, false, false, false, false);
    let mut lean_model = false;
    let mut lean_check = false;
    while let Some(a) = args.next() {
        match a.as_str() {
            "--fn" => only_fn = args.next(),
            "--callee" => callee = args.next().unwrap(),
            "--sym" => sym = args.next(),
            "--sink" => sink_sel = args.next().unwrap(),
            "--raw" => raw = true,
            // one front door for Lean emission: --lean <mode>. See LEAN_MODES.
            "--lean" => match args.next().as_deref() {
                Some("sm") => lean_sm = true,
                Some("amm") => lean_amm = true,
                Some("pool") => lean_pool = true,
                Some("cpmm") => lean_cpmm = true,
                Some("model") => lean_model = true,
                Some("check") => (lean_model, lean_check) = (true, true),
                other => {
                    eprintln!("--lean expects a mode: sm | amm | pool | cpmm | model (got {other:?})\n{LEAN_MODES}");
                    std::process::exit(2);
                }
            },
            "--storage-schema" => storage_schema = true,
            "--amm-dbg" => amm_dbg = true,
            "--expr-dbg" => expr_dbg = true,
            other => eprintln!("ignoring arg {other}"),
        }
    }
    let sym = sym.filter(|s| s != "any");
    let kinds: Vec<SinkKind> = match sink_sel.as_str() {
        "transfer" => vec![SinkKind::Transfer],
        "trap" => vec![SinkKind::Trap],
        "error" => vec![SinkKind::Error],
        "error-ret" => vec![SinkKind::ErrorReturn],
        _ => vec![SinkKind::Transfer, SinkKind::Trap, SinkKind::Error, SinkKind::ErrorReturn],
    };

    let ctx = Context::create();
    let buf = MemoryBuffer::create_from_file(&path).expect("read .ll");
    let module = ctx.create_module_from_ir(buf).expect("parse .ll");

    if storage_schema {
        emit_storage_schema(&module, &path);
        return;
    }

    let mut transes: Vec<Trans> = vec![];
    let mut all_slots: BTreeSet<String> = BTreeSet::new();
    let mut amm_entries: Vec<(String, Vec<(&'static str, &'static str, bool)>)> = vec![];
    let mut pool_entries: Vec<PoolEntry> = vec![];
    let mut cpmm_hits: Vec<(String, String, String, String)> = vec![];
    let mut model_entries: Vec<ModelEntry> = vec![];
    for f in module.get_functions() {
        if f.count_basic_blocks() == 0 {
            continue;
        }
        let name = f.get_name().to_string_lossy().into_owned();
        if only_fn.as_ref().map(|w| &name != w).unwrap_or(false) {
            continue;
        }

        if lean_cpmm {
            if !is_entry(f) {
                continue;
            }
            let fargs = arg_table(f);
            let (mut wmemo, mut vmemo) = (HashMap::new(), HashMap::new());
            let writes = write_summary(f, &module, &mut wmemo, &mut vmemo, 40);
            if let Some((xd, yd, dxn)) = recognize_cpmm(&writes, &fargs) {
                cpmm_hits.push((name, xd, yd, dxn));
            }
            continue;
        }

        if lean_model {
            if !is_entry(f) {
                continue;
            }
            let fargs = arg_table(f);
            let args: Vec<(String, String)> = fargs
                .iter()
                .filter(|(_, _, t)| !t.is_empty())
                .map(|(_, n, t)| (n.clone(), t.clone()))
                .collect();
            let facts = entry_facts(f, &module);
            FACTS.with(|x| *x.borrow_mut() = facts);
            let (rich, gset) = with_entry(f, || {
                let rb = rich_body(f, &module);
                let gs = entry_guards(f, &module);
                (rb, gs)
            });
            FACTS.with(|x| x.borrow_mut().clear());
            model_entries.push(ModelEntry { name, args, guards: gset.guards, rich });
            continue;
        }

        if lean_pool {
            if !is_entry(f) {
                continue;
            }
            let fargs = arg_table(f);
            let (t, _slots) = build_trans(f, &module, &callee);
            let (mut wmemo, mut vmemo) = (HashMap::new(), HashMap::new());
            let writes = write_summary(f, &module, &mut wmemo, &mut vmemo, 40);
            // dedup updates by durability, keep the recovered value expr + arith flag.
            let mut updates: Vec<(String, Option<String>, bool)> = vec![];
            for (dur, _ar, expr) in &writes {
                if updates.iter().any(|(d, _, _)| d == dur) {
                    continue;
                }
                updates.push((dur.clone(), lean_of_expr(expr, &fargs), expr_ops(expr) >= 1));
            }
            let guards: Vec<String> = t
                .guards
                .iter()
                .map(|(op, l, r)| format!("{} {} {}", lean_term(l), op.lean(), lean_term(r)))
                .collect();
            pool_entries.push(PoolEntry {
                name,
                amount: t.amount,
                updates,
                guards,
                has_transfer: t.ext != 0,
            });
            continue;
        }

        if expr_dbg {
            if !is_entry(f) {
                continue;
            }
            let fargs = arg_table(f);
            let (mut wmemo, mut vmemo) = (HashMap::new(), HashMap::new());
            let writes = write_summary(f, &module, &mut wmemo, &mut vmemo, 40);
            if writes.is_empty() {
                continue;
            }
            println!("@{name}:");
            for (dur, ar, ve) in &writes {
                println!("    storage.{dur}/{ar} := {}   [{} ops]", render_expr(ve, &fargs), expr_ops(ve));
            }
            continue;
        }

        if amm_dbg {
            if !is_entry(f) {
                continue;
            }
            let fargs = arg_table(f);
            let mut memo = HashMap::new();
            let facts = summarize(f, &module, &mut memo, 12);
            if facts.is_empty() {
                continue;
            }
            let show = |r: ARef| match r {
                ARef::Param(i) => fargs.get(i).map(|(_, n, _)| n.clone()).unwrap_or(format!("param{i}")),
                ARef::Contract => "this.pool".into(),
                ARef::Other => "?".into(),
            };
            println!("@{name}:");
            for tf in &facts {
                println!("    transfer(from={}, to={}, amount={})", show(tf.from), show(tf.to), show(tf.amount));
            }
            continue;
        }

        if lean_amm {
            if !is_entry(f) {
                continue;
            }
            let mut memo = HashMap::new();
            let facts = summarize(f, &module, &mut memo, 12);
            let pairs: Vec<(&'static str, &'static str, bool)> = facts
                .iter()
                .map(|tf| {
                    let resolved = tf.from != ARef::Other && tf.to != ARef::Other;
                    (party(tf.from), party(tf.to), resolved)
                })
                .collect();
            amm_entries.push((name, pairs));
            continue;
        }

        if lean_sm {
            if !is_entry(f) {
                continue;
            }
            let (t, slots) = build_trans(f, &module, &callee);
            all_slots.extend(slots);
            transes.push(t);
            continue;
        }

        let cfg = Cfg::build(f);
        let ipdom = ipostdoms(&cfg);
        let cd = control_deps(&cfg, &ipdom);

        for s in find_sinks(&cfg, &kinds, &callee, sym.as_deref()) {
            let slice = backward_slice(&cfg, &cd, &s.vals, &[s.instr]);
            if raw {
                print_report(&name, &s, &classify(&slice, s.instr));
            } else {
                report_sink(&name, f, &s, &slice, &module);
            }
        }
    }
    if lean_sm {
        emit_lean_sm(&transes, &all_slots);
    }
    if lean_amm {
        emit_lean_amm(&amm_entries);
    }
    if lean_model {
        emit_lean_model(&model_entries, lean_check);
    }
    if lean_pool {
        emit_lean_pool(&pool_entries);
    }
    if lean_cpmm {
        emit_lean_cpmm_proved(&cpmm_hits);
    }
}

fn print_report(fname: &str, s: &Sink, r: &Report) {
    println!("\n=== {:?} sink in @{fname}: {}", s.kind, fmt(s.instr));
    if !s.label.is_empty() {
        println!("    label: {}", s.label);
    }
    println!("    slice: {} instructions", r.size);
    println!("  storage/memory sources ({}):", r.sources.len());
    for x in &r.sources {
        println!("      {}", fmt(*x));
    }
    println!("  branch guards it depends on ({}):", r.guards.len());
    for (br, c) in &r.guards {
        let cond = as_instr(*c).map(fmt).unwrap_or_else(|| fmt(*c));
        println!("      if ({cond})  via {}", fmt(*br));
    }
    println!("  auth preconditions ({}):", r.preconds.len());
    for p in &r.preconds {
        println!("      {}", fmt(*p));
    }
    if !r.other_calls.is_empty() {
        println!("  other cross-contract calls ({}):", r.other_calls.len());
        for i in &r.other_calls {
            let nm = callee_name(*i).unwrap_or_default();
            let sy = call_symbol(*i).map(|s| format!(" \"{s}\"")).unwrap_or_default();
            println!("      {nm}{sy}");
        }
    }
}

// ======================= tests =======================

#[cfg(test)]
mod tests {
    use super::*;

    /// The raw-U32Val and obj_cmp rewrites agree with the comparison they replace.
    #[test]
    fn raw_u32_and_cmp_rewrites_are_exact() {
        let len = Expr::Opaque("@len".into(), vec![Expr::Param(0)]);
        let rels = ["<", "≤", ">", "≥"];
        let holds = |x: i128, r: &str, y: i128| match r { "<" => x < y, "≤" => x <= y, ">" => x > y, "≥" => x >= y, "=" => x == y, _ => x != y };
        for c in [0i64, 3, 4, 5, 1 << 32, (1 << 32) + 3, (1 << 32) + 4, (1 << 32) + 5, (11 << 32) - 1, 11 << 32, 81604378623] {
            for r in rels {
                let (_, r2, k) = raw_small_cmp(&len, r, &Expr::Const(c), &vec![]).expect("rewritten");
                for v in 0i128..40 {
                    let raw = v * (1 << 32) + 4;
                    assert_eq!(holds(raw, r, c as i128), holds(v, r2, k as i128), "raw {r} {c} vs v {r2} {k} at v={v}");
                }
            }
        }
        let cmp = Expr::Opaque("@cmp".into(), vec![Expr::Param(0), Expr::Param(1)]);
        for k in -2i64..=2 {
            for r in ["<", "≤", ">", "≥", "=", "≠"] {
                if let Some((_, r2, _)) = cmp_rel(&cmp, r, &Expr::Const(k)) {
                    for o in -1i128..=1 {
                        assert_eq!(holds(o, r, k as i128), holds(o, r2, 0), "cmp {r} {k} vs a {r2} b at {o}");
                    }
                }
            }
        }
    }

    fn with<'c>(ctx: &'c Context, ir: &str) -> inkwell::module::Module<'c> {
        let buf = MemoryBuffer::create_from_memory_range_copy(ir.as_bytes(), "t");
        ctx.create_module_from_ir(buf).expect("parse IR fixture")
    }
    fn func<'c>(m: &inkwell::module::Module<'c>, n: &str) -> FunctionValue<'c> {
        m.get_function(n).expect("function")
    }
    fn bidx_named(cfg: &Cfg, name: &str) -> usize {
        cfg.blocks
            .iter()
            .position(|b| b.get_name().to_str().unwrap() == name)
            .unwrap_or_else(|| panic!("no block {name}"))
    }
    fn slice_has<'c>(s: &HashSet<InstructionValue<'c>>, needle: &str) -> bool {
        s.iter().any(|i| fmt(*i).contains(needle))
    }

    const DIAMOND: &str = r#"
define i64 @f(i64 %x) {
entry:
  %c = icmp slt i64 %x, 0
  br i1 %c, label %t, label %e
t:
  br label %m
e:
  br label %m
m:
  %p = phi i64 [ 1, %t ], [ 2, %e ]
  ret i64 %p
}
"#;

    /// A callee writing through a frame pointer must clobber that slot for the
    /// sound forwarding (no stale `store 0`); rich mode resolves the load to the
    /// callee's store; a 4-byte write next to a slot does not clobber it.
    #[test]
    fn outpointer_clobber_and_resolution() {
        let ctx = Context::create();
        let m = with(
            &ctx,
            r#"
define void @w(i64 %p) {
entry:
  %a = trunc i64 %p to i32
  %q = inttoptr i32 %a to ptr
  store i64 7, ptr %q
  ret void
}
define void @flag(i64 %p) {
entry:
  %a = trunc i64 %p to i32
  %q = inttoptr i32 %a to ptr
  store i32 1, ptr %q
  ret void
}
define i64 @f() {
entry:
  %frame = alloca [64 x i8]
  %s0 = getelementptr inbounds i8, ptr %frame, i32 16
  store i64 0, ptr %s0
  %pi = ptrtoint ptr %s0 to i32
  %fp = zext i32 %pi to i64
  call void @w(i64 %fp)
  %v = load i64, ptr %s0
  %s1 = getelementptr inbounds i8, ptr %frame, i32 48
  store i64 5, ptr %s1
  %s2 = getelementptr inbounds i8, ptr %frame, i32 44
  %pj = ptrtoint ptr %s2 to i32
  %fq = zext i32 %pj to i64
  call void @flag(i64 %fq)
  %u = load i64, ptr %s1
  %r = add i64 %v, %u
  ret i64 %r
}
"#,
        );
        let f = func(&m, "f");
        let load = |n: &str| all_instrs(f).into_iter().find(|i| fmt(*i).starts_with(&format!("%{n} = load"))).unwrap();
        let (v, u) = (load("v"), load("u"));
        assert!(forward_load(v, f).is_none(), "the call through %fp clobbers the stale store 0");
        let fwd = forward_load(u, f).map(fmt).unwrap_or_default();
        assert!(fwd.contains('5'), "a 4-byte write at +44 doesn't clobber the slot at +48: {fwd}");
        // %v as a value: the add's first operand.
        let add = all_instrs(f).into_iter().find(|i| i.get_opcode() == InstructionOpcode::Add).unwrap();
        let Some(Operand::Value(ve)) = add.get_operand(0) else { panic!("no %v operand") };
        let e = with_rich(|| value_expr(ve, f, &m, &mut HashMap::new(), 20));
        assert!(e == Expr::Const(7), "rich mode resolves the load to the callee's store");
    }

    #[test]
    fn control_dep_diamond() {
        let ctx = Context::create();
        let m = with(&ctx, DIAMOND);
        let cfg = Cfg::build(func(&m, "f"));
        let cd = control_deps(&cfg, &ipostdoms(&cfg));
        let (entry, t, e, mm) = (
            bidx_named(&cfg, "entry"),
            bidx_named(&cfg, "t"),
            bidx_named(&cfg, "e"),
            bidx_named(&cfg, "m"),
        );
        assert_eq!(cd[t], HashSet::from([entry]), "then is control-dep on entry branch");
        assert_eq!(cd[e], HashSet::from([entry]), "else is control-dep on entry branch");
        assert!(cd[mm].is_empty(), "merge post-dominates entry -> no control dep");
        assert!(cd[entry].is_empty(), "entry has no control dep");
    }

    #[test]
    fn data_slice_chain() {
        let ctx = Context::create();
        let m = with(
            &ctx,
            r#"
define i64 @f(i64 %x) {
entry:
  %a = add i64 %x, 1
  %b = mul i64 %a, 2
  ret i64 %b
}
"#,
        );
        let cfg = Cfg::build(func(&m, "f"));
        let cd = control_deps(&cfg, &ipostdoms(&cfg));
        // seed: the %b value (operand of ret).
        let ret = cfg.instrs().find(|i| i.get_opcode() == InstructionOpcode::Return).unwrap();
        let b = match ret.get_operand(0).unwrap() {
            Operand::Value(v) => v,
            _ => unreachable!(),
        };
        let s = backward_slice(&cfg, &cd, &[b], &[]);
        assert!(slice_has(&s, "add"), "slice includes the add def");
        assert!(slice_has(&s, "mul"), "slice includes the mul def");
    }

    #[test]
    fn trap_sink_unreachable_catches_guard() {
        let ctx = Context::create();
        let m = with(
            &ctx,
            r#"
define i64 @f(i64 %x) {
entry:
  %c = icmp slt i64 %x, 0
  br i1 %c, label %bad, label %ok
bad:
  unreachable
ok:
  ret i64 %x
}
"#,
        );
        let cfg = Cfg::build(func(&m, "f"));
        let cd = control_deps(&cfg, &ipostdoms(&cfg));
        let sinks = find_sinks(&cfg, &[SinkKind::Trap], "call", None);
        assert_eq!(sinks.len(), 1, "one trap sink (the unreachable)");
        assert_eq!(sinks[0].kind, SinkKind::Trap);
        let s = backward_slice(&cfg, &cd, &sinks[0].vals, &[sinks[0].instr]);
        assert!(slice_has(&s, "icmp slt"), "trap's guard condition is in the slice");
    }

    #[test]
    fn trap_sink_soroban_trap_call() {
        let ctx = Context::create();
        let m = with(
            &ctx,
            r#"
declare void @soroban.trap()
define void @f() {
entry:
  call void @soroban.trap()
  unreachable
}
"#,
        );
        let cfg = Cfg::build(func(&m, "f"));
        let sinks = find_sinks(&cfg, &[SinkKind::Trap], "call", None);
        // both the trap() call and the unreachable terminator are trap sinks.
        assert!(sinks.iter().any(|s| s.label == "trap()"), "soroban.trap call found");
        assert!(sinks.iter().any(|s| s.label == "unreachable"), "unreachable found");
    }

    #[test]
    fn error_syscall_sink() {
        let ctx = Context::create();
        let m = with(
            &ctx,
            r#"
%Val = type { i64 }
declare %Val @soroban.val.from_payload(i64)
declare void @context.fail_with_error(%Val)
define void @f(i64 %x) {
entry:
  %c = icmp eq i64 %x, 0
  br i1 %c, label %err, label %ok
err:
  %e = call %Val @soroban.val.from_payload(i64 259)
  call void @context.fail_with_error(%Val %e)
  unreachable
ok:
  ret void
}
"#,
        );
        let cfg = Cfg::build(func(&m, "f"));
        let cd = control_deps(&cfg, &ipostdoms(&cfg));
        let sinks = find_sinks(&cfg, &[SinkKind::Error], "call", None);
        assert_eq!(sinks.len(), 1, "one fail_with_error sink");
        assert_eq!(sinks[0].kind, SinkKind::Error);
        assert_eq!(sinks[0].label, error_desc(259), "error code decoded (type=1, code=0)");
        let s = backward_slice(&cfg, &cd, &sinks[0].vals, &[sinks[0].instr]);
        assert!(slice_has(&s, "icmp eq"), "the condition raising the error is in the slice");
    }

    #[test]
    fn error_return_sink() {
        let ctx = Context::create();
        let m = with(
            &ctx,
            r#"
%Val = type { i64 }
declare %Val @soroban.val.from_payload(i64)
define %Val @f(i64 %x) {
entry:
  %c = icmp eq i64 %x, 0
  br i1 %c, label %err, label %ok
err:
  %e = call %Val @soroban.val.from_payload(i64 259)
  ret %Val %e
ok:
  %v = call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v
}
"#,
        );
        let cfg = Cfg::build(func(&m, "f"));
        let sinks = find_sinks(&cfg, &[SinkKind::ErrorReturn], "call", None);
        assert_eq!(sinks.len(), 1, "only the Err(..) return, not the Void return");
        assert_eq!(sinks[0].kind, SinkKind::ErrorReturn);
        assert_eq!(sinks[0].label, error_desc(259));
    }

    #[test]
    fn transfer_sink_and_symbol() {
        let ctx = Context::create();
        // 65154533130155790 is SymbolSmall("transfer").
        let m = with(
            &ctx,
            r#"
%Val = type { i64 }
declare %Val @call.call(%Val, %Val, %Val)
declare %Val @soroban.val.from_payload(i64)
define void @f(%Val %from, %Val %to) {
entry:
  %sym = call %Val @soroban.val.from_payload(i64 65154533130155790)
  %r = call %Val @call.call(%Val %from, %Val %sym, %Val %to)
  ret void
}
"#,
        );
        let cfg = Cfg::build(func(&m, "f"));
        let sinks = find_sinks(&cfg, &[SinkKind::Transfer], "call", Some("transfer"));
        assert_eq!(sinks.len(), 1, "transfer call found by symbol");
        assert_eq!(sinks[0].label, "transfer");
        assert_eq!(sinks[0].vals.len(), 3, "contract + symbol + args seeded");
    }

    #[test]
    fn symbol_decoder_roundtrips() {
        assert_eq!(decode_symbol(65154533130155790), Some("transfer".to_string()));
        assert_eq!(decode_symbol(2 /* Void tag */), None);
    }

    #[test]
    fn loop_postdom_terminates_and_is_correct() {
        let ctx = Context::create();
        let m = with(
            &ctx,
            r#"
define void @f(i64 %n) {
entry:
  br label %head
head:
  %i = phi i64 [ 0, %entry ], [ %i2, %body ]
  %c = icmp slt i64 %i, %n
  br i1 %c, label %body, label %exit
body:
  %i2 = add i64 %i, 1
  br label %head
exit:
  ret void
}
"#,
        );
        let cfg = Cfg::build(func(&m, "f"));
        let cd = control_deps(&cfg, &ipostdoms(&cfg)); // must terminate despite the back-edge
        let (head, body) = (bidx_named(&cfg, "head"), bidx_named(&cfg, "body"));
        assert_eq!(cd[body], HashSet::from([head]), "body is control-dep on the head branch");
    }

    #[test]
    fn all_sinks_in_one_function() {
        let ctx = Context::create();
        let m = with(
            &ctx,
            r#"
%Val = type { i64 }
declare %Val @call.call(%Val, %Val, %Val)
declare %Val @soroban.val.from_payload(i64)
declare void @context.fail_with_error(%Val)
define %Val @f(%Val %a, i64 %x) {
entry:
  %c = icmp slt i64 %x, 0
  br i1 %c, label %bad, label %go
bad:
  %e = call %Val @soroban.val.from_payload(i64 259)
  call void @context.fail_with_error(%Val %e)
  unreachable
go:
  %sym = call %Val @soroban.val.from_payload(i64 65154533130155790)
  %r = call %Val @call.call(%Val %a, %Val %sym, %Val %a)
  %err = call %Val @soroban.val.from_payload(i64 259)
  ret %Val %err
}
"#,
        );
        let cfg = Cfg::build(func(&m, "f"));
        let all = find_sinks(
            &cfg,
            &[SinkKind::Transfer, SinkKind::Trap, SinkKind::Error, SinkKind::ErrorReturn],
            "call",
            Some("transfer"),
        );
        let kinds: HashSet<_> = all.iter().map(|s| s.kind).collect();
        assert!(kinds.contains(&SinkKind::Transfer));
        assert!(kinds.contains(&SinkKind::Trap));
        assert!(kinds.contains(&SinkKind::Error));
        assert!(kinds.contains(&SinkKind::ErrorReturn));
    }

    #[test]
    fn ok_return_is_not_an_error_sink() {
        let ctx = Context::create();
        let m = with(
            &ctx,
            r#"
%Val = type { i64 }
declare %Val @soroban.val.from_payload(i64)
define %Val @f() {
entry:
  %v = call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v
}
"#,
        );
        let cfg = Cfg::build(func(&m, "f"));
        assert!(find_sinks(&cfg, &[SinkKind::ErrorReturn], "call", None).is_empty());
    }

    #[test]
    fn nested_control_deps_chain() {
        let ctx = Context::create();
        let m = with(
            &ctx,
            r#"
define i64 @f(i64 %x, i64 %y) {
entry:
  %c1 = icmp slt i64 %x, 0
  br i1 %c1, label %outer, label %done
outer:
  %c2 = icmp slt i64 %y, 0
  br i1 %c2, label %inner, label %done
inner:
  unreachable
done:
  ret i64 0
}
"#,
        );
        let cfg = Cfg::build(func(&m, "f"));
        let cd = control_deps(&cfg, &ipostdoms(&cfg));
        let sinks = find_sinks(&cfg, &[SinkKind::Trap], "call", None);
        let s = backward_slice(&cfg, &cd, &sinks[0].vals, &[sinks[0].instr]);
        // reaching the inner trap requires BOTH conditions.
        assert!(slice_has(&s, "%c1") || slice_has(&s, "icmp slt i64 %x"), "outer guard present");
        assert!(slice_has(&s, "%c2") || slice_has(&s, "icmp slt i64 %y"), "inner guard present");
    }

    // A storage read on a key parameterised by the `from` arg, built the way the
    // SDK does: store the arg payload into the frame, then a key-vec over it.
    const STORE_KEY: &str = r#"
%Val = type { i64 }
declare %Val @soroban.val.from_payload(i64)
declare i64 @soroban.val.payload(%Val)
declare i64 @soroban.storage_type(i64)
declare %Val @ledger.get_contract_data(%Val, i64)
declare %Val @vec.vec_new_from_linear_memory(%Val, %Val)
declare void @address.require_auth(%Val)
define i64 @g(%Val "spec.name"="from" "spec.type"="Address" %0, %Val "spec.name"="amount" "spec.type"="i128" %1) {
entry:
  %frame = alloca [16 x i8], align 1
  call void @address.require_auth(%Val %0)
  %from_pl = call i64 @soroban.val.payload(%Val %0)
  %amt_pl = call i64 @soroban.val.payload(%Val %1)
  store i64 %from_pl, ptr %frame, align 1
  %len = call %Val @soroban.val.from_payload(i64 8589934596)
  %keyv = call %Val @vec.vec_new_from_linear_memory(%Val %0, %Val %len)
  %dur = call i64 @soroban.storage_type(i64 1)
  %bal = call %Val @ledger.get_contract_data(%Val %keyv, i64 %dur)
  %bal_pl = call i64 @soroban.val.payload(%Val %bal)
  %cmp = icmp slt i64 %bal_pl, %amt_pl
  br i1 %cmp, label %t, label %e
t:
  unreachable
e:
  ret i64 0
}
"#;

    #[test]
    fn symbolic_types_keys_and_sources() {
        let ctx = Context::create();
        let m = with(&ctx, STORE_KEY);
        let f = func(&m, "g");
        let args = arg_table(f);
        // types come straight off the ABI attributes.
        assert_eq!(args[0].1, "from");
        assert_eq!(args[0].2, "Address");
        assert_eq!(args[1].2, "i128");

        // the storage read resolves to persistent[from] via the frame store.
        let bal = f
            .get_basic_blocks()
            .iter()
            .flat_map(|b| {
                let mut v = vec![];
                let mut it = b.get_first_instruction();
                while let Some(i) = it {
                    v.push(i);
                    it = i.get_next_instruction();
                }
                v
            })
            .find(|i| callee_name(*i).map(|n| n.contains("get_contract_data")).unwrap_or(false))
            .unwrap();
        match store_src(bal, &args) {
            Src::Store { dur, params } => {
                assert_eq!(dur, "persistent");
                assert_eq!(params, vec!["from".to_string()]);
            }
            _ => panic!("expected a Store source"),
        }
    }

    #[test]
    fn symbolic_value_gate_rests_on_balance_and_amount() {
        let ctx = Context::create();
        let m = with(&ctx, STORE_KEY);
        let f = func(&m, "g");
        let args = arg_table(f);
        // the icmp gate's sources are exactly {amount, storage.persistent[from]}.
        // take the condition the way the driver does: a conditional branch's operand 0.
        let cfg = Cfg::build(f);
        let cond = cfg
            .blocks
            .iter()
            .filter_map(|b| b.get_terminator())
            .filter(|t| t.get_opcode() == InstructionOpcode::Br && t.get_num_operands() == 3)
            .find_map(|t| match t.get_operand(0) {
                Some(Operand::Value(v)) => Some(v),
                _ => None,
            })
            .unwrap();
        let mut srcs = BTreeSet::new();
        srcs_in(cond, &args, 40, &mut srcs);
        let shown: BTreeSet<String> = srcs.iter().map(Src::show).collect();
        assert!(shown.contains("amount"), "gate rests on amount: {shown:?}");
        assert!(shown.contains("storage.persistent[from]"), "gate rests on balance: {shown:?}");
    }

    // Two Address type-checks combined with `select` into one branch condition,
    // the way rustc lowers `a.is_addr() && b.is_addr()` (as in three_bugs::read).
    const COMBINED_TYPE_GATE: &str = r#"
%Val = type { i64 }
declare i64 @soroban.val.payload(%Val)
declare void @soroban.trap()
define i64 @h(%Val "spec.name"="a" "spec.type"="Address" %0, %Val "spec.name"="b" "spec.type"="Address" %1) {
entry:
  %pa = call i64 @soroban.val.payload(%Val %0)
  %pb = call i64 @soroban.val.payload(%Val %1)
  %anda = and i64 %pa, 255
  %oka = icmp eq i64 %anda, 77
  %andb = and i64 %pb, 255
  %okb = icmp eq i64 %andb, 77
  %both = select i1 %oka, i1 %okb, i1 false
  br i1 %both, label %ok, label %bad
bad:
  call void @soroban.trap()
  unreachable
ok:
  ret i64 0
}
"#;

    #[test]
    fn combined_boolean_type_gate_is_discharged_not_a_value_gate() {
        let ctx = Context::create();
        let m = with(&ctx, COMBINED_TYPE_GATE);
        let f = func(&m, "h");
        let args = arg_table(f);
        let cfg = Cfg::build(f);
        let cond = cfg
            .blocks
            .iter()
            .filter_map(|b| b.get_terminator())
            .filter(|t| t.get_opcode() == InstructionOpcode::Br && t.get_num_operands() == 3)
            .find_map(|t| match t.get_operand(0) {
                Some(Operand::Value(v)) => Some(v),
                _ => None,
            })
            .unwrap();
        // the `a && b are Addresses` gate decomposes to two Address type checks,
        // so it is discharged by the ABI, NOT surfaced as a real value gate.
        match classify_gate(cond, false, &args) {
            Gate::Type(t) => assert_eq!(t, "Address"),
            Gate::Value(s) => panic!("combined type gate leaked as a value gate: {:?}",
                s.iter().map(Src::show).collect::<Vec<_>>()),
            Gate::Presence => panic!("unexpected presence"),
        }
    }

    #[test]
    fn tag_names_cover_the_core_val_tags() {
        assert_eq!(tag_name(77), "Address");
        assert_eq!(tag_name(11), "i128");
        assert_eq!(tag_name(69), "i128"); // object form
        assert_eq!(tag_name(14), "Symbol");
        assert_eq!(tag_name(2), "Void");
    }
}
