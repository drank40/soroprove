//! Parameter and return types of the lifted functions, inferred from the
//! binary, not guessed.
//!
//! Two sources, both exact. The wasm type section, which the LLVM stage
//! recorded on each parameter as `wasm.type`: on wasm32 a pointer is always
//! `i32` and a Val always `i64`, so an `i32` can be a pointer or an integer
//! and an `i64` a Val, a StorageType or an integer. And the uses: a value
//! turned into an address is a pointer, one wrapped as a Val is a Val, one
//! handed to a host function takes the ABI type of that position, and one
//! handed to another lifted function takes that function's parameter type,
//! solved to a fixpoint over the call graph. Where the evidence conflicts or
//! is absent, the wasm type stands as the plain integer it is.
//!
//! rustc then borrow-checks the MIR built with these types, so a wrong
//! inference is a compile error, never a silent one.
use std::collections::HashMap;

use inkwell::attributes::AttributeLoc;
use inkwell::module::Module;
use inkwell::values::{
    AnyValue, AnyValueEnum, AsValueRef, BasicValue, BasicValueEnum, CallSiteValue, FunctionValue, InstructionOpcode,
    InstructionValue, Operand,
};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum PTy {
    /// A plain integer, `u64` in the model (wasm `i32` values are zero-extended).
    Int,
    Ptr,
    Val,
    Storage,
}

#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
enum Slot {
    Param(usize, usize),
    Ret(usize),
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Ev {
    /// The use fixes the type.
    Is(PTy),
    /// The value is handed to another slot; that slot's type is this one's.
    Link(Slot),
    /// `x & 0xff == tag`: the SDK's `Val::get_tag`. Decides only when nothing
    /// stronger does.
    TagCheck,
    /// Multiplied, shifted, divided: an integer, unless something stronger
    /// says otherwise.
    IntOp,
    /// Added to a non-constant and then used as an address: a pointer or its
    /// index, undecidable from this alone.
    MaybePtr,
}

#[derive(Default)]
pub struct Sigs {
    index: HashMap<String, usize>,
    params: Vec<Vec<PTy>>,
    rets: Vec<Option<PTy>>,
}

impl Sigs {
    pub fn param(&self, f: &str, i: usize) -> Option<PTy> {
        self.index.get(f).and_then(|&k| self.params[k].get(i).copied())
    }
    pub fn ret(&self, f: &str) -> Option<PTy> {
        self.index.get(f).and_then(|&k| self.rets[k])
    }
}

fn user_inst(v: AnyValueEnum) -> Option<InstructionValue> {
    match v {
        AnyValueEnum::InstructionValue(i) => Some(i),
        other => BasicValueEnum::try_from(other).ok().and_then(|b| b.as_instruction_value()),
    }
}

fn operand_index(i: InstructionValue, v: BasicValueEnum) -> Option<u32> {
    (0..i.get_num_operands()).find(|k| match i.get_operand(*k) {
        Some(Operand::Value(x)) => x.as_value_ref() == v.as_value_ref(),
        _ => false,
    })
}

fn const_of(v: BasicValueEnum) -> Option<u64> {
    match v {
        BasicValueEnum::IntValue(i) if i.is_constant_int() => i.get_zero_extended_constant(),
        _ => None,
    }
}

fn callee_of(i: InstructionValue) -> Option<FunctionValue> {
    CallSiteValue::try_from(i).ok()?.get_called_fn_value()
}

/// The host function's declared types by position, from its `soroban.sig`.
fn host_positions(f: FunctionValue) -> Option<Vec<PTy>> {
    let a = f.get_string_attribute(AttributeLoc::Function, "soroban.sig")?;
    let s = a.get_string_value().to_string_lossy().into_owned();
    let inside = s.trim_start_matches('(').split(')').next().unwrap_or("").to_owned();
    Some(
        inside
            .split(',')
            .map(|p| match p.trim() {
                "StorageType" => PTy::Storage,
                "u64" | "i64" => PTy::Int,
                _ => PTy::Val,
            })
            .collect(),
    )
}

struct Infer<'ctx> {
    fns: Vec<FunctionValue<'ctx>>,
    index: HashMap<String, usize>,
    ev: HashMap<Slot, Vec<Ev>>,
}

