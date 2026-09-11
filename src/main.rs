//! Soroban wasm -> typed LLVM IR, built through inkwell.
//!
//! Three invariants, each one killing a decompiler bug class found in the wild:
//!
//! 1. `%Val` is a named struct type, NOT `i64`, and every Val<->i64 crossing is
//!    an explicit call to a declared conversion. Because the call site's
//!    function type is pinned to the callee's declaration (that is what
//!    `build_direct_call` does), passing an integer where a Val is declared is
//!    a `module.verify()` error. Hand-written `.ll` text cannot check this: the
//!    parser derives the call-site type from whatever was written, so a wrong
//!    type is written twice and stays self-consistent.
//! 2. Branch targets are `BasicBlock` handles resolved against the full
//!    enclosing label stack. An out-of-range depth is a hard error, and a
//!    `switch` names a real block for every case plus the default, so no
//!    `br_table` arm can be dropped.
//! 3. `Unknown` is bottom: it materialises only as a call to
//!    `@ponytail.unknown`. There is no literal for a pass to substitute.
//!
//! `--inline` then hands the module to LLVM: helpers become internal, O1's
//! inliner folds the SDK's plumbing into the export, and reads of the data
//! segment become the constants they are, so each syscall shows its
//! arguments. Nothing is guessed there; every step is an LLVM transformation
//! of a faithful module.
mod decode;
mod fingerprints;
mod host;
mod lower;
mod memory;
mod module;
mod optimize;
mod spec;
mod val;
#[cfg(test)]
mod tests;

pub(crate) use decode::*;
pub(crate) use fingerprints::*;
pub(crate) use host::*;
pub(crate) use lower::*;
pub(crate) use memory::*;
pub(crate) use module::*;
pub(crate) use optimize::*;
pub(crate) use val::*;

fn main() {
    let mut args = std::env::args().skip(1);
    let Some(path) = args.next() else {
        eprintln!("usage: ponytail-wasm <contract.wasm> [export|--all|--inline|--sdk|--fingerprints]");
        std::process::exit(2);
    };
    let only = args.next();
    let wasm = std::fs::read(&path).expect("read wasm");
    match lower_module(&wasm, only.as_deref()) {
        Ok(ir) => print!("{ir}"),
        Err(e) => {
            eprintln!("ponytail-wasm: module does not verify:\n{e}");
            std::process::exit(1);
        }
    }
}
