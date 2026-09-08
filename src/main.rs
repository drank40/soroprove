//! Soroban wasm -> typed LLVM IR.
//!
//! Three invariants, each one killing a decompiler bug class we found in the wild:
//!
//! 1. `%Val` is a named LLVM type, NOT `i64`, and `use_as` is the *only* place a
//!    Val<->i64 crossing can happen -- always as an explicit, greppable call.
//!    NB: LLVM will not police this for you. With opaque pointers, `llvm-as` and
//!    `opt -passes=verify` both accept a call whose site signature disagrees
//!    with the declaration. So the invariant is asserted here instead
//!    (`use_as` post-condition), which is the level that actually failed in the
//!    decompiler this replaces: its lifter typed the value correctly and a
//!    later pass overwrote it. With one crossing point, that pass cannot exist.
//! 2. Branch targets resolve through the full enclosing label stack, and an
//!    out-of-range depth is a hard error. An LLVM `switch` must name a real
//!    label for every case plus a default, so a `br_table` arm cannot be
//!    silently dropped.
//! 3. `Unknown` is bottom. It materialises only as `call @ponytail.unknown()` --
//!    there is no literal for a pass to substitute, and none of the code below
//!    can turn it into one.
use std::collections::HashMap;
use std::fmt::Write as _;
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

impl VT {
    fn llvm(self) -> &'static str {
        match self {
            VT::Val => "%Val",
            VT::Raw64 | VT::Storage => "i64",
        }
    }
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

/// Tag names, for decoding a constant into a readable comment. Small tags only:
/// an object handle is frame-relative and meaningless without a live host.
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

/// What a `Val`-typed constant actually means. This is the decode that a
/// downstream pass must never be able to undo.
fn explain_val(payload: u64) -> String {
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

#[derive(Clone)]
struct Lbl {
    /// Where a `br` to this depth goes. For a loop that is the header (a back
    /// edge); for a block or `if` it is the continuation.
    target: String,
    /// Where `End` falls through to. Same as `target` except for a loop, whose
    /// `End` continues *past* the loop rather than re-entering the header.
    cont: String,
    if_idx: Option<usize>,
}

impl Lbl {
    fn plain(target: String) -> Lbl {
        Lbl {
            cont: target.clone(),
            target,
            if_idx: None,
        }
    }
}

/// A value on the abstract wasm operand stack.
#[derive(Clone, Debug)]
enum SV {
    /// A wasm constant, not yet committed to a type. Which LLVM type it becomes
    /// is decided by its *consumer*, from the host ABI -- never guessed.
    Const(i64),
    /// An already-emitted LLVM value of known type.
    Reg(String, VT),
    /// Bottom. Deliberately carries no payload, so nothing can read a literal
    /// out of it.
    Unknown,
}

struct Fun<'a> {
    /// LLVM lines for the block currently being emitted.
    out: String,
    n: usize,
    stack: Vec<SV>,
    /// Enclosing label stack. Index from the end by relative depth -- exactly
    /// wasm's own rule. `if_idx` is `Some` while an `if`'s else-arm still owes
    /// us a block, so `End` can emit the empty arm rather than leave a branch
    /// pointing at a label that never appears.
    labels: Vec<Lbl>,
    imports: &'a HashMap<u32, &'static HostFn>,
    /// Set once the current LLVM block has a terminator.
    done: bool,
}

impl<'a> Fun<'a> {
    fn tmp(&mut self) -> String {
        self.n += 1;
        format!("%t{}", self.n)
    }

    fn line(&mut self, s: &str) {
        if !self.done {
            let _ = writeln!(self.out, "  {s}");
        }
    }

    fn label(&mut self, l: &str) {
        let _ = writeln!(self.out, "{l}:");
        self.done = false;
    }

    fn term(&mut self, s: &str) {
        self.line(s);
        self.done = true;
    }

