//! Numbers decoded from and encoded into Vals. The SDK reads a `u128`
//! parameter with a switch on its tag: the object arm calls
//! `obj_to_u128_hi64`/`lo64`, the small arm shifts the payload, the other
//! arm never returns. From then on the number is two words. The reverse --
//! `obj_from_u128_pieces(hi, lo)`, or `(lo << 8) | tag` when it fits -- is
//! the same number again. Shapes carry this: the words are `lo(x)` and
//! `hi(x)`, an encoding is `u128(H, L)`, and `u128(hi(x), lo(x))` is `x`.
use rustc_middle::mir::*;

use super::*;

/// Which part of a decoded number a local holds.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
pub(super) enum Part {
    Lo,
    Hi,
    Whole,
}

/// A decode switch: the Val and the locals that hold the number's parts.
#[derive(Clone, Debug)]
pub(super) struct Decode {
    pub(super) val: Local,
    pub(super) parts: Vec<(Local, Part)>,
}

/// (object tag, small tag, type, the host function for the whole or the high word)
const PAIRS: [(u64, u64, &str, &str); 6] = [
    (68, 10, "u128", "obj_to_u128_hi64"),
    (69, 11, "i128", "obj_to_i128_hi64"),
    (64, 6, "u64", "obj_to_u64"),
    (65, 7, "i64", "obj_to_i64"),
    (66, 8, "u64", "obj_to_timepoint"),
    (67, 9, "u64", "obj_to_duration"),
];

impl<'a, 'tcx> Fn_<'a, 'tcx> {
    /// The Val local whose tag `o` is: `v.0 as u8` or `v.0 & 255`.
    pub(super) fn tag_of(&self, o: &Operand<'tcx>) -> Option<Local> {
        match self.def_of(o)? {
            Rvalue::Cast(CastKind::IntToInt, inner, ty) if *ty == self.tcx.types.u8 => self.val_source(inner),
            Rvalue::BinaryOp(BinOp::BitAnd, ab) if self.konst_u64(&ab.1) == Some(0xff) => self.val_source(&ab.0),
            Rvalue::Use(inner) => self.tag_of(inner),
            _ => None,
        }
    }

    /// Every decode switch in the body, by its block.
    pub(super) fn find_decodes(&self) -> HashMap<BasicBlock, Decode> {
        let mut out = HashMap::new();
        for (bb, data) in self.body.basic_blocks.iter_enumerated() {
            let Some(Terminator { kind: TerminatorKind::SwitchInt { discr, targets }, .. }) = &data.terminator else { continue };
            let Some(val) = self.tag_of(discr) else { continue };
            let arms: HashMap<u64, BasicBlock> = targets.iter().map(|(v, t)| (v as u64, t)).collect();
            let Some(&(obj, small, _, host)) = PAIRS.iter().find(|(o, s, ..)| arms.contains_key(o) && arms.contains_key(s)) else { continue };
            if arms.len() != 2 || !self.diverges_at(targets.otherwise(), 0) {
                continue;
            }
            let (Some(a), Some(b)) = (self.arm_parts(arms[&obj], val, host), self.arm_parts(arms[&small], val, host)) else { continue };
            if a.0 != b.0 {
                continue; // the arms do not meet
            }
            let (mut pa, mut pb) = (a.1, b.1);
            pa.sort();
            pb.sort();
            if pa != pb || pa.is_empty() {
                continue;
            }
            out.insert(bb, Decode { val, parts: pa });
        }
        out
    }

    /// One arm of a decode: the block it meets the other at, and the locals
    /// it leaves the number's parts in. None when it does anything else.
    fn arm_parts(&self, start: BasicBlock, val: Local, host: &str) -> Option<(BasicBlock, Vec<(Local, Part)>)> {
        let mut parts: Vec<(Local, Part)> = Vec::new();
        let mut held: HashMap<Local, Part> = HashMap::new();
        let mut bb = start;
        for _ in 0..8 {
            if self.body.basic_blocks.predecessors()[bb].len() > 1 && bb != start {
                // The meeting point: what the arm left in each local.
                for (l, p) in held {
                    if self.defs.get(&l).copied().unwrap_or(0) > 1 || self.body.basic_blocks.predecessors()[bb].len() > 1 {
                        parts.push((l, p));
                    }
                }
                return Some((bb, parts));
            }
            let data = &self.body.basic_blocks[bb];
            for st in &data.statements {
                let StatementKind::Assign(a) = &st.kind else { return None };
                let Some(dst) = a.0.as_local() else { return None };
                let part = match &a.1 {
                    Rvalue::Use(Operand::Copy(p) | Operand::Move(p)) => p.as_local().and_then(|s| held.get(&s).copied()),
                    Rvalue::Use(Operand::Constant(_)) if self.konst_u64(match &a.1 {
                        Rvalue::Use(o) => o,
                        _ => unreachable!(),
                    }) == Some(0) =>
                    {
                        Some(Part::Hi)
                    }
                    // `payload >> 8`: the small Val's number.
                    Rvalue::BinaryOp(BinOp::Shr, xy) if self.konst_u64(&xy.1) == Some(8) && self.val_source(&xy.0) == Some(val) => {
                        Some(if host.ends_with("hi64") { Part::Lo } else { Part::Whole })
                    }
                    // `(payload as i64) >> 63`: the sign word of a small i128.
                    Rvalue::BinaryOp(BinOp::Shr, xy) if self.konst_u64(&xy.1) == Some(63) => Some(Part::Hi),
                    Rvalue::Cast(_, inner, _) => match inner {
                        Operand::Copy(p) | Operand::Move(p) => p.as_local().and_then(|s| held.get(&s).copied()),
                        _ => None,
                    },
                    _ => None,
                };
                match part {
                    Some(p) => {
                        held.insert(dst, p);
                    }
                    None if pure(&a.1) => {} // a temporary on the way (the payload, a cast)
                    None => return None,
                }
            }
            match &data.terminator.as_ref()?.kind {
                TerminatorKind::Goto { target } => bb = *target,
                TerminatorKind::Call { func, args, destination, target: Some(t), .. } => {
                    let name = self.callee_name(func)?;
                    let arg_is_val = args.first().and_then(|a| self.val_source(&a.node)) == Some(val);
                    let part = match name.as_str() {
                        n if n == host && arg_is_val => {
                            if host.ends_with("hi64") {
                                Part::Hi
                            } else {
                                Part::Whole
                            }
                        }
                        "obj_to_u128_lo64" | "obj_to_i128_lo64" if arg_is_val => Part::Lo,
                        _ => return None,
                    };
                    held.insert(destination.as_local()?, part);
                    bb = *t;
                }
                _ => return None,
            }
        }
        None
    }
}
