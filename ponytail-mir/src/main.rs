//! Rust from `ponytail-wasm --rust` -> optimized MIR, by asking rustc.
//!
//! No MIR is built by hand. rustc parses, type-checks and optimizes the
//! generated crate exactly as it would any other, and `optimized_mir` is read
//! back for every function and printed with rustc's own pretty-printer. The
//! `let` names from the IR survive as `debug` entries, so `v_Symbol__f__`
//! still says what the local is. Constructing `mir::Body` directly would be
//! the same rustc internals, redone worse.
#![feature(rustc_private)]
extern crate rustc_driver;
extern crate rustc_interface;
extern crate rustc_middle;

use rustc_driver::{Callbacks, Compilation};
use rustc_interface::interface::Compiler;
use rustc_middle::mir::write_mir_pretty;
use rustc_middle::ty::TyCtxt;

struct Mir;

impl Callbacks for Mir {
    fn after_analysis<'tcx>(&mut self, _c: &Compiler, tcx: TyCtxt<'tcx>) -> Compilation {
        // The same printer as `-Zunpretty=mir`, over every body in the crate,
        // each in the form codegen would use: optimized MIR.
        write_mir_pretty(tcx, None, &mut std::io::stdout().lock()).expect("write MIR");
        Compilation::Stop
    }
}

fn main() {
    let mut args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: ponytail-mir <generated.rs> [rustc args]");
        std::process::exit(2);
    }
    let file = args.remove(1);
    let mut rustc_args = vec![
        args[0].clone(),
        file,
        "--crate-type=lib".into(),
        "--edition=2021".into(),
        "-Zmir-opt-level=3".into(),
        // Otherwise every wrapping_shr carries a precondition_check call.
        "-Cdebug-assertions=off".into(),
        format!("--sysroot={}", sysroot()),
    ];
    rustc_args.extend(args.into_iter().skip(1));
    rustc_driver::run_compiler(&rustc_args, &mut Mir);
}

/// The sysroot of the toolchain this binary was built with; rustc_driver
/// cannot find it from a binary that does not live in the toolchain.
fn sysroot() -> String {
    if let Ok(s) = std::env::var("SYSROOT") {
        return s;
    }
    let out = std::process::Command::new("rustc")
        .env("RUSTUP_TOOLCHAIN", option_env!("RUSTUP_TOOLCHAIN").unwrap_or("nightly-2026-05-01"))
        .args(["--print", "sysroot"])
        .output()
        .expect("rustc --print sysroot");
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}