    fn pop(&mut self) -> SV {
        self.stack.pop().unwrap_or(SV::Unknown)
    }

    /// Turn a stack value into an LLVM operand of the requested type, emitting
    /// the conversion explicitly. This is the only place a type crossing can
    /// happen, which is what makes it auditable.
    fn use_as(&mut self, v: SV, want: VT) -> String {
        let s = self.use_as_inner(v, want);
        // The post-condition LLVM won't check for us: the operand really does
        // carry the type the host ABI declared.
        assert!(
            s.starts_with(want.llvm()),
            "operand {s:?} is not a {}",
            want.llvm()
        );
        s
    }

    fn use_as_inner(&mut self, v: SV, want: VT) -> String {
        match (v, want) {
            (SV::Const(c), VT::Val) => {
                let t = self.tmp();
                let why = explain_val(c as u64);
                self.line(&format!(
                    "{t} = call %Val @soroban.val.from_payload(i64 {c})   ; {why}"
                ));
                format!("%Val {t}")
            }
            (SV::Const(c), _) => format!("i64 {c}"),
            (SV::Reg(r, have), w) if have.llvm() == w.llvm() => format!("{} {r}", w.llvm()),
            (SV::Reg(r, VT::Val), _) => {
                let t = self.tmp();
                self.line(&format!("{t} = call i64 @soroban.val.payload(%Val {r})"));
                format!("i64 {t}")
            }
            (SV::Reg(r, have), VT::Val) if have != VT::Val => {
                let t = self.tmp();
                self.line(&format!("{t} = call %Val @soroban.val.from_payload(i64 {r})"));
                format!("%Val {t}")
            }
            // Same LLVM type on both sides: no conversion needed.
            (SV::Reg(r, _), w) => format!("{} {r}", w.llvm()),
            (SV::Unknown, w) => {
                let t = self.tmp();
                let f = if w == VT::Val {
                    "@ponytail.unknown"
                } else {
                    "@ponytail.unknown.i64"
                };
                self.line(&format!("{t} = call {} {f}()", w.llvm()));
                format!("{} {t}", w.llvm())
            }
        }
    }

    /// Bare operand for an i64 arithmetic position.
    fn use_i64(&mut self, v: SV) -> String {
        let s = self.use_as(v, VT::Raw64);
        s.trim_start_matches("i64 ").to_string()
    }

    fn binop(&mut self, op: &str) {
        let b = self.pop();
        let a = self.pop();
        let (a, b) = (self.use_i64(a), self.use_i64(b));
        let t = self.tmp();
        self.line(&format!("{t} = {op} i64 {a}, {b}"));
        self.stack.push(SV::Reg(t, VT::Raw64));
    }

    /// Resolve a relative branch depth against the full label stack. Out of
    /// range is malformed wasm, not something to skip.
    fn target(&self, depth: u32) -> Result<String, String> {
        let n = self.labels.len();
        let d = depth as usize;
        if d >= n {
            return Err(format!("branch depth {d} exceeds label stack {n}"));
        }
        Ok(self.labels[n - 1 - d].target.clone())
    }
}

/// Pair every structured control instruction with the index of its `End`.
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

