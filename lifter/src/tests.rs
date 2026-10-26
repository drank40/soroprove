use std::collections::HashMap;

use inkwell::context::Context;
use wasmparser::Operator;

use super::*;

fn build(ops: Vec<Operator>, nr: usize) -> Result<String, String> {
    build_with(ops, nr, 0, &Mod::default())
}

fn build_with(ops: Vec<Operator>, nr: usize, n_locals: usize, md: &Mod) -> Result<String, String> {
    let ctx = Context::create();
    let m = ctx.create_module("t");
    let rt = Rt::new(&ctx, &m);
    let fty = if nr == 0 {
        ctx.void_type().fn_type(&[], false)
    } else {
        rt.val.fn_type(&[], false)
    };
    let f = m.add_function("f", fty, None);
    lower(
        &ctx, &m, &rt, f, 0, nr, n_locals, &ops, &HashMap::new(), &HashMap::new(), md, true,
    )?;
    m.verify().map_err(|e| e.to_string())?;
    Ok(m.print_to_string().to_string())
}

#[test]
fn host_table_generated_from_env_json() {
    assert_eq!(HOST_FN_COUNT, HOST_FNS.len());
    assert!(HOST_FN_COUNT >= 171, "got {HOST_FN_COUNT}");
    let put = HOST_FNS
        .iter()
        .find(|h| h.name == "ledger.put_contract_data")
        .expect("put_contract_data");
    assert_eq!(put.args, &[VT::Val, VT::Val, VT::Storage]);
}

#[test]
fn val_payload_1_is_true_not_one() {
    assert_eq!(explain_val(1), "true");
    assert_eq!(explain_val(0), "false");
    assert_eq!(explain_val((1u64 << 32) | 4), "u32 1");
    assert_eq!(explain_val(0x100000003), "Error(type 0, code 1)");
    assert_eq!(explain_val(3867323444879862030), "Symbol(\"persisted\")");
}

#[test]
fn unknown_never_becomes_a_literal() {
    let ir = build(vec![Operator::Return], 1).unwrap();
    assert!(ir.contains("@diver.unknown()"), "{ir}");
    assert!(!ir.contains("ret %Val zeroinitializer"));
}

#[test]
fn branch_depth_out_of_range_is_an_error() {
    assert!(build(vec![Operator::Br { relative_depth: 99 }], 0).is_err());
}

/// Every sample must lower and verify, in both modes. This is the gate that
/// would have caught the `--all` ABI mismatch inkwell found, and it needs no
/// external corpus.
#[test]
fn falling_off_the_end_returns_the_value_not_bottom() {
    let ir = build(vec![Operator::I64Const { value: 2 }, Operator::End], 1).unwrap();
    assert!(ir.contains("ret %Val %v_void"), "{ir}");
    assert!(!ir.contains("bottom"), "{ir}");
}

#[test]
fn unmodelled_ops_pop_what_they_consume() {
    // `memory.copy` consumes three and produces nothing; the 2 beneath is
    // the result. A phantom push would return bottom here.
    let ops = vec![
        Operator::I64Const { value: 2 },
        Operator::I64Const { value: 5 },
        Operator::I64Const { value: 6 },
        Operator::I64Const { value: 7 },
        Operator::MemoryCopy { dst_mem: 0, src_mem: 0 },
        Operator::End,
    ];
    let ir = build(ops, 1).unwrap();
    assert!(ir.contains("ret %Val %v_void"), "{ir}");
}

#[test]
fn data_segment_constants_are_read() {
    let mut md = Mod::default();
    md.mem.segs.push((1048576, vec![1]));
    let ops = || {
        let memarg = wasmparser::MemArg { align: 0, max_align: 0, offset: 0, memory: 0 };
        vec![Operator::I32Const { value: 1048576 }, Operator::I32Load8U { memarg }, Operator::End]
    };
    // `&true` is a byte in the data segment: the load IS `true`...
    let ir = build_with(ops(), 1, 0, &md).unwrap();
    assert!(ir.contains("ret %Val %v_true"), "{ir}");
    // ...unless something in the module writes the segment.
    md.mem.written = true;
    let ir = build_with(ops(), 1, 0, &md).unwrap();
    assert!(ir.contains("@soroban.load8u(i64 1048576)"), "{ir}");
}

