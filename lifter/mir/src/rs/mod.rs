//! optimized MIR -> Rust, structured.
//!
//! The control flow comes from rustc's own analyses over the body: reverse
//! postorder, dominators, predecessors. A block that two edges reach is
//! placed after its immediate dominator inside a labelled block, so a jump
//! to it is `break 'b`; a loop header is `'l: loop { .. }` and its back edges
//! `continue 'l`; every other block has one predecessor and is written inline
//! where that predecessor branches. A jump that is the last thing before its
//! target falls through instead, and a label nothing jumps to is not written.
//! This is the Ramsey algorithm for reducible graphs, which is what inlined
//! wasm gives; anything else falls back to a state machine and says so.
//!
//! Every local is declared once and assigned where MIR assigns it; rustc's
//! definite-initialisation check on the output then confirms what MIR's
//! borrow check already established.
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::fmt::Write as _;
use rustc_middle::mir::*;
use rustc_middle::ty::{self, TyCtxt};
use crate::mir::Env;

mod calls;
mod decode;
mod frames;
mod sdk;
mod spec;
mod structure;
mod text;
mod values;
pub use spec::Spec;
use spec::*;
use text::*;

type R<T> = Result<T, String>;

/// One storage access: durability, key shape, operation (with the value for
/// a put), function.
type Access = (String, String, String, String);

/// What one function's emission tells the others: what a helper returns, in
/// terms of its parameters; which parameters a helper uses as storage keys;
/// who is called at all. Filled by one pass, read by the next.
/// A switch arm a value was made under: the word read through a pointer
/// parameter (`a0@0`), the arm's values, and whether this is the arm for
/// every other value.
type Cond = (String, Vec<u64>, bool);

