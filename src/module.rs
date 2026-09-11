//! The module: parse every section, lower every function, optimise, decode, verify.
use std::collections::HashMap;
use std::fmt::Write as _;
use inkwell::attributes::AttributeLoc;
use inkwell::context::Context;
use inkwell::module::Linkage;
use inkwell::types::BasicMetadataTypeEnum;
use inkwell::values::{
    FunctionValue,
};
use wasmparser::{ExternalKind, Operator, Parser, Payload};

use crate::*;

pub(crate) fn lower_module(wasm: &[u8], only: Option<&str>) -> Result<String, String> {
    let by_code: HashMap<(&str, &str), &HostFn> =
        HOST_FNS.iter().map(|h| ((h.module, h.code), h)).collect();

    let mut imports: HashMap<u32, &'static HostFn> = HashMap::new();
    let mut n_imports = 0u32;
    let mut bodies: Vec<(usize, Vec<Operator>)> = Vec::new();
    let mut exports: Vec<(String, u32)> = Vec::new();
    let mut sigs: Vec<(usize, usize)> = Vec::new();
    let mut wasm_types: Vec<(Vec<&'static str>, Vec<&'static str>)> = Vec::new();
    let mut func_types: Vec<u32> = Vec::new();
    let mut types = Types(Vec::new());
    let mut mem = Mem::default();
    let mut spec = spec::Spec::default();
    let mut names: HashMap<u32, String> = HashMap::new();
    let mut meta: Vec<(String, String)> = Vec::new();
    let mut fn_table: Vec<Option<u32>> = Vec::new();

    for p in Parser::new(0).parse_all(wasm) {
        match p.expect("parse") {
            Payload::TypeSection(r) => {
                for rg in r {
                    for st in rg.expect("rec group").into_types() {
                        if let wasmparser::CompositeInnerType::Func(ft) = &st.composite_type.inner {
                            sigs.push((ft.params().len(), ft.results().len()));
                            wasm_types.push((
                                ft.params().iter().map(|v| valtype_name(*v)).collect(),
                                ft.results().iter().map(|v| valtype_name(*v)).collect(),
                            ));
                        } else {
                            sigs.push((0, 0));
                            wasm_types.push((Vec::new(), Vec::new()));
                        }
                        types.0.push(st);
                    }
                }
            }
            Payload::ImportSection(r) => {
                for group in r {
                    for im in group.expect("import group") {
                        let (_, im) = im.expect("import");
                        if let wasmparser::TypeRef::Func(_) = im.ty {
                            if let Some(h) = by_code.get(&(im.module, im.name)) {
                                imports.insert(n_imports, h);
                            }
                            n_imports += 1;
                        }
                    }
                }
            }
            Payload::FunctionSection(r) => {
                for t in r {
                    func_types.push(t.expect("functype"));
                }
            }
            Payload::ExportSection(r) => {
                for e in r {
                    let e = e.expect("export");
                    if e.kind == ExternalKind::Func {
                        exports.push((e.name.to_string(), e.index));
                    }
                }
            }
            Payload::CodeSectionEntry(body) => {
                let mut n_locals = 0usize;
                for l in body.get_locals_reader().expect("locals") {
                    let (c, _) = l.expect("local");
                    n_locals += c as usize;
                }
                let ops: Vec<Operator> = body
                    .get_operators_reader()
                    .expect("ops")
                    .into_iter()
                    .map(|o| o.expect("op"))
                    .collect();
                bodies.push((n_locals, ops));
            }
            Payload::CustomSection(c) if c.name() == "contractspecv0" => spec = spec::parse(c.data()),
            // The SDK stamps its own version and rustc's: `rssdkver`, `rsver`.
            Payload::CustomSection(c) if c.name() == "contractmetav0" => {
                use stellar_xdr::curr::{Limited, Limits, ReadXdr, ScMetaEntry};
                for e in ScMetaEntry::read_xdr_iter(&mut Limited::new(c.data(), Limits::none())).flatten() {
                    let ScMetaEntry::ScMetaV0(m) = e;
                    meta.push((m.key.to_utf8_string_lossy(), m.val.to_utf8_string_lossy()));
                }
            }
            // Symbol names, when the build kept them: the reference build does.
            Payload::CustomSection(c) => {
                if let wasmparser::KnownCustom::Name(r) = c.as_known() {
                    for n in r.into_iter().flatten() {
                        if let wasmparser::Name::Function(map) = n {
                            for wasmparser::Naming { index, name } in map.into_iter().flatten() {
                                names.insert(index, name.to_string());
                            }
                        }
                    }
                }
            }
            Payload::DataSection(r) => {
                for d in r {
                    let d = d.expect("data");
                    if let wasmparser::DataKind::Active { offset_expr, .. } = d.kind {
                        if let Some(base) = const_expr(&offset_expr) {
                            mem.segs.push((base as u32 as u64, d.data.to_vec()));
                        }
                    }
                }
            }
            Payload::GlobalSection(r) => {
                for g in r {
                    let g = g.expect("global");
                    mem.globals.push((const_expr(&g.init_expr).unwrap_or(0), g.ty.mutable));
                }
            }
            // The function table: what `call_indirect` selects from.
            Payload::ElementSection(r) => {
                for e in r {
                    let e = e.expect("element");
                    let wasmparser::ElementKind::Active { table_index, offset_expr } = &e.kind else { continue };
                    if table_index.unwrap_or(0) != 0 {
                        continue;
                    }
                    let Some(base) = const_expr(offset_expr) else { continue };
                    let wasmparser::ElementItems::Functions(fs) = e.items else { continue };
                    for (i, fi) in fs.into_iter().enumerate() {
                        let Ok(fi) = fi else { continue };
                        let at = base as usize + i;
                        if fn_table.len() <= at {
                            fn_table.resize(at + 1, None);
                        }
                        fn_table[at] = Some(fi);
                    }
                }
            }
            _ => {}
        }
    }

    let mut local_sigs: HashMap<u32, (usize, usize)> = HashMap::new();
    let mut wasm_sigs = HashMap::new();
    for (i, t) in func_types.iter().enumerate() {
        if let Some(s) = sigs.get(*t as usize) {
            local_sigs.insert(n_imports + i as u32, *s);
        }
        if let Some(w) = wasm_types.get(*t as usize) {
            wasm_sigs.insert(n_imports + i as u32, w.clone());
        }
    }
    // Which SDK built this, and what its functions are called.
    let sdk_version = meta.iter().find(|(k, _)| k == "rssdkver").map(|(_, v)| v.split('#').next().unwrap_or(v).to_string());
    let rust_version = meta.iter().find(|(k, _)| k == "rsver").map(|(_, v)| v.clone());
    let sig_strs: Vec<String> = (0..bodies.len())
        .map(|i| func_types.get(i).and_then(|t| wasm_types.get(*t as usize)).map(|(p, r)| format!("{p:?}->{r:?}")).unwrap_or_default())
        .collect();
    let fps = fingerprints(&bodies, &sig_strs, n_imports, &imports, &mem.segs);
    let exp_idx: std::collections::HashSet<u32> = exports.iter().map(|(_, i)| *i).collect();
    if only == Some("--fingerprints") {
        return Ok(fingerprint_table(&fps, &names, &exp_idx, n_imports, sdk_version.as_deref(), rust_version.as_deref()));
    }
    if only == Some("--sdk") {
        return Ok(format!("{} {}\n", sdk_version.as_deref().unwrap_or("?"), rust_version.as_deref().unwrap_or("?")));
    }
    let (table, table_note) = load_fingerprints(sdk_version.as_deref(), rust_version.as_deref());
    let mut fnames: HashMap<u32, (String, String)> = HashMap::new();
    let mut used: std::collections::HashSet<String> = exports.iter().map(|(n, _)| n.clone()).collect();
    let mut by_shape = 0;
    for (i, (exact, shape)) in fps.iter().enumerate() {
        let fi = n_imports + i as u32;
        if exp_idx.contains(&fi) {
            continue;
        }
        if let Some((full, is_exact)) = table.name(*exact, *shape) {
            by_shape += !is_exact as usize;
            // Bodies that are one trap are every panic at once: say so.
            let mut id = if full.contains(" | ") && full.split(" | ").all(|n| n.contains("panic") || n.contains("fail")) {
                "panic".to_string()
            } else {
                sdk_ident(full)
            };
            if !used.insert(id.clone()) {
                id = format!("{id}_{fi}");
                used.insert(id.clone());
            }
            fnames.insert(fi, (id, full.to_string()));
        }
    }
    let sdk_note = format!(
        "; sdk {} rustc {}; {}: {} of {} helpers named, {} by shape\n",
        sdk_version.as_deref().unwrap_or("?"),
        rust_version.as_deref().unwrap_or("?"),
        table_note,
        fnames.len(),
        bodies.len() - exp_idx.len(),
        by_shape
    );
    let mut md = Mod { types, mem, wasm_sigs, fnames, table: fn_table };
    md.mem.written = writes_data(&bodies, &md, &imports, &local_sigs);

    let ctx = Context::create();
    let m = ctx.create_module("diver");
    let rt = Rt::new(&ctx, &m);
    // The declared ABI rides along as named metadata, one line per entry.
    for l in &spec.lines {
        let node = ctx.metadata_node(&[ctx.metadata_string(l).into()]);
        m.add_global_metadata("soroban.spec", &node).expect("named metadata takes nodes");
    }
    for (i, (v, mutable)) in md.mem.globals.iter().enumerate() {
        let g = m.add_global(rt.i64t, None, &format!("g{i}"));
        g.set_initializer(&rt.i64t.const_int(*v as u64, false));
        g.set_constant(!mutable);
    }

    // Declare every host function the module imports, with its ABI types. This
    // declaration is what `module.verify()` checks argument types against.
    let mut declared: Vec<&HostFn> = imports.values().copied().collect();
    declared.sort_by_key(|h| h.name);
    declared.dedup_by_key(|h| h.name);
    for h in &declared {
        let ps: Vec<BasicMetadataTypeEnum> =
            h.args.iter().map(|a| rt.ty(*a).into()).collect();
        let t = match h.ret {
            VT::Val => rt.val.fn_type(&ps, false),
            _ => rt.i64t.fn_type(&ps, false),
        };
        let d = m.add_function(h.name, t, None);
        // Keep the IR traceable back to the binary: the wasm import is a
        // single letter and a code, which no reader would guess.
        d.add_attribute(
            AttributeLoc::Function,
            ctx.create_string_attribute("soroban.import", &format!("{}.{}", h.module, h.code)),
        );
        d.add_attribute(
            AttributeLoc::Function,
            ctx.create_string_attribute("soroban.sig", &format!("({}) -> {}", h.arg_tys.join(", "), h.ret_ty)),
        );
        // Host functions never touch linear memory, except the 13 whose names
        // say so. Stating it lets LLVM forward stack slots across the call in
        // --inline mode, and documents the ABI for the reader.
        if !h.name.contains("linear_memory") {
            d.add_attribute(AttributeLoc::Function, attr(&ctx, "memory", MEM_INACCESSIBLE_RW));
        }
    }

    // The interesting code is usually NOT in an export: the SDK dispatch
    // wrapper delegates, and constants and jump tables live in helpers.
    let inline = only == Some("--inline");
    let all = only == Some("--all") || inline;
    let mut targets: Vec<(String, u32)> = exports.clone();
    if all {
        let named: std::collections::HashSet<u32> = exports.iter().map(|(_, i)| *i).collect();
        for i in 0..bodies.len() as u32 {
            let fi = n_imports + i;
            if !named.contains(&fi) {
                targets.push((fn_name(&md, fi), fi));
            }
        }
    }

    let exported: std::collections::HashSet<u32> = exports.iter().map(|(_, i)| *i).collect();

    // Declare every target first, so a call emitted while lowering one function
    // already sees the callee's real signature. Only an export carries the Val
    // ABI; a helper is plain i64.
    let mut plan: Vec<(FunctionValue, u32, usize, usize, bool)> = Vec::new();
    for (name, fidx) in &targets {
        if !all {
            if let Some(f) = only {
                if name != f {
                    continue;
                }
            }
        }
        let Some(local) = fidx.checked_sub(n_imports) else {
            continue;
        };
        let (np, nr) = func_types
            .get(local as usize)
            .and_then(|t| sigs.get(*t as usize))
            .copied()
            .unwrap_or((0, 0));
        let val_abi = exported.contains(fidx);
        let pty: BasicMetadataTypeEnum = if val_abi { rt.val.into() } else { rt.i64t.into() };
        let ps: Vec<BasicMetadataTypeEnum> = (0..np).map(|_| pty).collect();
        let fty = match (nr == 0, val_abi) {
            (true, _) => ctx.void_type().fn_type(&ps, false),
            (false, true) => rt.val.fn_type(&ps, false),
            (false, false) => rt.i64t.fn_type(&ps, false),
        };
        let f = match m.get_function(name) {
            Some(existing) if existing.count_basic_blocks() == 0 => existing,
            Some(_) => continue,
            None => m.add_function(name, fty, None),
        };
        wasm_type_attrs(&ctx, f, *fidx, &md);
        // An export's declared parameter names and types, from the spec.
        if let Some((_, params, ret)) = spec.fns.iter().find(|(n, ..)| n == name) {
            for (i, (pn, pt)) in params.iter().enumerate() {
                f.add_attribute(AttributeLoc::Param(i as u32), ctx.create_string_attribute("spec.name", pn));
                f.add_attribute(AttributeLoc::Param(i as u32), ctx.create_string_attribute("spec.type", pt));
            }
            if let Some(r) = ret {
                f.add_attribute(AttributeLoc::Return, ctx.create_string_attribute("spec.type", r));
            }
            if let Some(line) = spec.lines.iter().find(|l| l.starts_with(&format!("fn {name}("))) {
                f.add_attribute(AttributeLoc::Function, ctx.create_string_attribute("spec.sig", line));
            }
        }
        plan.push((f, local, np, nr, val_abi));
    }

    let mut notes = sdk_note;
    for (f, local, np, nr, val_abi) in plan {
        let Some((n_locals, ops)) = bodies.get(local as usize) else {
            continue;
        };
        if let Err(e) = lower(
            &ctx, &m, &rt, f, np, nr, *n_locals, ops, &imports, &local_sigs, &md, val_abi,
        ) {
            let _ = writeln!(notes, "; FAILED to lower {}: {e}", f.get_name().to_string_lossy());
        }
    }

    // In exports mode a helper is only a declaration, and the syscalls hide
    // behind it: the SDK outlines `storage().set` at every opt level. Say what
    // each declared helper reaches, so `call void @f17()` reads as the
    // put_contract_data it is. A footprint -- a set, not a sequence.
    let mut reach: Vec<std::collections::BTreeSet<&str>> = vec![Default::default(); bodies.len()];
    loop {
        let mut grew = false;
        for i in 0..bodies.len() {
            for op in &bodies[i].1 {
                let Operator::Call { function_index } = op else { continue };
                let add: Vec<&str> = match (imports.get(function_index), function_index.checked_sub(n_imports)) {
                    (Some(h), _) => vec![h.name],
                    (None, Some(l)) => reach.get(l as usize).map(|s| s.iter().copied().collect()).unwrap_or_default(),
                    _ => vec![],
                };
                for a in add {
                    grew |= reach[i].insert(a);
                }
            }
        }
        if !grew {
            break;
        }
    }
    for f in m.get_functions() {
        if f.count_basic_blocks() > 0 {
            continue;
        }
        let name = f.get_name().to_string_lossy().into_owned();
        let Some(set) = name
            .strip_prefix('f')
            .and_then(|n| n.parse::<u32>().ok())
            .and_then(|i| i.checked_sub(n_imports))
            .and_then(|l| reach.get(l as usize))
        else {
            continue;
        };
        let s: Vec<&str> = set.iter().copied().collect();
        f.add_attribute(AttributeLoc::Function, ctx.create_string_attribute("soroban.calls", &s.join(",")));
    }

    if inline {
        define_memory(&ctx, &m, &rt);
        let ex: std::collections::HashSet<&str> = exports.iter().map(|(n, _)| n.as_str()).collect();
        // Helpers become internal and nothing more. That lets LLVM's cost-based
        // inliner take every single-call-site helper (a size win, so it always
        // does) and small shared ones, and drop what it inlined. Forcing
        // `alwaysinline` instead duplicates each shared helper into every call
        // site up the tree: 5.7 GB and no result on a 187-function contract.
        for f in m.get_functions() {
            let n = f.get_name().to_string_lossy().into_owned();
            if f.count_basic_blocks() == 0 || ex.contains(n.as_str()) || n.starts_with("soroban.") {
                continue;
            }
            f.set_linkage(Linkage::Internal);
        }
        optimize(&m, &md.mem)?;
        strip_inline_suffixes(&m);
    }
    rename_decoded(&m, &md.mem, &spec);

    // The real check, and the reason for inkwell: a Val/i64 confusion at a call
    // site is a verifier error here. In hand-written text it never can be.
    m.verify().map_err(|e| e.to_string())?;
    Ok(format!("{}{}", notes, m.print_to_string().to_string()))
}