#[test]
fn inline_mode_shows_set_flag_as_its_syscall() {
    let wasm = std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/samples/three_bugs.wasm")).unwrap();
    let ir = lower_module(&wasm, Some("--inline")).unwrap();
    let body = ir
        .lines()
        .skip_while(|l| !(l.starts_with("define ") && l.contains("@set_flag(")))
        .take_while(|l| !l.starts_with('}'))
        .collect::<Vec<_>>()
        .join("\n");
    assert!(body.contains("@ledger.put_contract_data("), "{body}");
    assert!(body.contains("%v_true"), "{body}");
    assert!(body.contains("%Persistent"), "{body}");
    assert!(!body.contains("@f"), "helper calls remain: {body}");
    // Inline suffixes are stripped, and the recovered frame leaves no
    // stack-pointer traffic or dead stores behind.
    assert!(body.contains("%put_contract_data = "), "{body}");
    assert!(!body.contains("@g0") && !body.contains(" store "), "{body}");
}

#[test]
fn frame_is_an_alloca() {
    // LLVM's prologue, a spill and a reload through the frame, the epilogue.
    let ma = |offset| wasmparser::MemArg { align: 0, max_align: 0, offset, memory: 0 };
    let ops = vec![
        Operator::GlobalGet { global_index: 0 },
        Operator::I32Const { value: 16 },
        Operator::I32Sub,
        Operator::LocalTee { local_index: 0 },
        Operator::GlobalSet { global_index: 0 },
        Operator::LocalGet { local_index: 0 },
        Operator::I64Const { value: 7 },
        Operator::I64Store { memarg: ma(8) },
        Operator::LocalGet { local_index: 0 },
        Operator::I64Load { memarg: ma(8) },
        Operator::Drop,
        Operator::LocalGet { local_index: 0 },
        Operator::I32Const { value: 16 },
        Operator::I32Add,
        Operator::GlobalSet { global_index: 0 },
        Operator::I64Const { value: 2 },
        Operator::End,
    ];
    let ir = build_with(ops, 1, 1, &Mod::default()).unwrap();
    assert!(ir.contains("%frame = alloca [16 x i8]"), "{ir}");
    assert!(ir.contains("store i64 7, ptr %slot8"), "{ir}");
    assert!(ir.contains("load i64, ptr %slot8"), "{ir}");
    // No stack-pointer traffic and no memory helper: the frame is local.
    assert!(
        !ir.contains("call void @soroban.store64(") && !ir.contains("call i64 @soroban.load64(") && !ir.contains("ptrtoint"),
        "{ir}"
    );
}

#[test]
fn helper_declarations_say_what_they_reach() {
    let wasm = std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/samples/three_bugs.wasm")).unwrap();
    let ir = lower_module(&wasm, Some("set_flag")).unwrap();
    // set_flag: `call 33; call 17; i64.const 2` -- the void is right there.
    assert!(ir.contains("ret %Val %v_void"), "{ir}");
    // f17 is the outlined storage().set; its declaration must say so.
    let calls = ir.lines().find(|l| l.contains("soroban.calls") && l.contains("ledger.put_contract_data"));
    assert!(calls.is_some(), "{ir}");
}

