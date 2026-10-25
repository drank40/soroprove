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
    AnyValue, BasicValueEnum, FunctionValue, InstructionOpcode, InstructionValue, Operand,
    PointerValue,
};
use std::collections::{BTreeSet, HashMap, HashSet, VecDeque};
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
    f.get_params()
        .iter()
        .enumerate()
        .any(|(i, _)| f.get_string_attribute(AttributeLoc::Param(i as u32), "spec.name").is_some())
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
fn is_wrapper(name: &str) -> bool {
    name.contains("from_payload")
        || name.contains("val.payload")
        || name.contains("obj_to_u128")
        || name.contains("obj_to_i128")
        || name.contains("obj_to_u64")
        || name.contains("obj_to_i64")
        || name.contains("obj_from_u64")
        || name.contains("obj_from_i64")
}

/// Base identity + byte offset of a pointer (chasing geps to the alloca).
fn ptr_base_off(p: BasicValueEnum) -> (String, i64) {
    if let Some(i) = as_instr(p) {
        if i.get_opcode() == InstructionOpcode::GetElementPtr {
            if let Some(Operand::Value(base)) = i.get_operand(0) {
                let (b, o) = ptr_base_off(base);
                return (b, o + gep_off(p));
            }
        }
    }
    (fmt(p), 0)
}

/// The value feeding a `load`, via store-forwarding. First the reaching
/// definition within the load's own basic block (the latest preceding store to
/// the same slot) — this resolves the common spill-then-reload pattern even when
/// the frame slot is reused elsewhere. Failing that, a whole-function UNIQUE
/// store (a single definition). Both are sound; neither blows up.
fn forward_load<'c>(load: InstructionValue<'c>, g: FunctionValue<'c>) -> Option<BasicValueEnum<'c>> {
    let ptr = match load.get_operand(0) {
        Some(Operand::Value(p)) => p,
        _ => return None,
    };
    let target = ptr_base_off(ptr);
    // (1) latest store to this slot earlier in the load's own block.
    if let Some(blk) = load.get_parent() {
        let mut latest = None;
        let mut it = blk.get_first_instruction();
        while let Some(i) = it {
            if i == load {
                break;
            }
            if i.get_opcode() == InstructionOpcode::Store {
                if let (Some(Operand::Value(sval)), Some(Operand::Value(sptr))) =
                    (i.get_operand(0), i.get_operand(1))
                {
                    if sptr == ptr || ptr_base_off(sptr) == target {
                        latest = Some(sval);
                    }
                }
            }
            it = i.get_next_instruction();
        }
        if latest.is_some() {
            return latest;
        }
    }
    // (2) whole-function unique store.
    let mut found = None;
    let mut count = 0usize;
    for i in all_instrs(g) {
        if i.get_opcode() != InstructionOpcode::Store {
            continue;
        }
        let (Some(Operand::Value(sval)), Some(Operand::Value(sptr))) =
            (i.get_operand(0), i.get_operand(1)) else { continue };
        if sptr == ptr || ptr_base_off(sptr) == target {
            found = Some(sval);
            count += 1;
        }
    }
    if count == 1 { found } else { None }
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
            if let Some(lo) = o(1) {
                return value_expr(lo, g, module, memo, depth - 1); // low limb carries the value
            }
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
        // extension / truncation is limb bookkeeping -> the value passes through.
        SExt | ZExt | Trunc => {
            if let Some(x) = o(0) {
                return value_expr(x, g, module, memo, depth - 1);
            }
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
        }
        _ => {}
    }

    // ---- unrecognized: uninterpreted function of recovered inputs ----
    let label = callee_name(ins).filter(|n| !n.is_empty()).unwrap_or_else(|| format!("{:?}", ins.get_opcode()));
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

