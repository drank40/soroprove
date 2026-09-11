//! wasm -> (stellar-diver --inline) LLVM IR -> MIR -> Rust.
//!
//! The MIR is rustc's, not a by-product. A stub crate generated from the
//! `.ll`'s own declarations -- the two ABI types, one `extern "C"` per host
//! function and intrinsic, one static per wasm global, one empty `fn` per
//! defined function -- is compiled in-process, and rustc's `build_mir` hook is
//! replaced so that each stub's MIR *is* the body lifted from LLVM. From there
//! rustc does what it does to any body: borrow-checks it (NLL type-checks
//! every statement), validates it after every pass, and optimizes it with its
//! own inliner, GVN, copy propagation and dead-code passes. `optimized_mir`
//! is what gets printed, and what the Rust is emitted from.
#![feature(rustc_private)]
extern crate rustc_abi;
extern crate rustc_driver;
extern crate rustc_hir;
extern crate rustc_index;
extern crate rustc_interface;
extern crate rustc_middle;
extern crate rustc_span;

mod infer;
mod mir;
mod rs;
mod header;
pub(crate) use header::*;

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

use inkwell::context::Context;
use inkwell::memory_buffer::MemoryBuffer;
use inkwell::module::Module;
use inkwell::values::FunctionValue;
use rustc_driver::{Callbacks, Compilation};
use rustc_hir::def_id::LocalDefId;
use rustc_interface::interface::{Compiler, Config};
use rustc_middle::mir::pretty::MirDumper;
use rustc_middle::mir::Body;
use rustc_middle::ty::TyCtxt;

/// The LLVM module, alive for the whole compilation. Query providers are plain
/// fn pointers, so it lives in a static. rustc compiles on a thread of its
/// own while this one waits, so exactly one thread ever touches it.
struct Llvm {
    m: Module<'static>,
    fns: HashMap<String, FunctionValue<'static>>,
    sigs: infer::Sigs,
}
unsafe impl Send for Llvm {}
unsafe impl Sync for Llvm {}

static LLVM: OnceLock<Llvm> = OnceLock::new();

fn llvm<T>(f: impl FnOnce(&Llvm) -> T) -> T {
    f(LLVM.get().expect("LLVM module loaded"))
}

type BuildMir = for<'tcx> fn(TyCtxt<'tcx>, LocalDefId) -> Body<'tcx>;

/// rustc's own MIR builder, for the bodies that are not ours: the stub's
/// derived impls.
static ORIG_BUILD_MIR: OnceLock<BuildMir> = OnceLock::new();
/// Functions whose lift failed, with why. They keep their stub body.
static FAILED: Mutex<Vec<(String, String)>> = Mutex::new(Vec::new());

/// The `build_mir_inner_impl` hook: the MIR of a stub is the body lifted from
/// the LLVM function of the same name.
fn lifted_build_mir<'tcx>(tcx: TyCtxt<'tcx>, def: LocalDefId) -> Body<'tcx> {
    let orig = ORIG_BUILD_MIR.get().expect("original build_mir saved");
    if tcx.def_kind(def) != rustc_hir::def::DefKind::Fn {
        return orig(tcx, def);
    }
    let name = tcx.item_name(def.to_def_id()).to_string();
    let Some(f) = llvm(|l| l.fns.get(&name).copied()) else { return orig(tcx, def) };
    let env = mir::Env::new(tcx);
    match llvm(|l| mir::build(&env, f, def.to_def_id(), &l.sigs)) {
        Ok(body) => body,
        Err(e) => {
            FAILED.lock().unwrap().push((name, e));
            orig(tcx, def)
        }
    }
}

struct Lift {
    rust: bool,
    contract: bool,
}

impl Callbacks for Lift {
    fn config(&mut self, config: &mut Config) {
        config.override_queries = Some(|_, providers| {
            let _ = ORIG_BUILD_MIR.set(providers.hooks.build_mir_inner_impl);
            providers.hooks.build_mir_inner_impl = lifted_build_mir;
        });
    }