#[derive(Default)]
struct Inter {
    /// fn -> (shape of a returned value, the fn's parameter names to
    /// substitute, the arms it was returned under).
    ret_shapes: HashMap<String, Vec<(String, Vec<String>, Vec<Cond>)>>,
    /// fn -> the spec types it unpacks from the host (a struct's fields, a
    /// union's cases): what a `try_from_val` derive does.
    unpacks: HashMap<String, Vec<String>>,
    /// fn -> (identifier, doc) for helpers recognised as `#[contracttype]`
    /// derives. Filled once the summaries are final.
    renames: HashMap<String, (String, String)>,
    /// fn -> the error it hands the host: a `panic_with_error!` wrapper.
    fails: HashMap<String, String>,
    /// fns with no return: every path traps.
    diverges: HashSet<String>,
    /// fn -> (parameter index used as key, operation, durability).
    param_accesses: HashMap<String, Vec<(usize, String, String)>>,
    called: HashSet<String>,
    schema: Vec<Access>,
    /// fn -> (pointer parameter it writes through, itself or by a call; how
    /// far past the pointer, when every write is at a constant offset).
    /// Every emitted fn has an entry.
    param_writes: HashMap<String, Vec<(usize, Option<u64>)>>,
    /// fn -> (text position param, length param, "Symbol" | "String"): a
    /// helper that is the SDK's `Symbol::new` / `String::from_str`. Read off
    /// the final summaries.
    text_helpers: HashMap<String, (usize, usize, &'static str)>,
    /// The SDK's `SymbolSmall::try_from_bytes`, by what it computes.
    encoders: HashSet<String>,
}

/// `Symbol(@Val::u32(a0 as u32), Val::u32(a1 as u32))`, every return of the
/// helper: it builds its result from the text at two of its parameters.
fn text_params(template: &str, params: &[String]) -> Option<(usize, usize, &'static str)> {
    let kind = if template.starts_with("Symbol(@") { "Symbol" } else if template.starts_with("String(@") { "String" } else { return None };
    let mut idx = template.split("Val::u32(").skip(1).map(|r| {
        let w: String = r.chars().take_while(|c| c.is_ascii_alphanumeric() || *c == '_').collect();
        params.iter().position(|p| *p == w)
    });
    let (Some(Some(i)), Some(Some(j)), None) = (idx.next(), idx.next(), idx.next()) else { return None };
    (i != j).then_some((i, j, kind))
}

/// Every function's summaries, iterated to a fixpoint, then what is read off
/// them: the text helpers, the derive renames, the functions that never return.
fn summaries<'tcx>(tcx: TyCtxt<'tcx>, env: &Env<'tcx>, bodies: &[&Body<'tcx>], spec: &Spec) -> R<Inter> {
    // Helpers' return shapes and key parameters are known to their callers
    // only once every body has been seen, and a helper's own summary
    // sharpens once its callees' are known: each pass reads the previous
    // pass's summaries and writes fresh ones, until they stop changing; the
    // last pass emits with the complete set.
    // The small-symbol encoder: six bits a character under tag 14. Those are
    // the Val encoding, not the compiler's, so no fingerprint is needed.
    // diver: three parameters and the two constants; not checked to write
    // its result through the first.
    let has_const = |b: &Body<'tcx>, op: BinOp, k: u128| {
        b.basic_blocks.iter().flat_map(|d| &d.statements).any(|st| match &st.kind {
            StatementKind::Assign(a) => match &a.1 {
                Rvalue::BinaryOp(o, ab) if *o == op => matches!(&ab.1, Operand::Constant(c) if c.const_.try_to_scalar_int().map(|i| i.to_bits(i.size())) == Some(k)),
                _ => false,
            },
            _ => false,
        })
    };
    let encoders: HashSet<String> = bodies
        .iter()
        .filter(|b| (2..=3).contains(&b.arg_count) && has_const(b, BinOp::Shl, 6) && has_const(b, BinOp::BitOr, 14))
        .map(|b| tcx.item_name(b.source.def_id()).to_string())
        .collect();
    let mut prev = Inter { encoders: encoders.clone(), ..Default::default() };
    for _ in 0..8 {
        // diver: a summary chain deeper than 8 calls stays partly unresolved (shown as `_`).
        let cur = RefCell::new(Inter { encoders: encoders.clone(), ..Default::default() });
        for body in bodies {
            Fn_::new(tcx, env, body, spec, &prev, &cur, false).emit()?;
        }
        let cur = cur.into_inner();
        let stable = cur.ret_shapes == prev.ret_shapes && cur.param_accesses == prev.param_accesses && cur.called == prev.called && cur.unpacks == prev.unpacks && cur.param_writes == prev.param_writes && cur.fails == prev.fails;
        prev = cur;
        if stable {
            break;
        }
    }
    prev.text_helpers = prev
        .ret_shapes
        .iter()
        .filter_map(|(f, ts)| {
            let mut ps = ts.iter().map(|(t, params, _)| text_params(t, params));
            let first = ps.next()??;
            ps.all(|p| p == Some(first)).then(|| (f.clone(), first))
        })
        .collect();
    // Helpers that are `#[contracttype]` derives: every return one case of
    // one union or one struct's map is its `into_val`; unpacking one type's
    // fields or cases is its `try_from_val`.
    // Any function that is not an export, whatever it is called (a build
    // that kept its names calls a derive `from_val`).
    let is_helper = |f: &str| !spec.params.contains_key(f) && !prev.schema.iter().any(|(_, _, _, who)| who == f || who.starts_with(&format!("{f} via ")));
    let owner = |s: &str| -> Option<String> {
        let s = s.rsplit_once(" /* ").map(|(_, c)| c.trim_end_matches(" */")).unwrap_or(s);
        if let Some((u, _)) = s.split_once("::") {
            if spec.union_cases.iter().any(|(n, _)| n == u) {
                return Some(u.to_string());
            }
        }
        s.split_once(" {").map(|(st, _)| st).filter(|st| spec.struct_fields.contains_key(*st)).map(str::to_string)
    };
    let mut renames: HashMap<String, (String, String)> = HashMap::new();
    let mut used: HashSet<String> = HashSet::new();
    let mut encs: Vec<&String> = prev.encoders.iter().collect();
    encs.sort();
    // Two helpers for one derive (a monomorphisation, a wrapper): numbered.
    let name = |used: &mut HashSet<String>, base: String| -> String {
        let mut n = base.clone();
        let mut k = 2;
        while !used.insert(n.clone()) {
            n = format!("{base}_{k}");
            k += 1;
        }
        n
    };
    let unnamed = |f: &str| f.strip_prefix('f').is_some_and(|d| !d.is_empty() && d.chars().all(|c| c.is_ascii_digit()));
    for f in encs {
        // `(out, ptr, len)` is `SymbolSmall::try_from_bytes`; `(out, &&str)` is
        // `Symbol::try_from_val`, which inlines it. A build that kept its
        // names has said which already.
        let three = bodies.iter().any(|b| b.arg_count == 3 && tcx.item_name(b.source.def_id()).as_str() == f);
        if unnamed(f) {
            let id = name(&mut used, if three { "SymbolSmall_try_from_bytes" } else { "Symbol_try_from_val" }.into());
            let doc = if three { "/// The SDK's `SymbolSmall::try_from_bytes`: a short symbol packed from its text.\n" } else { "/// The SDK's `Symbol::try_from_val` from a `&str`.\n" };
            renames.insert(f.clone(), (id, doc.into()));
        }
        if three {
            prev.text_helpers.insert(f.clone(), (1, 2, "Symbol"));
        }
    }
    let mut fs: Vec<&String> = prev.ret_shapes.keys().collect();
    fs.sort();
    for f in fs {
        let shapes = &prev.ret_shapes[f];
        let owners: Vec<Option<String>> = shapes.iter().map(|(s, ..)| owner(s)).collect();
        if let Some(Some(t)) = owners.first().filter(|_| is_helper(f)) {
            if owners.iter().all(|o| o.as_deref() == Some(t.as_str())) {
                let id = name(&mut used, format!("{t}_into_val"));
                renames.insert(f.clone(), (id, format!("/// The `#[contracttype]` derive `<{t} as IntoVal<Env, Val>>::into_val`.\n")));
            }
        }
    }
    let mut fs: Vec<&String> = prev.unpacks.keys().collect();
    fs.sort();
    for f in fs {
        let types = &prev.unpacks[f];
        if let Some(t) = types.first().filter(|_| is_helper(f) && !renames.contains_key(f)) {
            if types.iter().all(|x| x == t) {
                let id = name(&mut used, format!("{t}_try_from_val"));
                renames.insert(f.clone(), (id, format!("/// The `#[contracttype]` derive `<{t} as TryFromVal<Env, Val>>::try_from_val`.\n")));
            }
        }
    }
    prev.renames = renames;
    prev.diverges = bodies
        .iter()
        .filter(|b| !b.basic_blocks.iter().any(|bb| matches!(bb.terminator().kind, TerminatorKind::Return)))
        .map(|b| tcx.item_name(b.source.def_id()).to_string())
        .collect();
    Ok(prev)
}

