//! LLVM's passes over the lifted module, and our own folds around them.
use inkwell::module::Module;
use inkwell::passes::PassBuilderOptions;
use inkwell::targets::{CodeModel, InitializationConfig, RelocMode, Target, TargetMachine, TargetTriple};
use inkwell::types::AnyTypeEnum;
use inkwell::values::{
    AnyValue, AsValueRef, BasicValue, BasicValueEnum, InstructionOpcode, IntValue, Operand, PointerValue,
};
use inkwell::OptimizationLevel;

use crate::*;

/// LLVM does the interpretation: inlining collapses the SDK's plumbing into
/// the export and constants reach the syscalls. O1 and not higher: O2's
/// simplifycfg turns a `switch` into a lookup table, hiding the very arms this
/// tool exists to keep.
pub(crate) fn optimize(m: &Module, mem: &Mem) -> Result<(), String> {
    // wasm32's own target when this LLVM has it: 32-bit pointers, so an
    // address widened to i64 has no high bits and the frame folds see
    // through the i32 arithmetic. Else the native target.
    let make = |triple: &TargetTriple| {
        Target::from_triple(triple).ok()?.create_target_machine(triple, "generic", "", OptimizationLevel::Less, RelocMode::Default, CodeModel::Default)
    };
    Target::initialize_webassembly(&InitializationConfig::default());
    let tm = match make(&TargetTriple::create("wasm32-unknown-unknown")) {
        Some(tm) => tm,
        None => {
            Target::initialize_native(&InitializationConfig::default())?;
            make(&TargetMachine::get_default_triple()).ok_or("no target machine")?
        }
    };
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
pub(crate) fn fold_frame_pointers(m: &Module) -> usize {
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
pub(crate) fn ptr_plus_const(a: IntValue) -> Option<(PointerValue, i64)> {
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
pub(crate) fn fold_data_loads(m: &Module, mem: &Mem) -> usize {
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
pub(crate) fn const_addr(p: PointerValue) -> Option<u64> {
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
pub(crate) fn strip_inline_suffixes(m: &Module) {
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