    fn after_analysis<'tcx>(&mut self, _c: &Compiler, tcx: TyCtxt<'tcx>) -> Compilation {
        let env = mir::Env::new(tcx);
        let failed: Vec<String> = FAILED.lock().unwrap().iter().map(|(n, _)| n.clone()).collect();
        // In the module's order, so output is stable.
        let names: Vec<String> = llvm(|l| {
            l.m.get_functions()
                .filter(|f| f.count_basic_blocks() > 0)
                .map(|f| rs_name(&f.get_name().to_string_lossy()))
                .collect()
        });
        let bodies: Vec<&Body<'tcx>> = names
            .iter()
            .filter(|n| !failed.contains(n))
            .filter_map(|n| env.fns.get(n))
            .map(|&d| tcx.optimized_mir(d))
            .collect();
        let mut out = std::io::stdout().lock();
        if self.rust || self.contract {
            let lines = llvm(|l| spec_lines(&l.m));
            let spec = rs::Spec::parse(
                lines.clone(),
                llvm(|l| meta_lines(&l.m, "soroban.keys")),
                llvm(|l| meta_lines(&l.m, "soroban.strings")),
                llvm(|l| meta_lines(&l.m, "soroban.rodata")),
                llvm(|l| sdk_names(&l.m)),
            );
            let text = if self.contract {
                rs::emit_contract(tcx, &env, &bodies, &spec, &lines).unwrap_or_else(|e| fatal(&e))
            } else {
                let head = llvm(|l| header(&l.m, &l.sigs)).unwrap_or_else(|e| fatal(&e));
                rs::emit(tcx, &env, &head, &bodies, &spec).unwrap_or_else(|e| fatal(&e))
            };
            std::io::Write::write_all(&mut out, text.as_bytes()).expect("write");
        } else {
            for body in &bodies {
                let d = MirDumper::new(tcx, "diver", body).expect("-Zdump-mir=diver is passed");
                d.dump_mir_to_writer(body, &mut out).expect("write MIR");
                std::io::Write::write_all(&mut out, b"\n").expect("write");
            }
        }
        for (n, e) in FAILED.lock().unwrap().iter() {
            eprintln!("stellar-diver-mir: {n}: {e}");
        }
        Compilation::Stop
    }
}

fn fatal(msg: &str) -> ! {
    eprintln!("stellar-diver-mir: {msg}");
    std::process::exit(1)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let ll = args.get(1).filter(|a| !a.starts_with("--")).cloned().unwrap_or_else(|| {
        eprintln!("usage: stellar-diver-mir <contract.inline.ll> [--rust|--contract] [--no-validate]");
        std::process::exit(2)
    });
    let rust = args.iter().any(|a| a == "--rust");
    let contract = args.iter().any(|a| a == "--contract");
    let validate = !args.iter().any(|a| a == "--no-validate");

    let ctx: &'static Context = Box::leak(Box::new(Context::create()));
    let buf = MemoryBuffer::create_from_file(&PathBuf::from(&ll)).unwrap_or_else(|e| fatal(&e.to_string()));
    let m = ctx.create_module_from_ir(buf).unwrap_or_else(|e| fatal(&e.to_string()));
    let fns = m
        .get_functions()
        .filter(|f| f.count_basic_blocks() > 0)
        .map(|f| (rs_name(&f.get_name().to_string_lossy()), f))
        .collect();
    let sigs = infer::infer(&m);
    let stub = format!("{}\n{}", header(&m, &sigs).unwrap_or_else(|e| fatal(&e)), stubs(&m, &sigs).unwrap_or_else(|e| fatal(&e)));
    LLVM.set(Llvm { m, fns, sigs }).ok().expect("set once");

    // The dump filter below also matches item paths, and a derived impl's
    // path carries its file name: keep "diver" out of the stub's, and send
    // whatever rustc dumps on its own account to a directory that goes away.
    let scratch = std::env::temp_dir().join(format!("lift-{}", std::process::id()));
    std::fs::create_dir_all(&scratch).unwrap_or_else(|e| fatal(&e.to_string()));
    let stub_path = scratch.join("stub.rs");
    std::fs::write(&stub_path, stub).unwrap_or_else(|e| fatal(&e.to_string()));

    let mut rustc_args = vec![
        args[0].clone(),
        stub_path.to_string_lossy().into_owned(),
        "--crate-type=lib".into(),
        "--edition=2021".into(),
        "--crate-name=contract".into(),
        // rustc's full MIR pipeline, inliner included.
        "-Zmir-opt-level=3".into(),
        // Gates MirDumper; the printer behind -Zdump-mir.
        "-Zdump-mir=diver".into(),
        format!("-Zdump-mir-dir={}", scratch.join("mir_dump").to_string_lossy()),
        format!("--sysroot={}", sysroot()),
    ];
    if validate {
        rustc_args.push("-Zvalidate-mir".into());
    }
    rustc_driver::run_compiler(&rustc_args, &mut Lift { rust, contract });
    let _ = std::fs::remove_dir_all(scratch);
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