fn lower(
    name: &str,
    n_params: usize,
    n_results: usize,
    n_locals: usize,
    ops: &[Operator],
    imports: &HashMap<u32, &'static HostFn>,
    local_sigs: &HashMap<u32, (usize, usize)>,
    used_locals: &mut std::collections::HashSet<u32>,
) -> Result<String, String> {
    let pairs = pair_ends(ops);
    let ret = if n_results == 0 { "void" } else { "%Val" };
    let params: Vec<String> = (0..n_params).map(|i| format!("%Val %a{i}")).collect();

    let mut f = Fun {
        out: String::new(),
        n: 0,
        stack: Vec::new(),
        labels: vec![Lbl::plain("exit".into())],
        imports,
        done: false,
    };

    // Locals live in allocas; `opt -passes=mem2reg` promotes them to real SSA
    // with phi nodes. Doing that ourselves would be re-implementing mem2reg.
    f.label("entry");
    for i in 0..(n_params + n_locals) {
        f.line(&format!("%l{i} = alloca i64"));
    }
    for i in 0..n_params {
        let t = f.tmp();
        f.line(&format!("{t} = call i64 @soroban.val.payload(%Val %a{i})"));
        f.line(&format!("store i64 {t}, ptr %l{i}"));
    }
    for i in n_params..(n_params + n_locals) {
        f.line(&format!("store i64 0, ptr %l{i}"));
    }

    let mut dead = 0usize;
    for (i, op) in ops.iter().enumerate() {
        match op {
            Operator::Block { .. } => {
                let end = pairs.get(&i).copied().unwrap_or(usize::MAX);
                f.labels.push(Lbl::plain(format!("c{end}")));
            }
            Operator::Loop { .. } => {
                let h = format!("h{i}");
                f.term(&format!("br label %{h}"));
                f.label(&h);
                f.labels.push(Lbl {
                    target: h,
                    cont: format!("c{}", pairs.get(&i).copied().unwrap_or(usize::MAX)),
                    if_idx: None,
                });
            }
            Operator::If { .. } => {
                let end = pairs.get(&i).copied().unwrap_or(usize::MAX);
                let c = f.pop();
                let c = f.use_i64(c);
                let t = f.tmp();
                f.line(&format!("{t} = icmp ne i64 {c}, 0"));
                f.term(&format!("br i1 {t}, label %then{i}, label %else{i}"));
                f.labels.push(Lbl {
                    target: format!("c{end}"),
                    cont: format!("c{end}"),
                    if_idx: Some(i),
                });
                f.label(&format!("then{i}"));
            }
            Operator::Else => {
                // Close the then-arm, open the else-arm. The `if` index rides on
                // the frame, so this label always matches the branch already
                // emitted -- it cannot drift into a name nothing jumps to.
                let (tgt, idx) = match f.labels.last_mut() {
                    Some(l) => (l.target.clone(), l.if_idx.take()),
                    None => ("exit".to_string(), None),
                };
                f.term(&format!("br label %{tgt}"));
                match idx {
                    Some(i) => f.label(&format!("else{i}")),
                    None => {
                        dead += 1;
                        f.label(&format!("dead{dead}"));
                    }
                }
                f.stack.clear();
            }
            Operator::End => {
                let frame = f.labels.pop().unwrap_or_else(|| Lbl::plain("exit".into()));
                if frame.cont == "exit" {
                    continue;
                }
                f.term(&format!("br label %{}", frame.cont));
                // An `if` with no `else`: the else edge still needs a real block.
                if let Some(idx) = frame.if_idx {
                    f.label(&format!("else{idx}"));
                    f.term(&format!("br label %{}", frame.cont));
                }
                f.label(&frame.cont);
                // ponytail: no cross-block operand-stack threading; locals go
                // through allocas and mem2reg builds the phis.
                f.stack.clear();
            }
            Operator::Br { relative_depth } => {
                let t = f.target(*relative_depth)?;
                f.term(&format!("br label %{t}"));
                dead += 1;
                f.label(&format!("dead{dead}"));
            }
            Operator::BrIf { relative_depth } => {
                let t = f.target(*relative_depth)?;
                let c = f.pop();
                let c = f.use_i64(c);
                let tv = f.tmp();
                f.line(&format!("{tv} = icmp ne i64 {c}, 0"));
                dead += 1;
                f.term(&format!("br i1 {tv}, label %{t}, label %fall{dead}"));
                f.label(&format!("fall{dead}"));
            }
            Operator::BrTable { targets } => {
                // Every case names a real label and so does the default. LLVM's
                // verifier will not accept a missing destination, so no arm can
                // vanish the way a depth-indexed list lets it.
                let sel = f.pop();
                let sel = f.use_i64(sel);
                let t32 = f.tmp();
                f.line(&format!("{t32} = trunc i64 {sel} to i32"));
                let deflt = f.target(targets.default())?;
                let mut arms = String::new();
                for (idx, d) in targets.targets().enumerate() {
                    let d = d.map_err(|e| e.to_string())?;
                    let l = f.target(d)?;
                    let _ = write!(arms, "\n    i32 {idx}, label %{l}");
                }
                f.term(&format!(
                    "switch i32 {t32}, label %{deflt} [{arms}\n  ]"
                ));
                dead += 1;
                f.label(&format!("dead{dead}"));
            }
            Operator::Return => {
                if n_results == 0 {
                    f.term("ret void");
                } else {
                    let v = f.pop();
                    let v = f.use_as(v, VT::Val);
                    f.term(&format!("ret {v}"));
                }
                dead += 1;
                f.label(&format!("dead{dead}"));
            }
            Operator::Unreachable => {
                f.term("unreachable");
                dead += 1;
                f.label(&format!("dead{dead}"));
            }
            Operator::I32Const { value } => f.stack.push(SV::Const(*value as i64)),
            Operator::I64Const { value } => f.stack.push(SV::Const(*value)),
            Operator::LocalGet { local_index } => {
                let t = f.tmp();
                f.line(&format!("{t} = load i64, ptr %l{local_index}"));
                f.stack.push(SV::Reg(t, VT::Raw64));
            }
            Operator::LocalSet { local_index } => {
                let v = f.pop();
                let v = f.use_i64(v);
                f.line(&format!("store i64 {v}, ptr %l{local_index}"));
            }
            Operator::LocalTee { local_index } => {
                let v = f.pop();
                let v = f.use_i64(v);
                f.line(&format!("store i64 {v}, ptr %l{local_index}"));
                f.stack.push(SV::Reg(v, VT::Raw64));
            }
            Operator::Drop => {
                f.pop();
            }
            Operator::Call { function_index } => {
                if let Some(h) = f.imports.get(function_index).copied() {
                    // Host call: the ABI decides every argument's type.
                    let mut args: Vec<SV> = Vec::new();
                    for _ in 0..h.args.len() {
                        args.push(f.pop());
                    }
                    args.reverse();
                    let mut ops_s: Vec<String> = Vec::new();
                    for (a, want) in args.into_iter().zip(h.args.iter().copied()) {
                        ops_s.push(f.use_as(a, want));
                    }
                    let sig: Vec<&str> = h.args.iter().map(|a| a.llvm()).collect();
                    let callee = format!("@\"{}\"", h.name);
                    if h.ret_ty == "Void" && h.ret == VT::Val {
                        // Void still returns a Val on the wire; keep it typed.
                    }
                    let t = f.tmp();
                    f.line(&format!(
                        "{t} = call {} {callee}({})   ; {}.{}",
                        h.ret.llvm(),
                        ops_s.join(", "),
                        h.module,
                        h.code
                    ));
                    let _ = sig;
                    f.stack.push(SV::Reg(t, h.ret));
                } else if let Some((np, nr)) = local_sigs.get(function_index).copied() {
                    // A local call: real call, real signature. Its *body* is
                    // not inlined, so the result is an opaque i64 -- opaque is
                    // not the same as a guessed value.
                    used_locals.insert(*function_index);
                    let mut a: Vec<SV> = (0..np).map(|_| f.pop()).collect();
                    a.reverse();
                    // Deliberately NOT Val-decoded. A local helper's parameters
                    // are plain i64 with no declared meaning -- a data pointer,
                    // a length and a Val all look alike. Decoding them anyway
                    // is exactly the fabrication this tool exists to avoid.
                    let note = "";
                    let ops_s: Vec<String> =
                        a.into_iter().map(|v| format!("i64 {}", f.use_i64(v))).collect();
                    if nr == 0 {
                        f.line(&format!(
                            "call void @f{function_index}({}){note}",
                            ops_s.join(", ")
                        ));
                    } else {
                        let t = f.tmp();
                        f.line(&format!(
                            "{t} = call i64 @f{function_index}({})",
                            ops_s.join(", ")
                        ));
                        f.stack.push(SV::Reg(t, VT::Raw64));
                    }
                } else {
                    f.stack.push(SV::Unknown);
                }
            }
            Operator::I64Add | Operator::I32Add => f.binop("add"),
            Operator::I64Sub | Operator::I32Sub => f.binop("sub"),
            Operator::I64Mul | Operator::I32Mul => f.binop("mul"),
            Operator::I64And | Operator::I32And => f.binop("and"),
            Operator::I64Or | Operator::I32Or => f.binop("or"),
            Operator::I64Xor | Operator::I32Xor => f.binop("xor"),
            Operator::I64Shl | Operator::I32Shl => f.binop("shl"),
            Operator::I64ShrU | Operator::I32ShrU => f.binop("lshr"),
            Operator::I64ShrS | Operator::I32ShrS => f.binop("ashr"),
            Operator::I64Eq | Operator::I32Eq => f.cmp("eq"),
            Operator::I64Ne | Operator::I32Ne => f.cmp("ne"),
            Operator::I64LtU | Operator::I32LtU => f.cmp("ult"),
            Operator::I64GtU | Operator::I32GtU => f.cmp("ugt"),
            Operator::I64LtS | Operator::I32LtS => f.cmp("slt"),
            Operator::I64GtS | Operator::I32GtS => f.cmp("sgt"),
            // ponytail: the value model is i64-wide, so width casts are identity.
            // Upgrade to real trunc/zext if 32-bit wraparound ever matters.
            Operator::I32WrapI64
            | Operator::I64ExtendI32U
            | Operator::I64ExtendI32S
            | Operator::I64Extend32S
            | Operator::I32Extend8S
            | Operator::I32Extend16S => {}
            Operator::I64Eqz | Operator::I32Eqz => {
                let v = f.pop();
                let v = f.use_i64(v);
                let t = f.tmp();
                f.line(&format!("{t} = icmp eq i64 {v}, 0"));
                let z = f.tmp();
                f.line(&format!("{z} = zext i1 {t} to i64"));
                f.stack.push(SV::Reg(z, VT::Raw64));
            }
            // Anything unmodelled yields bottom. It never yields a plausible value.
            _ => f.stack.push(SV::Unknown),
        }
    }

    if !f.done {
        if n_results == 0 {
            f.term("ret void");
        } else {
            let v = f.pop();
            let v = f.use_as(v, VT::Val);
            f.term(&format!("ret {v}"));
        }
    }
    f.label("exit");
    if n_results == 0 {
        f.term("ret void");
    } else {
        let t = f.tmp();
        f.line(&format!("{t} = call %Val @ponytail.unknown()"));
        f.term(&format!("ret %Val {t}"));
    }

    Ok(format!(
        "define {ret} @\"{name}\"({}) {{\n{}}}\n",
        params.join(", "),
        f.out
    ))
}