pub fn emit<'tcx>(tcx: TyCtxt<'tcx>, env: &Env<'tcx>, header: &str, bodies: &[&Body<'tcx>], spec: &Spec) -> R<String> {
    let prev = summaries(tcx, env, bodies, spec)?;
    let inter = RefCell::new(Inter::default());
    let mut fns = String::new();
    for body in bodies {
        fns.push('\n');
        fns.push_str(&Fn_::new(tcx, env, body, spec, &prev, &inter, true).emit()?);
    }
    // The storage schema: every key the contract hands the host, by
    // durability, with the operations and functions that use it. The uses
    // give the roles and the bare keys; the spec gave the names.
    let mut out = String::from(header);
    let schema = std::mem::take(&mut inter.borrow_mut().schema);
    if !schema.is_empty() {
        let mut groups: Vec<((String, String), Vec<String>)> = Vec::new();
        for (dur, key, op, f) in schema {
            let use_ = format!("{op}: {f}");
            match groups.iter_mut().find(|(k, _)| *k == (dur.clone(), key.clone())) {
                Some((_, uses)) => {
                    if !uses.contains(&use_) {
                        uses.push(use_);
                    }
                }
                None => groups.push(((dur, key), vec![use_])),
            }
        }
        groups.sort();
        out.push_str("\n// storage, from every put/get/has/del/extend_ttl call: durability, key, uses.\n");
        for ((dur, key), uses) in groups {
            let _ = writeln!(out, "//   {dur:<11} {key}   [{}]", uses.join(", "));
        }
    }
    out.push_str(&fns);
    Ok(out)
}