impl<'ctx> Infer<'ctx> {
    fn push(&mut self, s: Slot, e: Ev) {
        self.ev.entry(s).or_default().push(e);
    }

    /// Evidence about `v`, a value in function `fk`, from every use of it.
    fn uses(&mut self, v: BasicValueEnum<'ctx>, fk: usize, slot: Slot, depth: u8) {
        let mut u = v.get_first_use();
        while let Some(use_) = u {
            u = use_.get_next_use();
            let Some(i) = user_inst(use_.get_user()) else { continue };
            let Some(k) = operand_index(i, v) else { continue };
            use InstructionOpcode::*;
            match i.get_opcode() {
                IntToPtr => self.push(slot, Ev::Is(PTy::Ptr)),
                Load if k == 0 => self.push(slot, Ev::Is(PTy::Ptr)),
                Store if k == 1 => self.push(slot, Ev::Is(PTy::Ptr)),
                Call => {
                    let Some(callee) = callee_of(i) else { continue };
                    let name = callee.get_name().to_string_lossy().into_owned();
                    let e = match name.as_str() {
                        "soroban.val.from_payload" => Ev::Is(PTy::Val),
                        "soroban.storage_type" => Ev::Is(PTy::Storage),
                        n if (n.starts_with("soroban.load") || n.starts_with("soroban.store")) && k == 0 => Ev::Is(PTy::Ptr),
                        _ => match (self.index.get(&name), host_positions(callee)) {
                            (Some(&g), _) => Ev::Link(Slot::Param(g, k as usize)),
                            (None, Some(pos)) => Ev::Is(pos.get(k as usize).copied().unwrap_or(PTy::Int)),
                            (None, None) => Ev::IntOp,
                        },
                    };
                    self.push(slot, e);
                }
                Return => self.push(slot, Ev::Link(Slot::Ret(fk))),
                Add if depth < 2 => {
                    // Pointer arithmetic keeps the type; follow the sum.
                    let other = i.get_operand(1 - k).and_then(|o| match o {
                        Operand::Value(x) => Some(x),
                        _ => None,
                    });
                    let sum = BasicValueEnum::try_from(i.as_any_value_enum()).ok();
                    if let Some(sum) = sum {
                        if other.and_then(const_of).is_some() {
                            self.uses(sum, fk, slot, depth + 1);
                        } else {
                            // `p + i`: the address use downstream says pointer-or-index.
                            let before = self.ev.get(&slot).map_or(0, |e| e.len());
                            self.uses(sum, fk, slot, depth + 1);
                            if let Some(evs) = self.ev.get_mut(&slot) {
                                for e in &mut evs[before..] {
                                    if *e == Ev::Is(PTy::Ptr) {
                                        *e = Ev::MaybePtr;
                                    }
                                }
                            }
                        }
                    }
                }
                And => {
                    let other = i.get_operand(1 - k).and_then(|o| match o {
                        Operand::Value(x) => const_of(x),
                        _ => None,
                    });
                    let tag_check = other == Some(0xff)
                        && BasicValueEnum::try_from(i.as_any_value_enum()).ok().is_some_and(|m| {
                            let mut mu = m.get_first_use();
                            let mut yes = false;
                            while let Some(x) = mu {
                                mu = x.get_next_use();
                                if let Some(c) = user_inst(x.get_user()) {
                                    if c.get_opcode() == ICmp {
                                        yes |= (0..2).any(|j| match c.get_operand(j) {
                                            Some(Operand::Value(cv)) => const_of(cv).is_some_and(|t| t < 79),
                                            _ => false,
                                        });
                                    }
                                }
                            }
                            yes
                        });
                    self.push(slot, if tag_check { Ev::TagCheck } else { Ev::IntOp });
                }
                Mul | UDiv | SDiv | URem | SRem | Shl | LShr | AShr | Or | Xor | Sub | Switch => self.push(slot, Ev::IntOp),
                _ => {}
            }
        }
    }

