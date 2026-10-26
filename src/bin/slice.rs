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
    if expr_size(&e, 1500) >= 1500 {
        e = Expr::Opaque("big".into(), vec![]);
    }
    RICH_MEMO.with(|m| m.borrow_mut().insert(key, e.clone()));
    e
}

/// Fold the i128 / Soroban lowering idioms back into source-level values. Applied
/// at every reconstructed node (children are already folded):
/// - hi-limb phi `phi(x, AShr(x,63) [, 0 | arg])` → `x` (sign-extended hi limb,
///   with the storage-absent default);
/// - Soroban bool decode `Select(And(b,255)==1, 1, Select(And(b,255)==0, 0, 2))`
///   → `@bool(b)`, and `And(@bool b, 1) == 0` → `@isfalse(b)`;
fn fold_rich(e: Expr) -> Expr {
    fn is_op(x: &Expr, l: &str) -> bool { matches!(x, Expr::Opaque(n, _) if n == l) }
    let args_of = |x: &Expr| -> Vec<Expr> { if let Expr::Opaque(_, xs) = x { xs.clone() } else { vec![] } };
    match &e {
        Expr::Opaque(l, xs) if l == "phi" => {
            let arms: Vec<&Expr> = xs
                .iter()
                .filter(|a| !matches!(a, Expr::Const(0)) && !matches!(a, Expr::Opaque(n, v) if n == "arg" && v.is_empty()))
                .collect();
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
            // drop a carry/sign addend: X ± sext/zext/trunc(..) == X
            if matches!(opc, '+' | '-') {
                if let Some(bi) = o(1).and_then(as_instr) {
                    if matches!(bi.get_opcode(), SExt | ZExt | Trunc) {
                        if let Some(x) = o(0) {
                            return value_expr(x, g, module, memo, depth - 1);
                        }
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
        // extension / truncation is limb bookkeeping -> the value passes through.
        SExt | ZExt | Trunc => {
            if let Some(x) = o(0) {
                return value_expr(x, g, module, memo, depth - 1);
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
    let mut vals: Vec<Expr> = vec![];
    let mut ok = !preds.is_empty();
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
                    vals.push(e);
                }
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
            _ => Some(Expr::Opaque("phi".into(), vals)),
        }
    };
    seen.done.insert(blk, r.clone());
    r
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
    let e = derefs(e, call, g, cfg, module, memo, depth);
    let nargs = call.get_num_operands().saturating_sub(1);
    let actuals: Vec<Expr> = (0..nargs)
        .map(|j| match call.get_operand(j) {
            Some(Operand::Value(x)) => value_expr(x, g, module, memo, depth),
            _ => Expr::Opaque("?".into(), vec![]),
        })
        .collect();
    let r = fold_rich(subst(&e, &actuals));
    match entry_site(g, call) {
        Some(site) => annotate_at(&r, site),
        None => r,
    }
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

/// Folds that need named slots: a `get(k).unwrap_or(0)` (`has(k) ? get(k) : 0`)
/// is just the read — the model's storage reads an absent key as 0; `Or(x, x)` is
/// `x`; and `Or(a, b) = 0` is `a = 0 ∧ b = 0` (bitwise, exact).
fn fold_named(e: Expr) -> Expr {
    // the same slot, ignoring at which program point it was read.
    // (a field read `@field:f(K)` is a read of the struct at K.)
    fn root(e: &Expr) -> &Expr {
        match e {
            Expr::Opaque(l, xs) if l.starts_with("@field:") && xs.len() == 1 => root(&xs[0]),
            e => e,
        }
    }
    let same_slot = |a: &Expr, b: &Expr| -> bool {
        match (root(a), root(b)) {
            (Expr::Slot(x, _), Expr::Slot(y, _)) => x == y,
            (Expr::Opaque(x, xa), Expr::Opaque(y, ya)) if (x.starts_with("@map:") || x.starts_with("@tup:")) && x == y => xa.first() == ya.first(),
            (a, b) => a == b,
        }
    };
    let is_has_of = |c: &Expr, x: &Expr| -> bool {
        matches!(c, Expr::Opaque(l, v) if l == "ICmp_EQ" && v.len() == 2 && v[1] == Expr::Const(1)
            && matches!(&v[0], Expr::Opaque(h, k) if h == "@has" && k.len() == 1 && same_slot(&k[0], x)))
    };
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
        Expr::Opaque(l, xs) if l == "Select" && xs.len() == 3 => {
            let (c, t, f) = (&xs[0], &xs[1], &xs[2]);
            if *f == Expr::Const(0) && is_has_of(c, t) {
                return t.clone();
            }
            if let Expr::Opaque(n, inner) = c {
                if n == "@not" && inner.len() == 1 && *t == Expr::Const(0) && is_has_of(&inner[0], f) {
                    return f.clone();
                }
            }
            e
        }
        Expr::Opaque(l, xs) if l == "Or" && xs.len() == 2 && xs[0] == xs[1] => xs[0].clone(),
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

/// What callee `h` stores at `*(param k + off)`, as an expression over `h`'s
/// params: a direct store in a non-trapping block, or (one level down) a nested
/// call that forwards the pointer. Multiple distinct non-trapping stores (paths
/// that disagree) make it a `phi`.
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
    let param = h.get_nth_param(k as u32)?;
    let pbase = fmt(param);
    let mut found: Vec<Expr> = vec![];
    for bb in h.get_basic_blocks() {
        if forces_trap(bb, 0) {
            continue; // an error path writes its own garbage before trapping
        }
        let mut it = bb.get_first_instruction();
        while let Some(i) = it {
            it = i.get_next_instruction();
            match i.get_opcode() {
                InstructionOpcode::Store => {
                    if let (Some(Operand::Value(sv)), Some(Operand::Value(sp))) = (i.get_operand(0), i.get_operand(1)) {
                        if ptr_base_off(sp) == (pbase.clone(), off) {
                            let e = value_expr(sv, h, module, memo, depth - 1);
                            if !found.contains(&e) {
                                found.push(e);
                            }
                        }
                    }
                }
                InstructionOpcode::Call => {
                    // the callee forwards the pointer (param k + c) to a deeper helper.
                    let Some(cn) = callee_name(i) else { continue };
                    let Some(h2) = module.get_function(&cn) else { continue };
                    if h2.count_basic_blocks() == 0 {
                        continue;
                    }
                    let nargs = i.get_num_operands().saturating_sub(1);
                    for j in 0..nargs {
                        let Some(Operand::Value(a)) = i.get_operand(j) else { continue };
                        let (b, o) = if a.is_pointer_value() { ptr_base_off(a) } else { addr_base_off(a) };
                        if b == pbase && o <= off {
                            if let Some(e2) = callee_store_at(h2, j as usize, off - o, module, memo, depth - 1, fuel - 1) {
                                let hcfg = Cfg::build(h);
                                let e = subst_call(&e2, i, h, &hcfg, module, memo, depth - 1);
                                if !found.contains(&e) {
                                    found.push(e);
                                }
                            }
                        }
                    }
                }
                _ => {}
            }
        }
    }
    match found.len() {
        0 => None,
        1 => found.pop(),
        _ => Some(Expr::Opaque("phi".into(), found)),
    }
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

/// The Lean term for a transfer party, inside an entrypoint model: the external
/// party is the caller `c`, the pool is `pool`, an unresolved one is left `0`.
fn party_term(r: ARef) -> &'static str {
    match r {
        ARef::Contract => "pool",
        ARef::Param(_) => "c",
        ARef::Other => "0",
    }
}

/// One entrypoint's recovered shape, for the relational Lean model.
struct ModelEntry {
    name: String,
    args: Vec<(String, String)>,        // (spec.name, spec.type) of the ABI args
    transfers: Vec<(String, String)>,   // (from term, to term) per traced SEP-41 transfer
    tokens: Vec<String>,                // token ledger each transfer moves (by recovered order)
    writes: Vec<(String, bool)>,        // (storage slot name, is_mapping) written
    returns: bool,                      // the entrypoint returns a value
    auth: Option<String>,               // the arg whose `require_auth()` gates the call
    inv: bool,                          // guards a trap with a constant-product (x*y) check
    guards: Vec<Guard>,                 // all recovered trap (panic) guards (pass conditions)
    gdecls: Vec<String>,                // opaque Step-terms the guards name
    rich: Option<RichBody>,             // reconstructed transfers + writes (when available)
    more_auths: Vec<String>,            // further signers beyond `auth` (require_auth*)
}

/// The arg whose `require_auth()` the entrypoint calls — the signer gate. The
/// `to.require_auth()` at the top of each entrypoint means the caller must be
/// that address, which is how we justify binding transfers to the caller.
fn entry_auth(f: FunctionValue) -> Option<String> {
    entry_auths(f).into_iter().next()
}

/// Every arg whose `require_auth()` / `require_auth_for_args()` the entrypoint
/// calls, in order (e.g. both parties of an atomic swap).
fn entry_auths(f: FunctionValue) -> Vec<String> {
    let args = arg_table(f);
    let mut out = vec![];
    for i in all_instrs(f) {
        if callee_name(i).map_or(false, |n| n.contains("require_auth")) {
            if let Some(Operand::Value(v)) = i.get_operand(0) {
                if let Some(Src::Arg(n)) = src_of(v, &args) {
                    if !out.contains(&n) {
                        out.push(n);
                    }
                }
            }
        }
    }
    out
}

/// Does `f` contain a trap (`soroban.trap` / `unreachable`)?
fn f_has_trap(f: FunctionValue) -> bool {
    all_instrs(f).iter().any(|i| {
        i.get_opcode() == InstructionOpcode::Unreachable
            || callee_name(*i).map_or(false, |n| n.contains("trap"))
    })
}

/// Does `v` trace (through the transparent Val wrappers, selects and arithmetic,
/// but NOT through a memory load) to one of `f`'s parameters? Used to tell a
/// guard that compares against an argument (slippage/amount checks) from one
/// that compares two internally-computed values (the constant-product check).
fn derives_from_arg(v: BasicValueEnum, f: FunctionValue, depth: u32) -> bool {
    if depth == 0 {
        return false;
    }
    if param_index(v, f).is_some() {
        return true;
    }
    let Some(i) = as_instr(v) else { return false };
    if i.get_opcode() == InstructionOpcode::Load {
        return false; // a frame load severs the arg connection
    }
    (0..i.get_num_operands()).any(|k| match i.get_operand(k) {
        Some(Operand::Value(o)) => derives_from_arg(o, f, depth - 1),
        _ => false,
    })
}

/// Is `v` a constant integer?
fn is_const_int(v: BasicValueEnum) -> bool {
    matches!(v, BasicValueEnum::IntValue(c) if c.is_const())
}

/// Does block `b`, or a shallow successor, contain a trap?
fn blk_traps(b: BasicBlock, depth: u32) -> bool {
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
        Some(t) => (0..t.get_num_operands()).any(|k| match t.get_operand(k) {
            Some(Operand::Block(nb)) => blk_traps(nb, depth - 1),
            _ => false,
        }),
        None => false,
    }
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

/// Is the i1 `cmp` the condition of a branch one of whose targets reaches a
/// trap — i.e. `cmp` gates a panic (a guard), not just any branch?
fn gates_trap_br(cmp: InstructionValue, f: FunctionValue) -> bool {
    for i in all_instrs(f) {
        if i.get_opcode() != InstructionOpcode::Br {
            continue;
        }
        if as_instr(match i.get_operand(0) { Some(Operand::Value(c)) => c, _ => continue }) != Some(cmp) {
            continue;
        }
        // a conditional branch whose condition is `cmp`: does a target trap?
        let traps = (1..i.get_num_operands()).any(|k| match i.get_operand(k) {
            Some(Operand::Block(b)) => blk_traps(b, 1),
            _ => false,
        });
        if traps {
            return true;
        }
    }
    false
}

/// Does `f` guard a trap with a constant-product check — a comparison of two
/// internally-computed values (the two `inv_a*inv_b` products) feeding a panic?
/// Every OTHER trap guard compares a computed value against an argument
/// (slippage, amount, insufficient-shares) or a constant (sign checks), so
/// "both sides computed, neither an arg nor a constant, gating a trap" pins the
/// `new_inv_a*new_inv_b < old_inv_a*old_inv_b` panic — the invariant the
/// contract enforces on itself, without reconstructing the formula.
fn has_product_invariant_trap<'c>(f: FunctionValue<'c>, module: &inkwell::module::Module<'c>) -> bool {
    if !f_has_trap(f) {
        return false;
    }
    for i in all_instrs(f) {
        if !gates_trap_br(i, f) {
            continue;
        }
        // the invariant is a WIDE (i128/i256) comparison of the two products,
        // which lifts as the select-compare idiom `select (icmp eq hi) cmplo cmphi`
        // — we read its hi-limb icmp. A plain i64 icmp (e.g. inside the isqrt
        // share math) is not the constant-product check.
        let ci = match i.get_opcode() {
            InstructionOpcode::Select => match i.get_operand(2) {
                Some(Operand::Value(hv)) => match as_instr(hv).filter(|x| x.get_opcode() == InstructionOpcode::ICmp) {
                    Some(hi) => hi,
                    None => continue,
                },
                _ => continue,
            },
            _ => continue,
        };
        // an ORDERING comparison (`new < old`), not equality — that rules out
        // i128-multiply overflow/sign checks (`hi == lo>>63`), which also compare
        // two computed values but are not the constant-product invariant.
        use inkwell::IntPredicate::*;
        if !matches!(ci.get_icmp_predicate(), Some(ULT | ULE | UGT | UGE | SLT | SLE | SGT | SGE)) {
            continue;
        }
        if let (Some(Operand::Value(av)), Some(Operand::Value(bv))) = (ci.get_operand(0), ci.get_operand(1)) {
            let computed = |x: BasicValueEnum| !is_const_int(x) && !derives_from_arg(x, f, 24);
            // …and both sides really are products (not, say, two timestamps).
            fn has_mul(e: &Expr) -> bool {
                match e {
                    Expr::Bin('*', _, _) => true,
                    Expr::Bin(_, a, b) | Expr::VecGet(a, b) => has_mul(a) || has_mul(b),
                    Expr::Opaque(_, xs) => xs.iter().any(has_mul),
                    _ => false,
                }
            }
            let product = |x: BasicValueEnum<'c>| with_rich(|| has_mul(&value_expr(x, f, module, &mut HashMap::new(), 40)));
            if computed(av) && computed(bv) && product(av) && product(bv) {
                return true;
            }
        }
    }
    false
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
    let cfg = Cfg::build(f);
    let args = arg_table(f);
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
        // split so each leaf is a conjunct of the PASS condition: ¬(a∨b)=¬a∧¬b
        // when negating, (a∧b) when keeping.
        let mut leaves = vec![];
        bool_split(cond, negate, 8, &mut leaves);
        for leaf in leaves {
            // a boolean `select c, a, b` (one test or another, chosen by c).
            if gate_vals(leaf).is_none() && as_instr(leaf).is_some_and(|i| i.get_opcode() == InstructionOpcode::Select) {
                let e = with_rich(|| fold_rich(simplify(value_expr(leaf, f, module, &mut vmemo, 40))));
                let e = name_slots(&e, module, kb, &segs);
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
            let (le, re) = (name_slots(&le, module, kb, &segs), name_slots(&re, module, kb, &segs));
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
    }
    GuardSet { guards: gs, decls }
}

/// A recovered transition guard: its human-readable form and its Lean conjunct.
struct Guard { comment: String, lean: String }
struct GuardSet { guards: Vec<Guard>, decls: Vec<String> }

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

/// Render a reconstructed expression as a Lean term over the model: an argument
/// becomes `st.call.arg "n"`, arithmetic is kept, and any subtree the pass does
/// not name (a storage read, an i128 reconstruction) becomes a fresh `opaque`
/// Step-term (shared by structurally-identical subtrees), recorded in `decls`.
/// A token (SEP-41 contract) as the Lean ledger name it maps to: a named token
/// slot `"TokenA"`, or a conditional choice `(if c then "TokenB" else "TokenA")`.
fn ledger_term(
    tok: &Expr,
    args: &Args,
    opmap: &mut HashMap<String, String>,
    oc: &mut usize,
    decls: &mut Vec<String>,
    fnid: &str,
) -> Option<String> {
    match tok {
        Expr::Slot(n, _) if !matches!(n.as_str(), "instance" | "persistent" | "temporary" | "?") => Some(format!("\"{n}\"")),
        Expr::Opaque(l, _) if l.starts_with("@map:") => None,
        // a token address held in a struct field: `"Offer.buy_token"`.
        Expr::Opaque(l, xs) if l.starts_with("@field:") && xs.len() == 1 => {
            let base = ledger_term(&xs[0], args, opmap, oc, decls, fnid)?;
            Some(format!("{}.{}\"", base.strip_suffix('"')?, &l["@field:".len()..]))
        }
        // a token passed as an argument: the ledger is keyed by its address.
        Expr::Param(i) => args.get(*i).map(|(_, n, _)| format!("(toString (st.call.argA \"{n}\"))")),
        Expr::Opaque(l, xs) if l == "Select" && xs.len() == 3 => {
            let c = lean_cond(&xs[0], args, opmap, oc, decls, fnid)?;
            let a = ledger_term(&xs[1], args, opmap, oc, decls, fnid)?;
            let b = ledger_term(&xs[2], args, opmap, oc, decls, fnid)?;
            Some(format!("(if {c} then {a} else {b})"))
        }
        _ => None,
    }
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
        Expr::Opaque(l, xs) if l == "@not" && xs.len() == 1 => {
            Some(format!("¬({})", lean_cond(&xs[0], args, opmap, oc, decls, fnid)?))
        }
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
    match e {
        Expr::Slot(n, t) if !matches!(n.as_str(), "instance" | "persistent" | "temporary" | "?") => {
            Some((format!(".var \"{n}\""), if *t > 0 { state_at(*t - 1) } else { "st.pre".into() }))
        }
        // a variant whose payload is a struct (`Allowance(AllowanceDataKey { from,
        // spender })`): keyed by the struct's fields.
        Expr::Opaque(l, xs) if l.starts_with("@map:") && (xs.len() == 1 || xs.len() == 2)
            && matches!(&xs[0], Expr::Opaque(sl, _) if sl.starts_with("@struct:")) =>
        {
            let Expr::Opaque(_, fs) = &xs[0] else { unreachable!() };
            let mut v = vec![Expr::Opaque("@ks".into(), fs.clone())];
            v.extend(xs.get(1).cloned());
            lean_key(&Expr::Opaque(format!("@tup:{}", &l["@map:".len()..]), v), args, opmap, oc, decls, fnid)
        }
        Expr::Opaque(l, xs) if l.starts_with("@map:") && (xs.len() == 1 || xs.len() == 2) => {
            let st = match xs.get(1) {
                Some(Expr::Opaque(a, k)) if a == "@at" => match k.first() { Some(Expr::Const(t)) => state_at(*t as usize), _ => "st.pre".into() },
                _ => "st.pre".into(),
            };
            Some((format!(".entry \"{}\" ({})", &l["@map:".len()..], lean_guard_term(&xs[0], args, opmap, oc, decls, fnid)), st))
        }
        Expr::Opaque(l, xs) if l.starts_with("@tup:") && (xs.len() == 1 || xs.len() == 2) => {
            let Expr::Opaque(_, ks) = &xs[0] else { return None };
            let st = match xs.get(1) {
                Some(Expr::Opaque(a, k)) if a == "@at" => match k.first() { Some(Expr::Const(t)) => state_at(*t as usize), _ => "st.pre".into() },
                _ => "st.pre".into(),
            };
            let ks: Vec<String> = ks.iter().map(|k| lean_guard_term(k, args, opmap, oc, decls, fnid)).collect();
            Some((format!(".tup \"{}\" [{}]", &l["@tup:".len()..], ks.join(", ")), st))
        }
        Expr::Opaque(l, xs) if l.starts_with("@field:") && xs.len() == 1 => {
            let (k, st) = lean_key(&xs[0], args, opmap, oc, decls, fnid)?;
            Some((format!(".fld ({k}) \"{}\"", &l["@field:".len()..]), st))
        }
        _ => None,
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
            Some((_, n, t)) if t == "Address" => format!("st.call.argA \"{n}\""),
            Some((_, n, _)) => format!("st.call.arg \"{n}\""),
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
        Expr::Opaque(l, xs) if l == "@pool" && xs.is_empty() => "pool".into(),
        // `has(k)`: k's presence bit, as a Soroban bool (1 = present).
        Expr::Opaque(l, xs) if l == "@has" && xs.len() == 1 && lean_key(&xs[0], args, &mut HashMap::new(), &mut 0, &mut vec![], fnid).is_some() => {
            let (k, st) = lean_key(&xs[0], args, opmap, oc, decls, fnid).unwrap();
            format!("({st} (.has ({k})))")
        }
        Expr::Opaque(l, xs) if l.starts_with("@env:") && xs.is_empty() => format!("(st.call.env \"{}\")", &l["@env:".len()..]),
        // the length of a Vec argument: `claimants.len`.
        Expr::Opaque(l, xs) if l == "@len" && matches!(xs.as_slice(), [Expr::Param(i)] if args.get(*i).is_some()) => {
            let Expr::Param(i) = &xs[0] else { unreachable!() };
            format!("st.call.arg \"{}.len\"", args[*i].1)
        }
        // a field of a struct ARGUMENT: `config.limit`.
        Expr::Opaque(l, xs) if l.starts_with("@field:") && matches!(xs.as_slice(), [Expr::Param(i)] if args.get(*i).is_some()) => {
            let Expr::Param(i) = &xs[0] else { unreachable!() };
            format!("st.call.arg \"{}.{}\"", args[*i].1, &l["@field:".len()..])
        }
        // the address carried by an address-like argument (MuxedAddress etc.)
        Expr::Opaque(l, xs) if l == "@addrof" && xs.len() == 1 => match &xs[0] {
            Expr::Param(i) => args.get(*i).map(|(_, n, _)| format!("st.call.argA \"{n}\"")).unwrap_or_else(|| "pool".into()),
            x => lean_guard_term(x, args, opmap, oc, decls, fnid),
        },
        // SEP-41 `token.balance(who)` on a named token slot: that token's ledger.
        Expr::Opaque(l, xs) if l == "@call:balance" && (xs.len() == 2 || xs.len() == 3)
            && ledger_term(&xs[0], args, &mut HashMap::new(), &mut 0, &mut vec![], fnid).is_some()
            && matches!(&xs[1], Expr::Opaque(v, w) if v == "@vec" && w.len() == 1) =>
        {
            let tok = ledger_term(&xs[0], args, opmap, oc, decls, fnid).unwrap();
            let Expr::Opaque(_, who) = &xs[1] else { unreachable!() };
            // the ledger state at the read's program point (after earlier transfers).
            let state = match xs.get(2) {
                Some(Expr::Opaque(a, k)) if a == "@at" => match k.first() { Some(Expr::Const(site)) => state_at(*site as usize), _ => "st.pre".into() },
                _ => "st.pre".into(),
            };
            format!("(bal {tok} {state} {})", lean_guard_term(&who[0], args, opmap, oc, decls, fnid))
        }
        Expr::Opaque(l, xs) if l == "@bool" && xs.len() == 1 => lean_guard_term(&xs[0], args, opmap, oc, decls, fnid),
        Expr::Opaque(l, xs) if l == "Select" && xs.len() == 3
            && matches!(&xs[0], Expr::Opaque(n, _) if n == "@isfalse" || n == "@and" || n == "@or" || n == "@not" || n.starts_with("ICmp_"))
            && lean_cond(&xs[0], args, &mut HashMap::new(), &mut 0, &mut vec![], fnid).is_some() =>
        {
            let c = lean_cond(&xs[0], args, opmap, oc, decls, fnid).unwrap_or_else(|| "False".into());
            format!(
                "(if {c} then {} else {})",
                lean_guard_term(&xs[1], args, opmap, oc, decls, fnid),
                lean_guard_term(&xs[2], args, opmap, oc, decls, fnid)
            )
        }
        // storage read / vec read / unrecognized op: a fresh opaque Step-term.
        // (We do NOT merge by rendered shape — different i128 reconstructions
        // print identically once their loads are opaque, and merging them would
        // wrongly tie distinct quantities together into contradictory guards.)
        _ => {
            let _ = &opmap;
            *oc += 1;
            let nm = format!("{fnid}_g{oc}");
            decls.push(nm.clone());
            format!("({nm} st)")
        }
    }
}


fn is_zero(e: &Expr) -> bool {
    matches!(e, Expr::Const(0))
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

/// The storage slots an entrypoint touches, with real `DataKey` names:
/// `(slot, mapping-key-types, written, read)` — found transitively through the
/// helpers the entrypoint calls (puts/gets live in `put_reserve_a`,
/// `mint_shares`, … not the entrypoint itself).
fn entry_storage<'c>(
    f: FunctionValue<'c>,
    kb: Option<(FunctionValue<'c>, &(BTreeMap<i64, bool>, bool))>,
    module: &inkwell::module::Module<'c>,
    segs: &[(u64, Vec<u8>)],
) -> Vec<(String, Vec<String>, bool, bool)> {
    let mut out: Vec<(String, Vec<String>, bool, bool)> = vec![];
    let mut memo: HashMap<String, Vec<SFact>> = HashMap::new();
    for sf in storage_summary(f, kb, module, segs, &mut memo, 12) {
        if let KeyRef::Slot(name, params) = sf.key {
            add_slot(&mut out, name, params, sf.put, !sf.put);
        }
    }
    out.sort();
    out
}

/// Record a storage slot, OR-ing access flags and keeping any recovered params.
fn add_slot(out: &mut Vec<(String, Vec<String>, bool, bool)>, name: String, params: Vec<String>, w: bool, r: bool) {
    if let Some(e) = out.iter_mut().find(|(nm, _, _, _)| *nm == name) {
        e.2 |= w;
        e.3 |= r;
        if e.1.is_empty() && !params.is_empty() {
            e.1 = params;
        }
    } else {
        out.push((name, params, w, r));
    }
}

/// A storage access's key, relative to the function it was found in: a resolved
/// slot, or "the key is my parameter #j" (the caller supplies the real key).
#[derive(Clone)]
enum KeyRef {
    Slot(String, Vec<String>),
    Param(usize),      // the key Val is my parameter #j
    DiscParam(usize),  // the key is built from a DataKey discriminant in my parameter #j
    Unknown,
}

/// If key `k` is a `DataKey` built by the builder with its discriminant taken
/// from one of `f`'s parameters, that parameter's index (so the caller's
/// constant discriminant names the slot).
fn key_disc_param<'c>(
    k: BasicValueEnum<'c>,
    f: FunctionValue<'c>,
    kb: Option<(FunctionValue<'c>, &(BTreeMap<i64, bool>, bool))>,
) -> Option<usize> {
    let kb_name = kb?.0.get_name().to_string_lossy().into_owned();
    let mut cur = k;
    for _ in 0..8 {
        let i = as_instr(cur)?;
        let n = callee_name(i)?;
        if n == kb_name {
            // the builder's first operand is the discriminant.
            return match i.get_operand(0) {
                Some(Operand::Value(o)) => param_index(o, f),
                _ => None,
            };
        }
        if n.contains("from_payload") || n.contains("val.payload") {
            if let Some(Operand::Value(inner)) = i.get_operand(0) {
                cur = inner;
                continue;
            }
        }
        break;
    }
    None
}

#[derive(Clone)]
struct SFact {
    key: KeyRef,
    put: bool,
}

/// How to resolve a key value to a `KeyRef` in function `f`: an inline-built
/// `DataKey` resolves to its slot; a key that is just `f`'s parameter is left as
/// `Param(j)` for the caller to fill in.
fn key_ref<'c>(
    k: BasicValueEnum<'c>,
    f: FunctionValue<'c>,
    args: &Args<'c>,
    kb: Option<(FunctionValue<'c>, &(BTreeMap<i64, bool>, bool))>,
    module: &inkwell::module::Module<'c>,
    segs: &[(u64, Vec<u8>)],
) -> KeyRef {
    let (name, params) = storage_key(k, f, args, kb, module, segs);
    if name != "?" {
        KeyRef::Slot(name, params)
    } else if let Some(j) = key_disc_param(k, f, kb) {
        KeyRef::DiscParam(j)
    } else if let Some(j) = param_index(k, f) {
        KeyRef::Param(j)
    } else {
        KeyRef::Unknown
    }
}

/// Resolve a caller-supplied constant discriminant to its slot.
fn disc_slot<'c>(
    d: i64,
    kb: Option<(FunctionValue<'c>, &(BTreeMap<i64, bool>, bool))>,
    module: &inkwell::module::Module<'c>,
    segs: &[(u64, Vec<u8>)],
) -> KeyRef {
    if let Some((kbf, usage)) = kb {
        if let Some(name) = datakey_name(kbf, d, module, segs) {
            let mapping = usage.0.get(&d).copied().unwrap_or(usage.1);
            return KeyRef::Slot(name, if mapping { vec!["Address".to_string()] } else { vec![] });
        }
    }
    KeyRef::Unknown
}

/// Transitive storage-access summary of `f`, over `f`'s OWN parameters: each
/// put/get, with its key resolved to a slot where possible. Descends into
/// helpers and substitutes the caller's actual key at each hop (like
/// `summarize` does for transfers), so a put whose key is a parameter deep in a
/// setter helper is resolved from the discriminant the entrypoint passed.
fn storage_summary<'c>(
    f: FunctionValue<'c>,
    kb: Option<(FunctionValue<'c>, &(BTreeMap<i64, bool>, bool))>,
    module: &inkwell::module::Module<'c>,
    segs: &[(u64, Vec<u8>)],
    memo: &mut HashMap<String, Vec<SFact>>,
    depth: u32,
) -> Vec<SFact> {
    let name = f.get_name().to_string_lossy().into_owned();
    if let Some(v) = memo.get(&name) {
        return v.clone();
    }
    memo.insert(name.clone(), vec![]); // recursion guard
    if depth == 0 {
        return vec![];
    }
    let args = arg_table(f);
    let mut facts = vec![];
    for i in all_instrs(f) {
        let Some(n) = callee_name(i) else { continue };
        if n.contains("put_contract_data") || n.contains("get_contract_data") || n.contains("has_contract_data") {
            let put = n.contains("put_contract_data");
            let key = match i.get_operand(0) {
                Some(Operand::Value(k)) => key_ref(k, f, &args, kb, module, segs),
                _ => KeyRef::Unknown,
            };
            facts.push(SFact { key, put });
            continue;
        }
        let Some(h) = module.get_function(&n) else { continue };
        if h.count_basic_blocks() == 0 {
            continue;
        }
        let hs = storage_summary(h, kb, module, segs, memo, depth - 1);
        // map h's param-relative keys to f's terms via the call-site actuals.
        for sf in hs {
            let key = match sf.key {
                KeyRef::Param(j) => match i.get_operand(j as u32) {
                    Some(Operand::Value(a)) => key_ref(a, f, &args, kb, module, segs),
                    _ => KeyRef::Unknown,
                },
                // the helper's key is a discriminant param: the caller passes a
                // constant discriminant (names the slot) or forwards its own param.
                KeyRef::DiscParam(j) => match i.get_operand(j as u32) {
                    Some(Operand::Value(BasicValueEnum::IntValue(c))) if c.is_const() => {
                        match c.get_sign_extended_constant() {
                            Some(d) => disc_slot(d, kb, module, segs),
                            None => KeyRef::Unknown,
                        }
                    }
                    Some(Operand::Value(a)) => match param_index(a, f) {
                        Some(jj) => KeyRef::DiscParam(jj),
                        None => KeyRef::Unknown,
                    },
                    _ => KeyRef::Unknown,
                },
                other => other,
            };
            facts.push(SFact { key, put: sf.put });
        }
    }
    memo.insert(name, facts.clone());
    facts
}

// ===================== rich entrypoint bodies (transfers + writes) =====================

thread_local! {
    /// The entrypoint being modeled: its name and instruction -> program ordinal.
    static ENTRY: std::cell::RefCell<Option<(String, HashMap<usize, usize>)>> = const { std::cell::RefCell::new(None) };
    /// Program ordinals of the entrypoint's transfer sites, sorted (for states).
    static TX_SITES: std::cell::RefCell<Vec<usize>> = const { std::cell::RefCell::new(vec![]) };
}

/// Run `body` with `f` as the entrypoint being modeled.
fn with_entry<T>(f: FunctionValue, body: impl FnOnce() -> T) -> T {
    use inkwell::values::AsValueRef;
    let map: HashMap<usize, usize> =
        rpo_instrs(f).iter().enumerate().map(|(k, i)| (i.as_value_ref() as usize, k)).collect();
    ENTRY.with(|e| *e.borrow_mut() = Some((f.get_name().to_string_lossy().into_owned(), map)));
    let r = body();
    ENTRY.with(|e| *e.borrow_mut() = None);
    TX_SITES.with(|t| t.borrow_mut().clear());
    r
}

/// The program ordinal of instruction `i` if `g` is the entrypoint being modeled.
fn entry_site(g: FunctionValue, i: InstructionValue) -> Option<usize> {
    use inkwell::values::AsValueRef;
    ENTRY.with(|e| {
        let e = e.borrow();
        let (name, map) = e.as_ref()?;
        if g.get_name().to_string_lossy() != *name {
            return None;
        }
        map.get(&(i.as_value_ref() as usize)).copied()
    })
}

/// Tag every not-yet-tagged `balance()` read in `e` with the program point it
/// happens at (so it reads the ledger state after the transfers before it).
fn annotate_at(e: &Expr, site: usize) -> Expr {
    match e {
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

/// The ledger state a read at program point `site` sees: after the transfers
/// before it (`st.pre` when none).
fn state_at(site: usize) -> String {
    let n = TX_SITES.with(|t| t.borrow().iter().filter(|&&s| s < site).count());
    if n == 0 { "st.pre".into() } else { format!("s{n}") }
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
#[allow(clippy::type_complexity)]
fn effects<'c>(
    h: FunctionValue<'c>,
    module: &inkwell::module::Module<'c>,
    memo: &mut HashMap<String, Option<Expr>>,
    fuel: u32,
) -> Vec<(InstructionValue<'c>, Option<Tx>, Option<Wr>)> {
    let mut out = vec![];
    if fuel == 0 {
        return out;
    }
    let cfg = Cfg::build(h);
    for i in rpo_instrs(h) {
        let Some(cn) = callee_name(i) else { continue };
        let op = |k: u32| match i.get_operand(k) { Some(Operand::Value(x)) => Some(x), _ => None };
        if cn == "call.call" && call_symbol(i).as_deref() == Some("transfer") {
            let tok = op(0).map(|x| value_expr(x, h, module, memo, 40)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            let parts: Vec<Expr> = op(2)
                .map(linmem_vals_ordered)
                .unwrap_or_default()
                .into_iter()
                .map(|x| value_expr(x, h, module, memo, 40))
                .collect();
            if parts.len() == 3 {
                out.push((i, Some((tok, parts[0].clone(), parts[1].clone(), parts[2].clone())), None));
            }
            continue;
        }
        if cn.contains("del_contract_data") {
            let dur = op(1).map(durability).unwrap_or_else(|| "?".into());
            let key = op(0).map(|x| key_expr(x, h, module, memo, 40)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            out.push((i, None, Some((Expr::Opaque(format!("@slot:{dur}"), vec![key]), Expr::Opaque("@del".into(), vec![])))));
            continue;
        }
        if cn.contains("put_contract_data") {
            let dur = op(2).map(durability).unwrap_or_else(|| "?".into());
            let key = op(0).map(|x| key_expr(x, h, module, memo, 40)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            let val = op(1).map(|x| value_expr(x, h, module, memo, 40)).unwrap_or(Expr::Opaque("?".into(), vec![]));
            out.push((i, None, Some((Expr::Opaque(format!("@slot:{dur}"), vec![key]), val))));
            continue;
        }
        let Some(g2) = module.get_function(&cn) else { continue };
        if g2.count_basic_blocks() == 0 {
            continue;
        }
        for (_, tx, wr) in effects(g2, module, memo, fuel - 1) {
            let sub = |e: &Expr, memo: &mut HashMap<String, Option<Expr>>| subst_call(e, i, h, &cfg, module, memo, 40);
            let tx = tx.map(|(a, b, c, d)| (sub(&a, memo), sub(&b, memo), sub(&c, memo), sub(&d, memo)));
            let wr = wr.map(|(k, v)| (sub(&k, memo), sub(&v, memo)));
            out.push((i, tx, wr));
        }
    }
    out
}

/// The rendered Lean body of one entrypoint: threaded transfer states, the post
/// storage after the writes, the written keys, and the opaque terms used.
struct RichBody {
    lets: Vec<String>,
    post: String,
    writes: Vec<String>,
    decls: Vec<String>,
    key_decls: Vec<String>, // opaque Step → Key terms for unnameable written keys
    bool_decls: Vec<String>, // opaque Step → Bool branch conditions that couldn't be rendered
    events: Vec<String>,    // human-readable, for the doc comment
    ret: Option<String>,    // the returned value, when it is a reconstructed scalar
    ok_guard: Option<String>, // a Result-returning call succeeds only when it returns Ok
    auths: Vec<String>,       // require_auth on an address read from storage (not an arg)
}

/// Build the rich body of entrypoint `f` (call inside `with_entry(f, …)`).
fn rich_body<'c>(f: FunctionValue<'c>, module: &inkwell::module::Module<'c>) -> RichBody {
    let args = arg_table(f);
    let kbf = datakey_builder(module);
    let usage = kbf.map(kb_field_usage);
    let kb = kbf.zip(usage.as_ref());
    let segs = rodata_segs(module);
    let cfg = Cfg::build(f);
    let fnid: String = f.get_name().to_string_lossy().chars().map(|c| if c.is_alphanumeric() { c } else { '_' }).collect();
    let tid = format!("{fnid}_e");
    let (mut opmap, mut oc, mut decls) = (HashMap::new(), 0usize, vec![]);
    let evs = with_rich(|| {
        let mut memo = HashMap::new();
        let evs = effects(f, module, &mut memo, 6);
        // each event's program site and path condition (in the entrypoint).
        evs.into_iter()
            .map(|(i, tx, wr)| {
                let site = entry_site(f, i).unwrap_or(0);
                let conds = i.get_parent().and_then(|b| cfg.bidx(b)).map(|b| path_conds(f, &cfg, b, module, &mut memo)).unwrap_or_default();
                let fix = |e: Expr| name_slots(&annotate_at(&fold_rich(simplify(e)), site), module, kb, &segs);
                (site, conds.into_iter().map(|c| name_slots(&c, module, kb, &segs)).collect::<Vec<_>>(),
                 tx.map(|(a, b, c, d)| (fix(a), fix(b), fix(c), fix(d))),
                 wr.map(|(k, v)| (fix(k), fix(v))))
            })
            .collect::<Vec<_>>()
    });
    // every effect (transfer or storage write) is a state; a read sees the
    // state after the effects before it.
    TX_SITES.with(|t| *t.borrow_mut() = evs.iter().filter(|e| e.2.is_some() || e.3.is_some()).map(|e| e.0).collect());
    // a branch condition we can't render is an uninterpreted (Bool) one — never
    // `False`, which would claim the guarded effect cannot happen.
    let mut bool_decls: Vec<String> = vec![];
    let mut cond_str = |cs: &Vec<Expr>, opmap: &mut HashMap<String, String>, oc: &mut usize, decls: &mut Vec<String>| -> Option<String> {
        if cs.is_empty() {
            return None;
        }
        let mut unknown = |oc: &mut usize| {
            *oc += 1;
            let nm = format!("{tid}_c{oc}");
            bool_decls.push(nm.clone());
            format!("({nm} st) = true")
        };
        let parts: Vec<String> = cs
            .iter()
            .map(|c| match c {
                Expr::Opaque(l, x) if l == "@not" && x.len() == 1 => match lean_cond(&x[0], &args, opmap, oc, decls, &tid) {
                    Some(s) => format!("¬({s})"),
                    None => format!("¬({})", unknown(oc)),
                },
                c => lean_cond(c, &args, opmap, oc, decls, &tid).unwrap_or_else(|| unknown(oc)),
            })
            .collect();
        Some(parts.join(" ∧ "))
    };
    let (mut lets, mut writes, mut events) = (vec![], vec![], vec![]);
    let mut key_decls: Vec<String> = vec![];
    let mut cur = "st.pre".to_string();
    let mut nstate = 0;
    for (_site, conds, tx, wr) in &evs {
        let cs = cond_str(conds, &mut opmap, &mut oc, &mut decls);
        let next = |x: String, cur: &str| match &cs { Some(c) => format!("if {c} then {x} else {cur}"), None => x };
        if let Some((tok, from, to, amt)) = tx {
            let ledger = ledger_term(tok, &args, &mut opmap, &mut oc, &mut decls, &tid).unwrap_or_else(|| format!("\"Token?{nstate}\""));
            let (fr, tr, ar) = (
                lean_guard_term(from, &args, &mut opmap, &mut oc, &mut decls, &tid),
                lean_guard_term(to, &args, &mut opmap, &mut oc, &mut decls, &tid),
                lean_guard_term(amt, &args, &mut opmap, &mut oc, &mut decls, &tid),
            );
            nstate += 1;
            lets.push(format!("let s{nstate} := {}", next(format!("xfer {ledger} {cur} ({fr}) ({tr}) ({ar})"), &cur)));
            for p in [&fr, &tr] {
                let k = format!(".entry {ledger} ({p})");
                if !writes.contains(&k) {
                    writes.push(k);
                }
            }
            let ledger_show = if ledger.contains("Token?") { format!("{ledger} = {}", render_expr(tok, &args)) } else { ledger.clone() };
            events.push(format!("transfer {ledger_show}: {} -> {} : {}{}", render_expr(from, &args), render_expr(to, &args), render_expr(amt, &args),
                cs.as_ref().map(|c| format!("   [when {c}]")).unwrap_or_default()));
            cur = format!("s{nstate}");
        }
        if let Some((k, v)) = wr {
            let key = lean_key(k, &args, &mut opmap, &mut oc, &mut decls, &tid).map(|(k, _)| k);
            // an unnameable key is still a write — to SOME key (opaque), never dropped.
            let key = match key {
                Some(k) => k,
                None => {
                    oc += 1;
                    let nm = format!("{tid}_k{oc}");
                    key_decls.push(nm.clone());
                    format!("({nm} st)")
                }
            };
            events.push(format!("write {}{} := {}", render_expr(k, &args), cs.as_ref().map(|c| format!(" [when {c}]")).unwrap_or_default(), render_expr(v, &args)));
            // a struct value is stored field by field (nested structs recursively).
            fn flatten(key: String, v: &Expr, out: &mut Vec<(String, Expr)>) {
                match v {
                    Expr::Opaque(l, xs) if l.starts_with("@struct:") && l["@struct:".len()..].split(',').count() == xs.len() => {
                        for (f, x) in l["@struct:".len()..].split(',').zip(xs) {
                            flatten(format!(".fld ({key}) \"{f}\""), x, out);
                        }
                    }
                    _ => out.push((key, v.clone())),
                }
            }
            let mut sets = vec![];
            let del = matches!(v, Expr::Opaque(l, x) if l == "@del" && x.is_empty());
            if del {
                sets.push((key.clone(), Expr::Const(0)));
            } else {
                flatten(key.clone(), v, &mut sets);
            }
            // a named key's presence: set → 1, remove → 0.
            if !key.ends_with(" st)") {
                sets.push((format!(".has ({key})"), Expr::Const(if del { 0 } else { 1 })));
            }
            let mut upd = cur.clone();
            for (key, v) in &sets {
                let val = lean_guard_term(v, &args, &mut opmap, &mut oc, &mut decls, &tid);
                upd = format!("({upd}).set ({key}) ({val})");
                if !writes.contains(key) {
                    writes.push(key.clone());
                }
            }
            nstate += 1;
            lets.push(format!("let s{nstate} := {}", next(upd, &cur)));
            cur = format!("s{nstate}");
        }
    }
    let post = cur;
    let bool_decls = std::mem::take(&mut bool_decls);
    // the returned value (a scalar Val), read in the final state.
    let ret = with_rich(|| {
        let mut memo = HashMap::new();
        let rets: Vec<InstructionValue> = all_instrs(f).into_iter().filter(|i| i.get_opcode() == InstructionOpcode::Return).collect();
        let mut vals: Vec<Expr> = vec![];
        for r in &rets {
            let Some(Operand::Value(v)) = r.get_operand(0) else { return None };
            let site = entry_site(f, *r).unwrap_or(usize::MAX);
            let e = name_slots(&annotate_at(&fold_rich(simplify(value_expr(v, f, module, &mut memo, 40))), site), module, kb, &segs);
            if !vals.contains(&e) {
                vals.push(e);
            }
        }
        if std::env::var("SDBG").is_ok() { for v in &vals { eprintln!("RET {}: {}", fnid, render_expr(v, &args)); } }
        match vals.as_slice() {
            [e] => Some(e.clone()),
            _ => None,
        }
    });
    // a Result-returning entrypoint: the Ok condition is a guard of the step.
    let ok_guard = ret
        .as_ref()
        .and_then(ok_condition)
        .and_then(|c| lean_cond(&c, &args, &mut opmap, &mut oc, &mut decls, &tid));
    let ret = ret
        .filter(|e| !matches!(e, Expr::Opaque(l, _) if l == "@vec" || l == "big") && (expr_has_named(e) || ok_guard.is_some()))
        .map(|e| lean_guard_term(&e, &args, &mut opmap, &mut oc, &mut decls, &tid));
    // `x.require_auth()` on an address that isn't an argument (e.g. a struct
    // field in storage): that address must have signed.
    let auths: Vec<String> = with_rich(|| {
        let mut memo = HashMap::new();
        let mut out = vec![];
        for i in all_instrs(f) {
            if !callee_name(i).is_some_and(|n| n.contains("require_auth")) {
                continue;
            }
            let Some(Operand::Value(v)) = i.get_operand(0) else { continue };
            let site = entry_site(f, i).unwrap_or(0);
            let e = name_slots(&annotate_at(&fold_rich(simplify(value_expr(v, f, module, &mut memo, 40))), site), module, kb, &segs);
            if matches!(e, Expr::Param(_)) || lean_key(&e, &args, &mut HashMap::new(), &mut 0, &mut vec![], &tid).is_none() {
                continue;
            }
            let t = lean_guard_term(&e, &args, &mut opmap, &mut oc, &mut decls, &tid);
            if !out.contains(&t) {
                out.push(t);
            }
        }
        out
    });
    RichBody { lets, post, writes, decls: std::mem::take(&mut decls), key_decls, bool_decls, events, ret, ok_guard, auths }
}

/// Emit a relational abstraction of the contract: one `Step → Prop` per
/// entrypoint, in the style of stellar-lean-playground's `SorobanAmm.lean`.
/// RECOVERED exactly from the bytecode: the entrypoints + their ABI args, the
/// SEP-41 transfer DIRECTIONS (traced transitively through fastcc helpers), and
/// the storage slots each entrypoint writes/reads (real `DataKey` names from the
/// data section). UNINTERPRETED (the nonlinear fee / share math the lifter marks
/// opaque): transfer amounts and stored values — emitted as `opaque` Step-indexed
/// terms, so the model is faithful about exactly what was and was not recovered.
fn emit_lean_model(entries: &[ModelEntry]) {
    let san = |s: &str| s.chars().map(|c| if c.is_alphanumeric() { c } else { '_' }).collect::<String>();
    println!("-- Auto-emitted by stellar-diver: a relational abstraction of the contract,");
    println!("-- one `Step → Prop` per entrypoint, in the style of SorobanAmm.lean.");
    println!("--");
    println!("-- RECONSTRUCTED from the bytecode, in terms of call arguments, storage slots");
    println!("-- (real DataKey names) and token ledgers:");
    println!("--   * effects, in program order, as a chain of states s1, s2, …: SEP-41");
    println!("--     transfers (`xfer`: ledger, from, to, amount) and storage writes, each");
    println!("--     under the (non-panic) branch condition it runs in;");
    println!("--   * every read sees the state at its program point (a balance read after a");
    println!("--     transfer reads the post-transfer ledger; a slot read after a write");
    println!("--     reads the write — e.g. a token's self-transfer nets to zero);");
    println!("--   * guards: require_auth, every panic condition and `Err` return, as the");
    println!("--     condition to pass.");
    println!("-- Values are rebuilt through i128 helper routines (__muloti4 / __divti3), out-");
    println!("-- pointer returns and by-reference closure captures on the wasm shadow stack.");
    println!("--");
    println!("-- Storage keys: `.var` (unit variant), `.entry` / `.tup` (variants with one /");
    println!("-- several fields), `.fld k f` (field f of the #[contracttype] struct stored at");
    println!("-- k, nested structs field by field) and `.has k` (k's presence: set → 1,");
    println!("-- remove → 0). Struct arguments' fields are args named `config.limit`.");
    println!("--");
    println!("-- STILL `opaque`: values from loops (e.g. an integer sqrt), tuple and whole-");
    println!("-- struct returns, enum values carried as data, and whatever the");
    println!("-- reconstruction could not resolve (a branch condition so becomes an opaque");
    println!("-- `Step → Bool`, never `False`).");
    println!("-- ASSUMES token ledgers are keyed by the storage slot holding the token");
    println!("-- address (`\"TokenA\"`, `\"Offer.buy_token\"`), i.e. distinct slots hold");
    println!("-- distinct tokens; an absent key reads as 0 (`get(k).unwrap_or(0)`); the");
    println!("-- host's address order (`obj_cmp`) is the order on `Addr`; loops terminate.");
    println!("-- Reads/writes inside one helper call are ordered at the call's position.\n");
    println!("namespace Contract\n");
    println!("abbrev Addr := Int\n");
    println!("inductive Key where");
    println!("  | var   (name : String)");
    println!("  | entry (map : String) (k : Addr)");
    println!("  | tup   (map : String) (ks : List Int)   -- a multi-field key variant, `Minter(a, b)`");
    println!("  | fld   (base : Key) (f : String)   -- a field of the #[contracttype] struct at `base`");
    println!("  | has   (k : Key)                   -- k's presence (1 = set): `has(k)`, written by set/remove");
    println!("  deriving DecidableEq, Inhabited\n");
    println!("abbrev Storage := Key → Int");
    println!("def Storage.set (s : Storage) (k : Key) (v : Int) : Storage := fun k' => if k' = k then v else s k'\n");
    println!("structure Call where");
    println!("  fn     : String");
    println!("  caller : Addr");
    println!("  arg    : String → Int   -- numeric args by name");
    println!("  argA   : String → Addr  -- address args by name");
    println!("  signed : Addr → Prop    -- addresses that authorized the call (require_auth)");
    println!("  env    : String → Int   -- ledger info (`sequence`, `timestamp`)\n");
    println!("structure Step where");
    println!("  call   : Call");
    println!("  pre    : Storage");
    println!("  post   : Storage");
    println!("  writes : List Key");
    println!("  ret    : Int\n");
    println!("/-- the pool's own address (`e.current_contract_address()`). -/");
    println!("opaque pool : Addr\n");
    println!("/-- a token ledger `m`'s balance of `a`. -/");
    println!("def bal (m : String) (s : Storage) (a : Addr) : Int := s (.entry m a)");
    println!("/-- storage after token `m` moves `amt` from `src` to `dst`. -/");
    println!("def xfer (m : String) (s : Storage) (src dst : Addr) (amt : Int) : Storage :=");
    println!("  let s1 := s.set (.entry m src) (bal m s src - amt)   -- (a self-transfer nets to zero)");
    println!("  s1.set (.entry m dst) (bal m s1 dst + amt)\n");
    // the fee-adjusted constant-product invariant the contract checks on itself
    // (new_inv_a*new_inv_b). Opaque: we recover that it is CHECKED, not its formula.
    if entries.iter().any(|e| e.inv) {
        println!("/-- the fee-adjusted constant-product invariant value `new_inv_a*new_inv_b`,");
        println!("    the quantity the contract's `constant product` panic compares. -/");
        println!("opaque invProduct : Storage → Int\n");
    }

    for e in entries {
        let fn_id = san(&e.name);
        // signature comment
        let sig: Vec<String> = e.args.iter().map(|(n, t)| format!("{n}: {t}")).collect();
        println!("/-- `{}({})`", e.name, sig.join(", "));
        if let Some(rb) = &e.rich {
            println!("    effects (reconstructed, in program order):");
            for ev in &rb.events {
                println!("      {ev}");
            }
        } else if e.transfers.is_empty() {
            println!("    transfers: (none recovered)");
        } else {
            println!("    transfers (direction recovered; amount uninterpreted):");
            for (k, (from, to)) in e.transfers.iter().enumerate() {
                println!("      {}: {from} -> {to}", e.tokens[k]);
            }
        }
        if e.rich.is_none() && !e.writes.is_empty() {
            let ws: Vec<String> = e.writes.iter().map(|(s, _)| s.clone()).collect();
            println!("    writes storage: {}", ws.join(", "));
        }
        // the recovered transition guards: auth, then every trap (panic) gate.
        if e.auth.is_some() || !e.guards.is_empty() {
            println!("    guards (recovered panic/gate conditions):");
            if let Some(a) = &e.auth {
                println!("      auth: caller signed as `{a}` (require_auth)");
            }
            for a in &e.more_auths {
                println!("      auth: `{a}` also authorized the call (require_auth)");
            }
            for g in &e.guards {
                println!("      gate: {}", g.comment);
            }
        }
        println!("-/");
        // opaque Step-terms for anything not reconstructed.
        if let Some(rb) = &e.rich {
            for d in &rb.decls {
                println!("opaque {d} : Step → Int");
            }
            for d in &rb.key_decls {
                println!("opaque {d} : Step → Key");
            }
            for d in &rb.bool_decls {
                println!("opaque {d} : Step → Bool");
            }
        } else {
            for k in 0..e.transfers.len() {
                println!("opaque {fn_id}_amt{k} : Step → Int");
            }
            for (slot, _) in &e.writes {
                println!("opaque {fn_id}_v_{} : Step → Int", san(slot));
            }
        }
        for d in &e.gdecls {
            println!("opaque {d} : Step → Int");
        }
        if e.returns && e.rich.as_ref().and_then(|rb| rb.ret.as_ref()).is_none() {
            println!("opaque {fn_id}_ret : Step → Int");
        }
        // the Step -> Prop model
        println!("def {fn_id} : Step → Prop := fun st =>");
        println!("  let c := st.call.caller");
        // thread the transfers
        let mut cur = "st.pre".to_string();
        if let Some(rb) = &e.rich {
            for l in &rb.lets {
                println!("  {l}");
            }
        }
        for (k, (from, to)) in e.transfers.iter().enumerate().filter(|_| e.rich.is_none()) {
            let next = format!("s{}", k + 1);
            println!(
                "  let {next} := xfer \"{}\" {cur} {from} {to} ({fn_id}_amt{k} st)",
                e.tokens[k]
            );
            cur = next;
        }
        // post: fold the recovered storage writes onto the post-transfer storage
        let key_term = |slot: &str, mapping: bool| -> String {
            if mapping {
                format!(".entry \"{slot}\" c") // mapping keyed by the caller
            } else {
                format!(".var \"{slot}\"")
            }
        };
        let mut post = cur.clone();
        for (slot, mapping) in &e.writes {
            post = format!("({post}.set ({}) ({fn_id}_v_{} st))", key_term(slot, *mapping), san(slot));
        }
        let mut writes_list: Vec<String> = e.writes.iter().map(|(s, m)| key_term(s, *m)).collect();
        if let Some(rb) = &e.rich {
            post = rb.post.clone();
            writes_list = rb.writes.clone();
        }
        let rich_ret = e.rich.as_ref().and_then(|rb| rb.ret.clone());
        let ret = match (&rich_ret, e.returns) {
            (Some(r), true) => r.clone(),
            (_, true) => format!("{fn_id}_ret st"),
            _ => "0".to_string(),
        };
        println!("  st.call.fn = \"{}\" ∧", e.name);
        println!("  c ≠ pool ∧");
        // recovered transition guards: auth, then the constant-product check.
        if let Some(a) = &e.auth {
            println!("  c = st.call.argA \"{a}\" ∧   -- require_auth");
        }
        for a in &e.more_auths {
            println!("  st.call.signed (st.call.argA \"{a}\") ∧   -- require_auth");
        }
        for a in e.rich.iter().flat_map(|rb| &rb.auths) {
            println!("  st.call.signed {a} ∧   -- require_auth");
        }
        if e.inv {
            println!("  invProduct st.pre ≤ invProduct st.post ∧   -- constant-product trap");
        }
        // the recovered panic gates as pass conditions over args + storage.
        for g in &e.guards {
            println!("  {} ∧   -- gate", g.lean);
        }
        if let Some(okg) = e.rich.as_ref().and_then(|rb| rb.ok_guard.as_ref()) {
            println!("  ({okg}) ∧   -- returns Ok (an Err return fails the call)");
        }
        println!("  st.post = {post} ∧");
        println!("  st.writes = [{}] ∧", writes_list.join(", "));
        println!("  st.ret = {ret}\n");

        // the recovered constant-product guard is itself a value invariant:
        // emit the one-step monotonicity theorem, projected out of the def.
        if e.inv {
            let before = 2 + if e.auth.is_some() { 1 } else { 0 }; // fn, c≠pool, [auth]
            let path = ".2".repeat(before) + ".1"; // invProduct is the next conjunct
            println!("-- VALUE INVARIANT: a `{}` never decreases the constant product.", e.name);
            println!("theorem {fn_id}_keeps_product (st : Step) (h : {fn_id} st) :");
            println!("    invProduct st.pre ≤ invProduct st.post := h{path}\n");
        }
    }

    // the contract as the list of its entrypoints (cf. SorobanAmm.contract).
    let names: Vec<String> = entries.iter().map(|e| san(&e.name)).collect();
    println!("/-- the contract's entry points (each a `Step → Prop`). -/");
    println!("def entries : List (Step → Prop) := [{}]\n", names.join(", "));

    // inductive no-drain: the invariant never falls below its start across any
    // sequence of the invariant-guarded entrypoint's calls.
    if let Some(e) = entries.iter().find(|e| e.inv) {
        let fn_id = san(&e.name);
        println!("-- VALUE INVARIANT (inductive): across any sequence of `{}` calls the", e.name);
        println!("-- constant product never falls below its start -- no draining by swapping.");
        println!("inductive Reach : Storage → Storage → Prop where");
        println!("  | refl (s) : Reach s s");
        println!("  | step {{s}} (st : Step) : Reach s st.pre → {fn_id} st → Reach s st.post\n");
        println!("theorem no_drain (s t : Storage) (r : Reach s t) : invProduct s ≤ invProduct t := by");
        println!("  induction r with");
        println!("  | refl => omega");
        println!("  | step st _ h ih => have hp := {fn_id}_keeps_product st h; omega\n");
    }
    println!("end Contract");
}

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
    // the DataKey builder + rodata, for resolving real storage-slot names (model).
    let m_kb = datakey_builder(&module);
    let m_usage = m_kb.map(kb_field_usage);
    let m_kb_pair = m_kb.zip(m_usage.as_ref());
    let m_segs = rodata_segs(&module);
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
            let mut memo = HashMap::new();
            let facts = summarize(f, &module, &mut memo, 12);
            let transfers: Vec<(String, String)> = facts
                .iter()
                .map(|tf| (party_term(tf.from).to_string(), party_term(tf.to).to_string()))
                .collect();
            // token ledgers by recovered transfer order (A first, then B).
            let tokens: Vec<String> = (0..facts.len())
                .map(|k| if k % 2 == 0 { "A.Balance".into() } else { "B.Balance".into() })
                .collect();
            let stores = entry_storage(f, m_kb_pair, &module, &m_segs);
            let writes: Vec<(String, bool)> = stores
                .iter()
                .filter(|(_, _, w, _)| *w)
                .map(|(n, p, _, _)| (n.clone(), !p.is_empty()))
                .collect();
            let returns = f
                .get_string_attribute(AttributeLoc::Function, "spec.type")
                .or_else(|| f.get_string_attribute(AttributeLoc::Return, "spec.type"))
                .map(|a| a.get_string_value().to_string_lossy().into_owned())
                .map(|s| !s.is_empty() && s != "void")
                .unwrap_or(false);
            let auth = entry_auth(f);
            let inv = has_product_invariant_trap(f, &module);
            let (rb, gset) = with_entry(f, || {
                let rb = rich_body(f, &module);
                let gs = entry_guards(f, &module);
                (rb, gs)
            });
            let (guards, gdecls) = (gset.guards, gset.decls);
            let rich = (!rb.lets.is_empty() || !rb.writes.is_empty() || rb.ret.is_some()).then_some(rb);
            model_entries.push(ModelEntry {
                name, args, transfers, tokens, writes, returns, auth, inv, guards, gdecls, rich,
                more_auths: entry_auths(f).into_iter().skip(1).collect(),
            });
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
        emit_lean_model(&model_entries);
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
