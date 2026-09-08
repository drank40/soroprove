//! wasm -> LLVM -> MIR -> Rust, end to end on the checked-in sample IR.
//! Needs the nightly this crate pins and the LLVM inkwell links (nix-shell).
use std::process::Command;

fn run(args: &[&str]) -> (bool, String, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_ponytail-mir")).args(args).output().expect("run ponytail-mir");
    (out.status.success(), String::from_utf8_lossy(&out.stdout).into_owned(), String::from_utf8_lossy(&out.stderr).into_owned())
}

const LL: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../samples/three_bugs.inline.ll");

#[test]
fn mir_is_built_validated_and_typed() {
    let (ok, mir, err) = run(&[LL]);
    assert!(ok, "{err}");
    // No body was skipped: every function got MIR rustc accepted.
    assert!(!err.contains("ponytail-mir:"), "{err}");
    let set_flag: String = mir.lines().skip_while(|l| !l.starts_with("fn set_flag")).take_while(|l| !l.starts_with('}')).collect::<Vec<_>>().join("\n");
    assert!(set_flag.contains("= Val(const 11022_u64);"), "{set_flag}");
    assert!(set_flag.contains("= StorageType::Persistent;"), "{set_flag}");
    assert!(set_flag.contains("put_contract_data(copy _1, copy _2, copy _3)"), "{set_flag}");
    assert!(set_flag.contains("debug v_Symbol__f__ => _1;"), "{set_flag}");
}

#[test]
fn rust_from_mir_is_structured_and_typechecks() {
    let (ok, rs, err) = run(&[LL, "--rust"]);
    assert!(ok, "{err}");
    assert!(rs.contains("Persistent = StorageType::Persistent;"), "{rs}");
    assert!(rs.contains("put_contract_data(v_Symbol__f__, v_true, Persistent);"), "{rs}");
    // pick is a five-way dispatch: structured, not a state machine.
    let pick: String = rs.lines().skip_while(|l| !l.starts_with("pub fn pick")).take_while(|l| !l.starts_with('}')).collect::<Vec<_>>().join("\n");
    assert!(pick.contains("match ") && pick.contains("break 'b"), "{pick}");
    assert!(!pick.contains("__bb"), "{pick}");
    // stable rustc is the type checker for the output.
    let dir = std::env::temp_dir().join(format!("ponytail-mir-e2e-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let src = dir.join("three_bugs.rs");
    std::fs::write(&src, &rs).unwrap();
    let out = Command::new("rustc")
        .env("RUSTUP_TOOLCHAIN", "stable")
        .args(["--crate-type", "lib", "--edition", "2021", "--emit", "metadata", "-o"])
        .arg(dir.join("three_bugs.rmeta"))
        .arg(&src)
        .output()
        .expect("rustc");
    assert!(out.status.success(), "{}\n{rs}", String::from_utf8_lossy(&out.stderr));
}