/// The contract as soroban-sdk source: its types from the spec, its exports
/// from the shapes. An export the source level cannot say is a `todo!()`
/// that names the first thing it could not.
pub fn emit_contract<'tcx>(tcx: TyCtxt<'tcx>, env: &Env<'tcx>, bodies: &[&Body<'tcx>], spec: &Spec, lines: &[String], partial: bool, complete: bool, head: &str) -> R<String> {
    let prev = summaries(tcx, env, bodies, spec)?;
    let inter = RefCell::new(Inter::default());
    let mut out = String::from(CONTRACT_HEAD);
    // The third-party crates the binary linked, inferred from the demangled
    // names it kept: everything that is not the SDK, the Rust runtime, or the
    // contract's own code. These are `Cargo.toml` dependencies to add.
    let runtime = ["core", "alloc", "std", "compiler_builtins", "soroban_sdk", "soroban_env_common", "soroban_env_guest", "soroban_env_host"];
    let prim = ["str", "bool", "char", "u8", "u16", "u32", "u64", "u128", "usize", "i8", "i16", "i32", "i64", "i128", "isize", "f32", "f64"];
    // The crate root of a demangled path: the first segment, only when the
    // path is `crate::...` and the root is a plain crate identifier -- not a
    // primitive (`<str as ...>`), a bare lang item (`rust_begin_unwind`), or
    // the runtime.
    let mut deps: Vec<String> = spec
        .sdk
        .values()
        .filter(|p| p.contains("::"))
        .filter_map(|p| p.trim_start_matches(['<', '&', ' ']).split("::").next())
        .filter(|c| !c.is_empty() && c.chars().all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_') && !c.starts_with("__") && !runtime.contains(c) && !prim.contains(c))
        .map(str::to_string)
        .collect();
    deps.sort();
    deps.dedup();
    if !deps.is_empty() {
        out.push_str(&format!("// Inferred dependencies (add to Cargo.toml): {}.
", deps.join(", ")));
        out.push_str("// These crates ran in the binary; the exports below call into them.

");
    }
    for l in lines {
        out.push_str(&type_item(l));
    }
    // A spec function may name a UDT the spec never defines (a private
    // migration/config type). Alias each undefined type to `Val` so the
    // reconstruction still compiles; the reader sees it was not in the spec.
    let mut defined: std::collections::HashSet<String> = lines.iter().filter_map(|l| l.split_whitespace().nth(1).map(|n| n.split(['{', '(']).next().unwrap_or(n).to_string())).collect();
    let builtin = ["Val", "Env", "Address", "MuxedAddress", "Bytes", "BytesN", "String", "Symbol", "Vec", "Map", "Result", "Option", "Timepoint", "Duration", "I256", "U256", "bool", "u32", "i32", "u64", "i64", "u128", "i128", "u256", "i256"];
    let mut aliases: Vec<String> = Vec::new();
    for sig in spec.sigs.values() {
        let ret_params = sig.splitn(2, '(').nth(1).unwrap_or("");
        let mut word = String::new();
        for c in ret_params.chars().chain(std::iter::once(' ')) {
            if c.is_alphanumeric() || c == '_' {
                word.push(c);
            } else {
                if word.chars().next().is_some_and(|f| f.is_ascii_uppercase() || f == '_') && !builtin.contains(&word.as_str()) && !defined.contains(&word) && !aliases.contains(&word) {
                    aliases.push(word.clone());
                }
                word.clear();
            }
        }
    }
    // A referenced-but-undefined type whose value the code requires to be
    // Void carries no data: it is `()`. Others get `Val` (safe for any shape).
    let mut unit: std::collections::HashSet<String> = std::collections::HashSet::new();
    for body in bodies {
        let n = tcx.item_name(body.source.def_id()).to_string();
        let Some(ptys) = spec.params.get(&n) else { continue };
        let f = Fn_::new(tcx, env, body, spec, &prev, &inter, true);
        for (i, ty) in ptys.iter().enumerate() {
            if aliases.contains(ty) && f.param_is_void(i) {
                unit.insert(ty.clone());
            }
        }
    }
    for a in &aliases {
        defined.insert(a.clone());
        if unit.contains(a) {
            out.push_str(&format!("type {a} = (); // not in the spec; the code requires it to be Void (carries no data)\n"));
        } else {
            out.push_str(&format!("type {a} = Val; // not in the spec; referenced by a signature\n"));
        }
    }
    if !aliases.is_empty() {
        out.push('\n');
    }
    out.push_str("#[contract]\npub struct Contract;\n\n#[contractimpl]\nimpl Contract {\n");
    let mut need_raw = false;
    for body in bodies {
        let def_id = body.source.def_id();
        let name = tcx.item_name(def_id).to_string();
        if !tcx.visibility(def_id).is_public() || name == "_" {
            continue;
        }
        let Some(sig) = spec.sigs.get(&name).cloned() else {
            out.push_str(&format!("    // {name}: exported, not in the spec.\n\n"));
            continue;
        };
        let emitted = Fn_::new(tcx, env, body, spec, &prev, &inter, true).emit_sdk();
        match emitted {
            // Fully reconstructed, or the marked partial view was asked for: as is.
            Ok(s) if partial || !s.contains("not reconstructed") => out.push_str(&s),
            // Otherwise an SDK-typed entry point that forwards to the complete
            // faithful reconstruction in `mod raw` below. No idiomatic form
            // exists for the library (rlp/bytes) or frame-ABI helpers it calls,
            // but the full logic is there and it compiles. Blocker named.
            Ok(s) => {
                let why = s.lines().find_map(|l| l.split("not reconstructed: ").nth(1)).unwrap_or("").trim_end_matches(&[';'][..]);
                if complete {
                    out.push_str(&format!("    // not idiomatic ({why}); full logic in `raw::{name}`.\n{}", raw_wrapper(&sig, &name)?));
                    need_raw = true;
                } else {
                    out.push_str(&format!("    {}\n        // not reconstructed: {why}\n        todo!()\n    }}\n", sdk_header(&sig)?));
                }
            }
            Err(why) => {
                if complete {
                    out.push_str(&format!("    // not idiomatic ({why}); full logic in `raw::{name}`.\n{}", raw_wrapper(&sig, &name)?));
                    need_raw = true;
                } else {
                    out.push_str(&format!("    {}\n        // not reconstructed: {why}\n        todo!()\n    }}\n", sdk_header(&sig)?));
                }
            }
        }
        out.push('\n');
    }
    let mut trimmed = out.trim_end().to_string();
    trimmed.push_str("\n}\n");
    if need_raw {
        let raw = emit(tcx, env, head, bodies, spec)?;
        let raw: String = raw.lines().filter(|l| !l.trim_start().starts_with("#![no_std")).map(|l| format!("    {l}\n")).collect();
        trimmed.push_str(&format!("\n#[allow(warnings)]\nmod raw {{\n{raw}}}\n"));
    }
    Ok(trimmed)
}

/// An SDK-typed entry point that forwards to `raw::name`: each argument is
/// re-encoded to the raw `Val`, the result decoded back to the spec type.
fn raw_wrapper(sig: &str, name: &str) -> R<String> {
    let rest = sig.strip_prefix("fn ").unwrap_or(sig);
    let (name_params, ret) = rest.split_once(" -> ").map(|(a, b)| (a, b.trim())).unwrap_or((rest, "()"));
    let params = name_params.split_once('(').map(|(_, p)| p.trim_end_matches(')')).unwrap_or("");
    let names: Vec<String> = if params.is_empty() {
        vec![]
    } else {
        split_top(params, ',').iter().map(|p| p.trim().split_once(": ").map(|(n, _)| n.trim().to_string()).unwrap_or_else(|| p.trim().to_string())).collect()
    };
    let hdr = sdk_header(sig)?;
    let args: Vec<String> = names.iter().map(|n| format!("raw::Val(IntoVal::<_, Val>::into_val(&{n}, &env).get_payload())")).collect();
    let call = format!("raw::{name}({})", args.join(", "));
    let body = if ret == "()" || ret.is_empty() {
        format!("        {call};")
    } else {
        format!("        <{ret} as TryFromVal<Env, Val>>::try_from_val(&env, &Val::from_payload({call}.0)).unwrap()")
    };
    Ok(format!("    {hdr}\n{body}\n    }}\n"))
}

struct Fn_<'a, 'tcx> {
    tcx: TyCtxt<'tcx>,
    env: &'a Env<'tcx>,
    body: &'a Body<'tcx>,
    spec: &'a Spec,
    fname: String,
    names: HashMap<Local, String>,
    payloads: HashSet<Local>,
    rpo: HashMap<BasicBlock, usize>,
    defs: HashMap<Local, usize>,
    uses: HashMap<Local, usize>,
    /// The one rvalue assigned to a local that is assigned exactly once.
    single_def: HashMap<Local, Rvalue<'tcx>>,
    /// Frame arrays whose address goes to the host as a position it reads
    /// Vals from (`vec_new_from_linear_memory`, the values of `map_new_..`),
    /// with their length: their slots hold Vals.
    val_arrays: HashMap<Local, u64>,
    /// Val arrays written whole, once, right before the one call that takes
    /// them: written as an array literal at that call instead.
    literal: HashSet<Local>,
    /// The address plumbing of literal arrays (`&raw mut`, casts, the packed
    /// position): every use of it is the consuming call, so it is not written.
    addr_locals: HashSet<Local>,
    /// The literal's elements as they are collected: expression, and the
    /// local it came from when it was a plain copy.
    array_lits: HashMap<Local, Vec<Option<(String, Option<Local>)>>>,
    /// Call results: callee and arguments, by destination local.
    call_def: HashMap<Local, (String, Vec<Operand<'tcx>>)>,
    /// What a vec or map built from linear memory is, once its call has been
    /// written: `DataKey::Pair(pair_key)`, `PairKey { a: .., b: .. }`. Every
    /// shape a local takes, each with the switch arms it was made under.
    shapes: HashMap<Local, Vec<(Vec<Cond>, String)>>,
    /// The block being emitted, for those arms.
    cur_bb: BasicBlock,
    /// Source level: SDK calls and spec types, no Vals.
    sdk: bool,
    /// Locals bound by name in SDK output; results inlined at their one use.
    declared: HashSet<Local>,
    inlined: HashMap<Local, String>,
    /// Locals whose value flows to the return unchanged; whether `_0` is
    /// always assigned right before a `return`.
    ret_locals: HashSet<Local>,
    ret_inline: bool,
    ret_expr: Option<String>,
    /// The previous pass's summaries, read; this pass's, written.
    prev: &'a Inter,
    inter: &'a RefCell<Inter>,
    /// The last pass, whose summaries are complete.
    final_pass: bool,
    /// Single-use temporaries written into their one use instead of on a
    /// line of their own: the expression, and the rvalue it came from so a
    /// consumer can still see its shape.
    folded: HashMap<Local, (String, Rvalue<'tcx>)>,
    /// The frame words at each block's entry, once computed.
    words_memo: RefCell<HashMap<(Local, BasicBlock, bool), frames::Words>>,
    derived_memo: RefCell<HashMap<Local, std::rc::Rc<HashSet<Local>>>>,
    conds_memo: RefCell<HashMap<BasicBlock, Vec<Cond>>>,
    phi_memo: RefCell<HashMap<Local, Option<(Local, u64)>>>,
    dead_mentions: RefCell<Option<HashMap<Local, usize>>>,
    may_derive_memo: RefCell<HashMap<Local, HashSet<Local>>>,
    merges_memo: RefCell<HashMap<BasicBlock, Vec<BasicBlock>>>,
    decodes: HashMap<BasicBlock, decode::Decode>,
    /// Output lines with their nesting depth; indentation is applied at the end.
    out: Vec<(usize, String)>,
    depth: usize,
    /// Labels whose region is being emitted. A jump to a label not here means
    /// the CFG is not reducible; the function then falls back.
    open: Vec<BasicBlock>,
    /// Labels some `break`/`continue` names; the others are not written.
    used: HashSet<BasicBlock>,
}

impl<'a, 'tcx> Fn_<'a, 'tcx> {
    fn new(tcx: TyCtxt<'tcx>, env: &'a Env<'tcx>, body: &'a Body<'tcx>, spec: &'a Spec, prev: &'a Inter, inter: &'a RefCell<Inter>, final_pass: bool) -> Self {
        let fname = tcx.item_name(body.source.def_id()).to_string();
        let mut names = HashMap::new();
        // A local must not shadow a function or static it might share a name
        // with: LLVM named the result of put_contract_data after its callee.
        let mut used: HashSet<String> = env.fns.keys().chain(env.statics.keys()).cloned().collect();
        used.extend(["Val", "StorageType", "trap", "unknown", "unknown_i64"].iter().map(|s| s.to_string()));
        for d in &body.var_debug_info {
            if let VarDebugInfoContents::Place(p) = d.value {
                if !p.projection.is_empty() || names.contains_key(&p.local) {
                    continue;
                }
                // An LLVM name (`cmp2.not`) as a Rust identifier, unique here.
                let mut n = crate::rs_name(&d.name.to_string().replace('.', "_"));
                if !used.insert(n.clone()) {
                    n = format!("{n}_{}", p.local.as_usize());
                    used.insert(n.clone());
                }
                names.insert(p.local, n);
            }
        }
        let rpo = body.basic_blocks.reverse_postorder().iter().enumerate().map(|(n, b)| (*b, n)).collect();
        let payloads = val_payload_locals(body, env.val_def);
        let (defs, uses) = def_use_counts(body);
        let single_def = body
            .basic_blocks
            .iter()
            .flat_map(|b| &b.statements)
            .filter_map(|st| match &st.kind {
                StatementKind::Assign(a) => a.0.as_local().filter(|l| defs.get(l) == Some(&1)).map(|l| (l, a.1.clone())),
                _ => None,
            })
            .collect();
        let call_def = body
            .basic_blocks
            .iter()
            .filter_map(|b| match &b.terminator {
                Some(Terminator { kind: TerminatorKind::Call { func, args, destination, .. }, .. }) => {
                    let Operand::Constant(c) = func else { return None };
                    let ty::FnDef(d, _) = c.const_.ty().kind() else { return None };
                    Some((destination.as_local()?, (tcx.item_name(*d).to_string(), args.iter().map(|a| a.node.clone()).collect())))
                }
                _ => None,
            })
            .collect();
        let mut me = Fn_ {
            tcx,
            env,
            body,
            spec,
            fname,
            names,
            payloads,
            rpo,
            defs,
            uses,
            single_def,
            val_arrays: HashMap::new(),
            literal: HashSet::new(),
            addr_locals: HashSet::new(),
            array_lits: HashMap::new(),
            call_def,
            shapes: HashMap::new(),
            cur_bb: START_BLOCK,
            sdk: false,
            declared: HashSet::new(),
            inlined: HashMap::new(),
            ret_locals: HashSet::new(),
            ret_inline: false,
            ret_expr: None,
            prev,
            inter,
            final_pass,
            folded: HashMap::new(),
            words_memo: RefCell::new(HashMap::new()),
            derived_memo: RefCell::new(HashMap::new()),
            conds_memo: RefCell::new(HashMap::new()),
            phi_memo: RefCell::new(HashMap::new()),
            dead_mentions: RefCell::new(None),
            may_derive_memo: RefCell::new(HashMap::new()),
            merges_memo: RefCell::new(HashMap::new()),
            decodes: HashMap::new(),
            out: Vec::new(),
            depth: 0,
            open: Vec::new(),
            used: HashSet::new(),
        };
        me.val_arrays = me.find_val_arrays();
        me.name_fields();
        // A decoded number's words are `lo(x)` and `hi(x)` of the Val it came from.
        me.decodes = me.find_decodes();
        for d in me.decodes.clone().values() {
            let x = match me.call_def.get(&d.val) {
                Some((callee, args)) if args.is_empty() => format!("{callee}()"),
                _ => me.local(d.val),
            };
            for (l, part) in &d.parts {
                let sh = match part {
                    decode::Part::Lo => format!("lo({x})"),
                    decode::Part::Hi => format!("hi({x})"),
                    decode::Part::Whole => x.clone(),
                };
                me.push_shape_under(*l, sh, vec![]);
            }
        }
        let (literal, addr_locals) = me.find_literal_arrays();
        me.literal = literal;
        me.addr_locals = addr_locals;
        me
    }
}