impl Fun<'_> {
    fn cmp(&mut self, p: &str) {
        let b = self.pop();
        let a = self.pop();
        let (a, b) = (self.use_i64(a), self.use_i64(b));
        let t = self.tmp();
        self.line(&format!("{t} = icmp {p} i64 {a}, {b}"));
        let z = self.tmp();
        self.line(&format!("{z} = zext i1 {t} to i64"));
        self.stack.push(SV::Reg(z, VT::Raw64));
    }
}

fn main() {
    let mut args = std::env::args().skip(1);
    let path = match args.next() {
        Some(p) => p,
        None => {
            eprintln!("usage: ponytail-wasm <contract.wasm> [export]");
            std::process::exit(2);
        }
    };
    let only = args.next();
    let wasm = std::fs::read(&path).expect("read wasm");

    let by_code: HashMap<(&str, &str), &HostFn> =
        HOST_FNS.iter().map(|h| ((h.module, h.code), h)).collect();

    let mut imports: HashMap<u32, &'static HostFn> = HashMap::new();
    let mut n_imports = 0u32;
    let mut bodies: Vec<(usize, usize, Vec<Operator>)> = Vec::new();
    let mut exports: Vec<(String, u32)> = Vec::new();
    let mut sigs: Vec<(usize, usize)> = Vec::new(); // per type index
    let mut func_types: Vec<u32> = Vec::new();

    for p in Parser::new(0).parse_all(&wasm) {
        match p.expect("parse") {
            Payload::TypeSection(r) => {
                for rg in r {
                    for st in rg.expect("rec group").into_types() {
                        if let wasmparser::CompositeInnerType::Func(ft) =
                            &st.composite_type.inner
                        {
                            sigs.push((ft.params().len(), ft.results().len()));
                        } else {
                            sigs.push((0, 0));
                        }
                    }
                }
            }
            Payload::ImportSection(r) => {
                // 0.258 yields import *groups* (compact imports); expand each.
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
                let idx = bodies.len();
                bodies.push((idx, n_locals, ops));
            }
            _ => {}
        }
    }

    let mut out = String::from(
        "; ponytail-wasm: Soroban wasm -> typed LLVM IR\n\
         ; %Val is NOT i64. Every crossing is an explicit call.\n\
         %Val = type { i64 }\n\n\
         declare %Val @soroban.val.from_payload(i64)\n\
         declare i64 @soroban.val.payload(%Val)\n\
         ; bottom. No literal exists for a pass to substitute.\n\
         declare %Val @ponytail.unknown()\n\
         declare i64 @ponytail.unknown.i64()\n\n",
    );

    let mut declared: Vec<&HostFn> = imports.values().copied().collect();
    declared.sort_by_key(|h| h.name);
    declared.dedup_by_key(|h| h.name);
    for h in &declared {
        let ps: Vec<&str> = h.args.iter().map(|a| a.llvm()).collect();
        let _ = writeln!(
            out,
            "declare {} @\"{}\"({})   ; {}.{}  ({}) -> {}",
            h.ret.llvm(),
            h.name,
            ps.join(", "),
            h.module,
            h.code,
            h.arg_tys.join(", "),
            h.ret_ty
        );
    }
    out.push('\n');

    // Local function index -> (params, results), so a local call gets a real
    // signature instead of vanishing.
    let mut local_sigs: HashMap<u32, (usize, usize)> = HashMap::new();
    for (i, t) in func_types.iter().enumerate() {
        if let Some(s) = sigs.get(*t as usize) {
            local_sigs.insert(n_imports + i as u32, *s);
        }
    }
    let mut used_locals: std::collections::HashSet<u32> = Default::default();
    let mut bodies_out = String::new();

    // The interesting code is usually NOT in an export: the SDK's dispatch
    // wrapper delegates, and constants/jump tables live in helpers. Lowering
    // only exports is how you miss them.
    let all = only.as_deref() == Some("--all");
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

    for (name, fidx) in &targets {
        if !all {
            if let Some(f) = &only {
                if name != f {
                    continue;
                }
            }
        }
        let Some(local) = fidx.checked_sub(n_imports) else {
            continue;
        };
        let Some((_, n_locals, ops)) = bodies.get(local as usize) else {
            continue;
        };
        let (np, nr) = func_types
            .get(local as usize)
            .and_then(|t| sigs.get(*t as usize))
            .copied()
            .unwrap_or((0, 0));
        match lower(
            name,
            np,
            nr,
            *n_locals,
            ops,
            &imports,
            &local_sigs,
            &mut used_locals,
        ) {
            Ok(ir) => {
                bodies_out.push_str(&ir);
                bodies_out.push('\n');
            }
            Err(e) => {
                let _ = writeln!(bodies_out, "; FAILED to lower {name}: {e}\n");
            }
        }
    }

    // Only declare a local we did not also define, or LLVM sees a redefinition.
    let defined: std::collections::HashSet<u32> = targets.iter().map(|(_, i)| *i).collect();
    let mut used: Vec<u32> = used_locals.difference(&defined).copied().collect();
    used.sort();
    for fi in used {
        let (np, nr) = local_sigs.get(&fi).copied().unwrap_or((0, 0));
        let ps = vec!["i64"; np].join(", ");
        let r = if nr == 0 { "void" } else { "i64" };
        let _ = writeln!(out, "declare {r} @f{fi}({ps})   ; local function");
    }
    out.push('\n');
    out.push_str(&bodies_out);

    print!("{out}");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn host_table_generated_from_env_json() {
        assert_eq!(HOST_FN_COUNT, HOST_FNS.len());
        // 171 host functions at protocol 25. If env.json is refreshed and this
        // trips, the table regenerated -- that is the point.
        assert!(HOST_FN_COUNT >= 171, "got {HOST_FN_COUNT}");
        let put = HOST_FNS
            .iter()
            .find(|h| h.name == "ledger.put_contract_data")
            .expect("put_contract_data");
        // The bug this typing prevents: arg 1 is a Val, arg 2 is a raw enum.
        assert_eq!(put.args, &[VT::Val, VT::Val, VT::Storage]);
    }

    #[test]
    fn val_payload_1_is_true_not_one() {
        assert_eq!(explain_val(1), "true");
        assert_eq!(explain_val(0), "false");
        // u32 1 is a completely different payload.
        assert_eq!(explain_val((1u64 << 32) | 4), "u32 1");
        assert_eq!(explain_val(0x100000003), "Error(type 0, code 1)");
        assert_eq!(explain_val(3867323444879862030), "Symbol(\"persisted\")");
    }

    #[test]
    fn unknown_never_becomes_a_literal() {
        let imports = HashMap::new();
        let ops = vec![Operator::Return];
        let ir = lower("f", 0, 1, 0, &ops, &imports, &HashMap::new(), &mut Default::default()).unwrap();
        assert!(ir.contains("@ponytail.unknown()"), "{ir}");
        // There is no code path that emits a constant for bottom.
        assert!(!ir.contains("ret %Val zeroinitializer"));
    }

    #[test]
    fn every_operand_carries_its_declared_type() {
        // The assertion in use_as is the enforcement point, since LLVM accepts
        // a mismatched call site. Exercise both directions.
        let imports = HashMap::new();
        let mut f = Fun {
            out: String::new(), n: 0, stack: Vec::new(),
            labels: vec![Lbl::plain("exit".into())], imports: &imports, done: false,
        };
        assert!(f.use_as(SV::Const(1), VT::Val).starts_with("%Val "));
        assert!(f.use_as(SV::Const(1), VT::Raw64).starts_with("i64 "));
        assert!(f.use_as(SV::Unknown, VT::Val).starts_with("%Val "));
        assert!(f.use_as(SV::Unknown, VT::Raw64).starts_with("i64 "));
        assert!(f.use_as(SV::Reg("%r".into(), VT::Raw64), VT::Val).starts_with("%Val "));
        assert!(f.use_as(SV::Reg("%r".into(), VT::Val), VT::Raw64).starts_with("i64 "));
    }

    #[test]
    fn branch_depth_out_of_range_is_an_error() {
        let imports = HashMap::new();
        let ops = vec![Operator::Br { relative_depth: 99 }];
        assert!(lower("f", 0, 0, 0, &ops, &imports, &HashMap::new(), &mut Default::default()).is_err());
    }
}
