//! Linear memory as the binary declares it, and whether anything writes it.
use std::collections::HashMap;
use wasmparser::Operator;

use crate::*;

/// Linear memory as the binary declares it: the initialised data segments, the
/// wasm globals' initial values, and whether any store in the module targets a
/// segment at a constant address. A load from an unwritten segment at a
/// constant address IS a constant -- that is where `&true` and the static keys
/// behind every outlined `storage().set` live.
/// ponytail: a store through a pointer into a segment is invisible here. Rust
/// keeps mutable statics out of rodata, so this is the decompiler's usual bet;
/// `written` catches the direct `static mut` case.
#[derive(Default)]
pub(crate) struct Mem {
    pub(crate) segs: Vec<(u64, Vec<u8>)>,
    pub(crate) written: bool,
    /// (initial value, mutable), by global index.
    pub(crate) globals: Vec<(i64, bool)>,
}

impl Mem {
    pub(crate) fn bytes(&self, addr: u64, n: usize) -> Option<Vec<u8>> {
        if self.written {
            return None;
        }
        // Linear memory is zero-initialised and the encoder trims a segment's
        // trailing zeros: past a segment's end, up to the next one, is zero.
        let (base, d) = self.segs.iter().find(|(base, d)| addr >= *base && addr < base + d.len() as u64)?;
        let off = (addr - base) as usize;
        let end = off.checked_add(n)?;
        if self.segs.iter().any(|(b2, _)| *b2 > *base && *b2 < base + end as u64) {
            return None;
        }
        let mut out = d[off..d.len().min(end)].to_vec();
        out.resize(n, 0);
        Some(out)
    }

    /// A `bits`-wide load at a constant address, as the i64 the model carries.
    pub(crate) fn load(&self, addr: u64, bits: u32, signed: bool) -> Option<i64> {
        let b = self.bytes(addr, (bits / 8) as usize)?;
        let v = b.iter().enumerate().fold(0u64, |v, (i, x)| v | ((*x as u64) << (8 * i)));
        Some(if signed && bits < 64 { ((v << (64 - bits)) as i64) >> (64 - bits) } else { v as i64 })
    }
}

/// Does any store in the module target a data segment at a constant address?
/// Constants are tracked through straight-line code only; a control-flow
/// operator clears what is known. Enough to catch a `static mut` counter,
/// which is how Rust actually writes its own data segment.
pub(crate) fn writes_data(
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
