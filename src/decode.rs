//! After optimisation: name values after what they are, record keys/strings/rodata for the next stage.
use inkwell::module::Module;
use inkwell::values::{
    BasicValue, BasicValueEnum, CallSiteValue,
    InstructionValue, Operand, ValueKind,
};

use crate::*;

/// Names for what folding has just made constant: a `from_payload` of a
/// literal reads as the Val it is, a StorageType literal as its variant, and a
/// `*_from_linear_memory` call with constant position and length as the
/// symbol, string or Val list sitting in the data segment.
pub(crate) fn rename_decoded(m: &Module, mem: &Mem, spec: &spec::Spec) {
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
pub(crate) fn const_arg(i: InstructionValue, k: u32) -> Option<u64> {
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

pub(crate) fn decode_lm(
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
        Some(String::from_utf8_lossy(&mem.bytes(u(k)?, u(k + 1)? as usize)?).into_owned())
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
                Some(format!("{:?}", String::from_utf8_lossy(&mem.bytes(p, l)?)))
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
        "map.map_unpack_to_linear_memory" | "map.sparse_map_unpack_to_linear_memory" => {
            let keys = slices(u(1)?, u(3)?)?;
            keys_out.push((u(1)?, keys.iter().map(|k| k.trim_matches('"').to_string()).collect()));
            return None;
        }
        // A union's case names, for the derive's `Symbol::index_in_strs`.
        "buf.symbol_index_in_linear_memory" => {
            let names = slices(u(1)?, u(2)?)?;
            keys_out.push((u(1)?, names.iter().map(|k| k.trim_matches('"').to_string()).collect()));
            return None;
        }
        "map.map_new_from_linear_memory" | "map.sparse_map_new_from_linear_memory" => {
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
