//! wasm -> LLVM -> MIR -> Rust, end to end on the checked-in sample IR.
//! Needs the nightly this crate pins and the LLVM inkwell links (nix-shell).
use std::process::Command;

fn run(args: &[&str]) -> (bool, String, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_ponytail-mir")).args(args).output().expect("run ponytail-mir");
    (out.status.success(), String::from_utf8_lossy(&out.stdout).into_owned(), String::from_utf8_lossy(&out.stderr).into_owned())
}

const LL: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../samples/three_bugs.inline.ll");

fn body_of<'a>(text: &'a str, head: &str) -> String {
    text.lines().skip_while(|l| !l.starts_with(head)).take_while(|l| !l.starts_with('}')).collect::<Vec<_>>().join("\n")
}

#[test]
fn mir_is_rustcs_own_borrowchecked_and_optimized() {
    let (ok, mir, err) = run(&[LL]);
    assert!(ok, "{err}");
    // No body was skipped, and rustc reported nothing against the lifted MIR.
    assert!(!err.contains("ponytail-mir:") && !err.contains("error"), "{err}");
    let set_flag = body_of(&mir, "fn set_flag");
    // rustc's GVN folded the constants into the call and its debuginfo.
    assert!(set_flag.contains("put_contract_data(const Val(11022_u64), const Val(1_u64), const StorageType::Persistent)"), "{set_flag}");
    assert!(set_flag.contains("debug v_Symbol__f__ => const Val(11022_u64);"), "{set_flag}");
}

#[test]
fn rust_from_mir_is_structured_decoded_and_typechecks() {
    let (ok, rs, err) = run(&[LL, "--rust"]);
    assert!(ok, "{err}");
    // Constants read as what they are, through constructors rustc checks.
    assert!(rs.contains("put_contract_data(Val::sym(\"f\"), Val::TRUE, StorageType::Persistent)"), "{rs}");
    // read: the Symbol("Pair") encoding loop folded to its constant; the two
    // frames the host reads Vals from are written as the arrays they are, at
    // the calls that take their position; the key is named in the contract's
    // terms and appears in the storage schema.
    let read = body_of(&rs, "pub fn read");
    assert!(!read.contains("loop"), "{read}");
    assert!(read.contains("pair_key = Val::map(&[\"a\", \"b\"], &[a, b]); // PairKey { a, b }"), "{read}");
    assert!(read.contains("Val::vec(&[Val::sym(\"Pair\") /* DataKey::Pair */, pair_key]); // DataKey::Pair(PairKey { a, b })"), "{read}");
    assert!(rs.contains("//   persistent  DataKey::Pair(PairKey { a, b })   [has: read]"), "{rs}");
    assert!(rs.contains("//   persistent  Val::sym(\"f\")   [put(Val::TRUE): set_flag]"), "{rs}");
    // f37: its parameterless body hands a decoded error to the host; the
    // unread result is not kept.
    assert!(body_of(&rs, "fn f37").contains("fail_with_error(Val::error(0, 1) /* Error::AnError */);"), "{rs}");
    // pick: a five-way dispatch, structured, no state machine, no dead labels,
    // and the phi that merges the arms' results is typed as the Val it feeds.
    let pick = body_of(&rs, "pub fn pick");
    assert!(pick.contains("match ") && !pick.contains("__bb") && !pick.contains("'b"), "{pick}");
    assert!(pick.contains("= Val::sym(\"a\");") && pick.contains("= Val::error(0, 1) /* Error::AnError */;"), "{pick}");
    // contractspecv0: the parameter is named and typed as declared, the
    // dispatch arms are the enum's cases, the map is the struct it builds.
    assert!(rs.contains("/// spec: fn pick(f: Flag) -> Result<Symbol, Error>\npub fn pick(mut f: Val) -> Val"), "{rs}");
    assert!(pick.contains("3 /* Flag::D */ =>"), "{pick}");
    assert!(rs.contains("//   struct PairKey { a: Address, b: Address }"), "{rs}");
    // A helper the SDK fingerprints named comes out under that name, with
    // the demangled path as its doc (errors.wasm: sdk 26.0.1, rustc 1.95.0).
    let (ok, errs, err) = run(&[concat!(env!("CARGO_MANIFEST_DIR"), "/../samples/errors.inline.ll"), "--rust"]);
    assert!(ok, "{err}");
    assert!(errs.contains("/// <soroban_sdk::env::Env as soroban_env_common::env::Env>::fail_with_error\nfn Env_fail_with_error(mut a0: Val)"), "{errs}");
    // test_udt.wasm: the union's `try_from_val` derive is recognised from the
    // case names it scans and named; the SDK's i64 conversion by fingerprint.
    let (ok, udt, err) = run(&[concat!(env!("CARGO_MANIFEST_DIR"), "/../samples/test_udt.inline.ll"), "--rust"]);
    assert!(ok, "{err}");
    assert!(udt.contains("/// The `#[contracttype]` derive `<UdtEnum as TryFromVal<Env, Val>>::try_from_val`.\nfn UdtEnum_try_from_val("), "{udt}");
    assert!(udt.contains("fn i64_try_from_val("), "{udt}");
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