    /// What a function returns, from its `ret` instructions.
    fn returns(&mut self, fk: usize) {
        let f = self.fns[fk];
        for bb in f.get_basic_blocks() {
            let Some(t) = bb.get_terminator() else { continue };
            if t.get_opcode() != InstructionOpcode::Return || t.get_num_operands() == 0 {
                continue;
            }
            let Some(Operand::Value(v)) = t.get_operand(0) else { continue };
            self.returned(v, fk, 0);
        }
    }

    fn returned(&mut self, v: BasicValueEnum<'ctx>, fk: usize, depth: u8) {
        let slot = Slot::Ret(fk);
        if let Some(p) = self.fns[fk].get_params().iter().position(|p| p.as_value_ref() == v.as_value_ref()) {
            self.push(slot, Ev::Link(Slot::Param(fk, p)));
            return;
        }
        let Some(i) = v.as_instruction_value() else { return };
        use InstructionOpcode::*;
        match i.get_opcode() {
            Call => {
                let Some(callee) = callee_of(i) else { return };
                let name = callee.get_name().to_string_lossy().into_owned();
                let e = match name.as_str() {
                    "soroban.val.payload" => Ev::Is(PTy::Val),
                    _ => match self.index.get(&name) {
                        Some(&g) => Ev::Link(Slot::Ret(g)),
                        None => Ev::IntOp,
                    },
                };
                self.push(slot, e);
            }
            PtrToInt => self.push(slot, Ev::Is(PTy::Ptr)),
            Phi if depth < 2 => {
                if let Ok(phi) = inkwell::values::PhiValue::try_from(i) {
                    for k in 0..phi.count_incoming() {
                        if let Some((iv, _)) = phi.get_incoming(k) {
                            self.returned(iv, fk, depth + 1);
                        }
                    }
                }
            }
            Add | Sub | Mul | And | Or | Xor | Shl | LShr | AShr | Select | ZExt | Trunc => self.push(slot, Ev::IntOp),
            _ => {}
        }
    }
}

/// What the LLVM type and the wasm type leave open for a parameter or return.
fn candidates(f: FunctionValue, loc: AttributeLoc, llvm_ty: inkwell::types::BasicTypeEnum) -> Vec<PTy> {
    use inkwell::types::BasicTypeEnum::*;
    match llvm_ty {
        StructType(_) => vec![PTy::Val],
        PointerType(_) => vec![PTy::Ptr],
        _ => {
            let w = f.get_string_attribute(loc, "wasm.type").map(|a| a.get_string_value().to_string_lossy().into_owned());
            match w.as_deref() {
                Some("i32") => vec![PTy::Ptr, PTy::Int],
                Some("i64") => vec![PTy::Val, PTy::Storage, PTy::Int],
                _ => vec![PTy::Ptr, PTy::Val, PTy::Storage, PTy::Int],
            }
        }
    }
}