/// Substitute a callee's param-relative expression with the caller's arg exprs.
fn subst(e: &Expr, actuals: &[Expr]) -> Expr {
    match e {
        Expr::Param(i) => actuals.get(*i).cloned().unwrap_or(Expr::Opaque("arg".into(), vec![])),
        Expr::Bin(op, a, b) => Expr::Bin(*op, Box::new(subst(a, actuals)), Box::new(subst(b, actuals))),
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

/// Collapse the 64-bit-multiply-from-32-bit-limbs idiom back to a Mul:
///   (lo A * hi B + hi A * lo B) << 32  +  lo A * lo B   ==>   A * B
/// (bottom-up), so a native i64 `y*dx` lowered to limb products reads as `y*dx`.
fn simplify(e: Expr) -> Expr {
    let e = match e {
        Expr::Bin(op, a, b) => Expr::Bin(op, Box::new(simplify(*a)), Box::new(simplify(*b))),
        Expr::Opaque(l, xs) => Expr::Opaque(l, xs.into_iter().map(simplify).collect()),
        x => x,
    };
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

/// (legacy) assume-the-bound variant, kept unused.
#[allow(dead_code)]
fn emit_lean_cpmm(swap_names: &[String], u256_ops: usize) {
    println!("-- Auto-emitted by stellar-diver from lifted LLVM IR.");
    println!("-- Constant-product NO-DRAIN for the pool's exchange entrypoint(s): {}.", swap_names.join(", "));
    println!("-- RECOVERED from bytecode (SEP-41 transfer summary, any depth): each is an");
    println!("--   exchange taking dx of the input token (user->pool) and returning `out` of");
    println!("--   the output token (pool->user) between two reserves. The swap formula's");
    println!("--   fee/product arithmetic is present ({u256_ops} u256 mul/div ops recovered).");
    println!("-- MODELED (one spec hypothesis `hcp`): the output never exceeds the constant-");
    println!("--   product amount, (x+dx)*out <= dx*y (fees only tighten it). Discharging hcp");
    println!("--   from the exact fee formula is the remaining obligation.\n");
    println!("namespace Pool\n");
    println!("structure State where");
    println!("  x  : Int   -- pool reserve of the input token");
    println!("  y  : Int   -- pool reserve of the output token");
    println!("  k0 : Int   -- initial product (the invariant target)\n");
    println!("def Inv (s : State) : Prop := 0 ≤ s.x ∧ 0 ≤ s.y ∧ s.k0 ≤ s.x * s.y\n");
    println!("-- one exchange: dx in (user->pool), out out (pool->user).");
    println!("def swap (s : State) (dx out : Int) : State := {{ s with x := s.x + dx, y := s.y - out }}\n");
    println!("-- NONLINEAR CORE: the constant-product bound makes the product non-decreasing.");
    println!("theorem no_drain_step (s : State) (dx out : Int)");
    println!("    (hdx : 0 ≤ dx) (houtlt : out ≤ s.y)");
    println!("    (hcp : (s.x + dx) * out ≤ dx * s.y) (h : Inv s) : Inv (swap s dx out) := by");
    println!("  have hx := h.1; have hk := h.2.2");
    println!("  refine ⟨by simp only [swap]; omega, by simp only [swap]; omega, ?_⟩");
    println!("  simp only [swap]");
    println!("  have e1 : (s.x + dx) * (s.y - out) = (s.x + dx) * s.y - (s.x + dx) * out := by rw [Int.mul_sub]");
    println!("  have e2 : (s.x + dx) * s.y = s.x * s.y + dx * s.y := by rw [Int.add_mul]");
    println!("  have hp : s.x * s.y ≤ (s.x + dx) * (s.y - out) := by rw [e1, e2]; omega");
    println!("  omega\n");
    println!("-- every state reachable by any sequence of (formula-respecting) swaps.");
    println!("inductive Reachable (p : State) : State → Prop where");
    println!("  | refl : Reachable p p");
    println!("  | step {{q : State}} {{dx out : Int}} :");
    println!("      Reachable p q → 0 ≤ dx → out ≤ q.y → (q.x + dx) * out ≤ dx * q.y →");
    println!("      Reachable p (swap q dx out)\n");
    println!("-- NO-DRAIN: the invariant holds at every reachable state.");
    println!("theorem no_drain (p : State) (h : Inv p) : ∀ q, Reachable p q → Inv q := by");
    println!("  intro q r");
    println!("  induction r with");
    println!("  | refl => exact h");
    println!("  | step _ hdx houtlt hcp ih => exact no_drain_step _ _ _ hdx houtlt hcp ih\n");
    println!("theorem k0_const (p q : State) (r : Reachable p q) : q.k0 = p.k0 := by");
    println!("  induction r with");
    println!("  | refl => rfl");
    println!("  | step _ _ _ _ ih => simpa only [swap] using ih\n");
    println!("-- the product never drops below its initial value k0 -- the pool cannot be drained.");
    println!("theorem product_floor (p q : State) (h : Inv p) (r : Reachable p q) : p.k0 ≤ q.x * q.y := by");
    println!("  have hq := (no_drain p h q r).2.2");
    println!("  rw [k0_const p q r] at hq; exact hq\n");
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

// ======================= driver =======================

fn main() {
    let mut args = std::env::args().skip(1);
    let path = PathBuf::from(
        args.next()
            .expect("usage: slice <file.ll> [--fn F] [--sink transfer|trap|error|error-ret|all] [--callee call] [--sym transfer|any]"),
    );
    let (mut only_fn, mut callee, mut sym, mut sink_sel, mut raw, mut lean_sm, mut amm_dbg, mut lean_amm, mut expr_dbg, mut lean_pool, mut lean_cpmm) =
        (None, "call".to_string(), Some("transfer".to_string()), "all".to_string(), false, false, false, false, false, false, false);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--fn" => only_fn = args.next(),
            "--callee" => callee = args.next().unwrap(),
            "--sym" => sym = args.next(),
            "--sink" => sink_sel = args.next().unwrap(),
            "--raw" => raw = true,
            "--lean-sm" => lean_sm = true,
            "--amm-dbg" => amm_dbg = true,
            "--lean-amm" => lean_amm = true,
            "--lean-pool" => lean_pool = true,
            "--lean-cpmm" => lean_cpmm = true,
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

    let mut transes: Vec<Trans> = vec![];
    let mut all_slots: BTreeSet<String> = BTreeSet::new();
    let mut amm_entries: Vec<(String, Vec<(&'static str, &'static str, bool)>)> = vec![];
    let mut pool_entries: Vec<PoolEntry> = vec![];
    let mut cpmm_hits: Vec<(String, String, String, String)> = vec![];
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