#[test]
fn syscalls_read_as_syscalls() {
    let wasm = std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/samples/errors.wasm")).unwrap();
    let ir = lower_module(&wasm, None).unwrap();
    // The StorageType operand is a named constant, not a bare `i64 1`.
    assert!(ir.contains("%Persistent = call i64 @soroban.storage_type(i64 1)"), "{ir}");
    // The result is named after the syscall, not its import code `_`.
    assert!(ir.contains("%put_contract_data = call %Val @ledger.put_contract_data("), "{ir}");
    // And the declaration still says which wasm import it came from.
    assert!(ir.contains("\"soroban.import\"=\"l._\""), "{ir}");
}

#[test]
fn fingerprints_name_the_sdk_helpers() {
    // The table for the sample's own SDK version is checked in; exact
    // fingerprints name what the reference built the same way, shapes
    // name what register allocation laid out differently.
    std::env::set_var("DIVER_FINGERPRINTS", concat!(env!("CARGO_MANIFEST_DIR"), "/fingerprints"));
    let wasm = std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/samples/three_bugs.wasm")).unwrap();
    let ir = lower_module(&wasm, Some("--all")).unwrap();
    assert!(ir.starts_with("; sdk 25.3.2 rustc 1.97.1; fingerprints 25.3.2.txt: 4 of 43 helpers named, 3 by shape\n"), "{}", ir.lines().next().unwrap_or(""));
    assert!(ir.contains("@Symbol_new(") && ir.contains("\"sdk.name\"=\"<soroban_sdk::symbol::Symbol>::new\""), "{ir}");
    assert_eq!(sdk_ident("<soroban_sdk::vec::Vec<T> as soroban_env_common::convert::TryFromVal<E, Val>>::try_from_val"), "Vec_try_from_val");
    assert_eq!(sdk_ident("<U as soroban_sdk::env::IntoVal<E,T>>::into_val"), "into_val");
    assert_eq!(sdk_ident("<(a::Val, a::Val) as a::TryIntoVal<E, a::Val>>::try_into_val"), "Tuple_try_into_val");
    assert_eq!(sdk_ident("compiler_builtins::mem::memcpy"), "memcpy");
    assert_eq!(sdk_ident("core::ptr::drop_in_place<soroban_sdk::vec::Vec<T>>"), "drop_in_place");
    // The version query, for gen.sh.
    assert_eq!(lower_module(&wasm, Some("--sdk")).unwrap(), "25.3.2 1.97.1\n");
}

#[test]
fn samples_lower_and_verify() {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("samples");
    let mut n = 0;
    for e in std::fs::read_dir(&dir).expect("samples/ exists").flatten() {
        let p = e.path();
        if p.extension().map(|x| x != "wasm").unwrap_or(true) {
            continue;
        }
        let wasm = std::fs::read(&p).expect("read sample");
        for mode in [None, Some("--all"), Some("--inline")] {
            let out = lower_module(&wasm, mode);
            assert!(
                out.is_ok(),
                "{} ({mode:?}) failed to verify: {}",
                p.display(),
                out.unwrap_err()
            );
        }
        n += 1;
    }
    assert!(n >= 3, "expected at least 3 samples, found {n}");
}

/// The whole reason for inkwell: LLVM rejects an integer where a Val is
/// declared. `llvm-as` on equivalent hand-written text does not.
#[test]
fn llvm_rejects_int_where_val_declared() {
    let ctx = Context::create();
    let m = ctx.create_module("t");
    let rt = Rt::new(&ctx, &m);
    let put = m.add_function(
        "put",
        rt.val
            .fn_type(&[rt.val.into(), rt.i64t.into()], false),
        None,
    );
    let f = m.add_function("f", ctx.void_type().fn_type(&[], false), None);
    let b = ctx.create_builder();
    b.position_at_end(ctx.append_basic_block(f, "e"));
    let one = rt.i64t.const_int(1, false);
    // arg 0 is declared %Val; hand it an i64.
    b.build_direct_call(put, &[one.into(), one.into()], "bad")
        .expect("builder allows it");
    b.build_return(None).unwrap();
    assert!(m.verify().is_err(), "verifier should reject the mismatch");
}