pub fn infer(m: &Module) -> Sigs {
    let fns: Vec<FunctionValue> = m.get_functions().filter(|f| f.count_basic_blocks() > 0).collect();
    let index: HashMap<String, usize> = fns.iter().enumerate().map(|(k, f)| (f.get_name().to_string_lossy().into_owned(), k)).collect();
    let mut inf = Infer { fns: fns.clone(), index: index.clone(), ev: HashMap::new() };

    // Candidate sets, and the evidence.
    let mut cands: HashMap<Slot, Vec<PTy>> = HashMap::new();
    for (k, f) in fns.iter().enumerate() {
        for (i, p) in f.get_params().iter().enumerate() {
            cands.insert(Slot::Param(k, i), candidates(*f, AttributeLoc::Param(i as u32), p.get_type()));
            inf.uses(*p, k, Slot::Param(k, i), 0);
        }
        if let Some(rt) = f.get_type().get_return_type() {
            cands.insert(Slot::Ret(k), candidates(*f, AttributeLoc::Return, rt));
            inf.returns(k);
            // What callers do with the result.
            let fv = f.as_global_value().as_pointer_value();
            let mut u = fv.get_first_use();
            while let Some(use_) = u {
                u = use_.get_next_use();
                let Some(call) = user_inst(use_.get_user()) else { continue };
                if call.get_opcode() != InstructionOpcode::Call || callee_of(call).map(|c| c.as_value_ref()) != Some(f.as_value_ref()) {
                    continue;
                }
                let Ok(r) = BasicValueEnum::try_from(call.as_any_value_enum()) else { continue };
                let caller = call.get_parent().and_then(|b| b.get_parent()).and_then(|cf| index.get(&cf.get_name().to_string_lossy().into_owned()).copied());
                if let Some(ck) = caller {
                    inf.uses(r, ck, Slot::Ret(k), 0);
                }
            }
        }
    }

    // Decide: fixed types first, then direct evidence, then links to a
    // fixpoint, then the weak hints, then the wasm type.
    let mut decided: HashMap<Slot, PTy> = HashMap::new();
    let pick = |set: Vec<PTy>| -> Option<PTy> {
        let mut s = set;
        s.sort_by_key(|t| *t as u8);
        s.dedup();
        match s.len() {
            1 => Some(s[0]),
            0 => None,
            _ => Some(PTy::Int), // conflicting evidence: the integer it is in wasm
        }
    };
    for (slot, c) in &cands {
        if c.len() == 1 {
            decided.insert(*slot, c[0]);
            continue;
        }
        let strong: Vec<PTy> = inf.ev.get(slot).into_iter().flatten().filter_map(|e| match e {
            Ev::Is(t) if c.contains(t) => Some(*t),
            _ => None,
        }).collect();
        if let Some(t) = pick(strong) {
            decided.insert(*slot, t);
        }
    }
    loop {
        let mut changed = false;
        for (slot, c) in &cands {
            if decided.contains_key(slot) {
                continue;
            }
            let linked: Vec<PTy> = inf.ev.get(slot).into_iter().flatten().filter_map(|e| match e {
                Ev::Link(t) => decided.get(t).copied().filter(|t| c.contains(t)),
                _ => None,
            }).collect();
            if let Some(t) = pick(linked) {
                decided.insert(*slot, t);
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    for (slot, c) in &cands {
        if decided.contains_key(slot) {
            continue;
        }
        let evs = inf.ev.get(slot).map(|v| v.as_slice()).unwrap_or(&[]);
        let int_op = evs.contains(&Ev::IntOp);
        let t = if evs.contains(&Ev::TagCheck) && c.contains(&PTy::Val) {
            PTy::Val
        } else if evs.contains(&Ev::MaybePtr) && !int_op && c.contains(&PTy::Ptr) {
            // ponytail: `p + i` marks both as pointer-or-index; without other
            // evidence the pointer wins for both. A mislabelled index still
            // type-checks (it is added as an integer either way).
            PTy::Ptr
        } else {
            PTy::Int
        };
        decided.insert(*slot, t);
    }

    let params = fns
        .iter()
        .enumerate()
        .map(|(k, f)| (0..f.count_params() as usize).map(|i| decided[&Slot::Param(k, i)]).collect())
        .collect();
    let rets = fns.iter().enumerate().map(|(k, f)| f.get_type().get_return_type().map(|_| decided[&Slot::Ret(k)])).collect();
    Sigs { index, params, rets }
}
