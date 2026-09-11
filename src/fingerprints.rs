//! SDK fingerprints: what a function's code hashes to, the tables, the names they give.
use std::collections::HashMap;
use std::fmt::Write as _;
use wasmparser::Operator;

use crate::*;

pub(crate) fn fnv(s: &str) -> u64 {
    s.bytes().fold(0xcbf29ce484222325u64, |h, b| (h ^ b as u64).wrapping_mul(0x100000001b3))
}

/// Two fingerprints per function. Exact: the code, hashed (FNV-1a) with what
/// varies between builds of the same source taken out -- a constant that is
/// a data address becomes `D`, a call to a lifted function becomes that
/// function's own fingerprint, one round deep, so a wrapper is told apart by
/// what it wraps. Shape: order-free -- the signature, the host functions
/// called, the constants, the number of calls and loops -- which survives
/// what wasm-opt and register allocation do to the same function: `if` for
/// `block/br_if`, values on the stack for locals.
pub(crate) fn fingerprints(
    bodies: &[(usize, Vec<Operator>)],
    sigs: &[String],
    n_imports: u32,
    imports: &HashMap<u32, &'static HostFn>,
    segs: &[(u64, Vec<u8>)],
) -> Vec<(u64, u64)> {
    let is_data = |v: i32| segs.iter().any(|(b, d)| (v as u32 as u64) >= *b && (v as u32 as u64) < b + d.len() as u64);
    let shape = |i: usize, ops: &[Operator]| -> u64 {
        let (mut hosts, mut consts, mut calls, mut loops) = (Vec::new(), Vec::new(), 0usize, 0usize);
        for op in ops {
            match op {
                Operator::I32Const { value } if !is_data(*value) => consts.push(*value as i64),
                Operator::I64Const { value } => consts.push(*value),
                Operator::Call { function_index } => match imports.get(function_index) {
                    Some(hf) => hosts.push(hf.name),
                    None => calls += 1,
                },
                Operator::Loop { .. } => loops += 1,
                _ => {}
            }
        }
        hosts.sort();
        consts.sort();
        fnv(&format!("{} {hosts:?} {consts:?} {calls} {loops}", sigs.get(i).map(String::as_str).unwrap_or("")))
    };
    let round = |prev: Option<&Vec<u64>>| -> Vec<u64> {
        bodies
            .iter()
            .map(|(n_locals, ops)| {
                let mut h: u64 = 0xcbf29ce484222325;
                let mut feed = |s: &str| {
                    for b in s.bytes() {
                        h ^= b as u64;
                        h = h.wrapping_mul(0x100000001b3);
                    }
                };
                feed(&n_locals.to_string());
                for op in ops {
                    match op {
                        Operator::I32Const { value } if is_data(*value) => feed("D"),
                        Operator::Call { function_index } => match (imports.get(function_index), function_index.checked_sub(n_imports)) {
                            (Some(hf), _) => feed(hf.name),
                            (None, Some(l)) => feed(&prev.and_then(|p| p.get(l as usize)).map(|fp| format!("F{fp:x}")).unwrap_or_else(|| "F".into())),
                            _ => feed("F"),
                        },
                        other => feed(&format!("{other:?}")),
                    }
                }
                h
            })
            .collect()
    };
    let first = round(None);
    round(Some(&first)).into_iter().enumerate().map(|(i, exact)| (exact, shape(i, &bodies[i].1))).collect()
}

/// `--fingerprints`, on a reference build that kept its symbol names: one
/// line per named, non-exported function that is not the reference crate's
/// own -- fingerprint, then the demangled path. The header says which SDK
/// and rustc built it.
pub(crate) fn fingerprint_table(fps: &[(u64, u64)], names: &HashMap<u32, String>, exported: &std::collections::HashSet<u32>, n_imports: u32, sdk: Option<&str>, rustc: Option<&str>) -> String {
    let mut out = format!("# sdk {}\n# rustc {}\n# exact shape name\n", sdk.unwrap_or("?"), rustc.unwrap_or("?"));
    for (i, (exact, shape)) in fps.iter().enumerate() {
        let fi = n_imports + i as u32;
        let Some(n) = names.get(&fi) else { continue };
        let full = format!("{:#}", rustc_demangle::demangle(n));
        if exported.contains(&fi) || full.contains("ponytail_ref") {
            continue;
        }
        let _ = writeln!(out, "{exact:016x} {shape:016x} {full}");
    }
    out
}

/// A loaded table: exact fingerprint -> name, and shape -> names.
#[derive(Default)]
pub(crate) struct Table {
    exact: HashMap<u64, String>,
    shape: HashMap<u64, Vec<String>>,
}

impl Table {
    /// The name for a function: its exact fingerprint's, else its shape's
    /// when that names exactly one function.
    pub(crate) fn name(&self, exact: u64, shape: u64) -> Option<(&str, bool)> {
        if let Some(n) = self.exact.get(&exact) {
            return Some((n, true));
        }
        match self.shape.get(&shape).map(Vec::as_slice) {
            Some([n]) => Some((n, false)),
            _ => None,
        }
    }
}

/// The cached table nearest the binary's SDK version: `<dir>/<sdk>.txt`, or
/// `<sdk>+rustc<ver>.txt` when the reference was built with a chosen
/// toolchain (preferred when it is the binary's). The dir is
/// `PONYTAIL_FINGERPRINTS`; else both ~/.cache/ponytail-wasm/fingerprints,
/// which gen.sh fills, and the tables checked in with this source. Returns
/// the table and a note for the IR header.
pub(crate) fn load_fingerprints(sdk: Option<&str>, rustc: Option<&str>) -> (Table, String) {
    let dirs: Vec<String> = match std::env::var("PONYTAIL_FINGERPRINTS") {
        Ok(d) => vec![d],
        Err(_) => vec![
            format!("{}/.cache/ponytail-wasm/fingerprints", std::env::var("HOME").unwrap_or_default()),
            concat!(env!("CARGO_MANIFEST_DIR"), "/fingerprints").to_string(),
        ],
    };
    let ver = |s: &str| -> Vec<u64> { s.split('.').map(|p| p.parse().unwrap_or(0)).collect() };
    let want = ver(sdk.unwrap_or("0"));
    // (version distance, toolchain differs, path): least wins.
    let mut best: Option<(u64, bool, std::path::PathBuf)> = None;
    for dir in &dirs {
        let Ok(rd) = std::fs::read_dir(dir) else { continue };
        for e in rd.flatten() {
            let name = e.file_name().to_string_lossy().into_owned();
            let Some(stem) = name.strip_suffix(".txt") else { continue };
            let (s, tc) = stem.split_once("+rustc").map(|(a, b)| (a, Some(b))).unwrap_or((stem, None));
            let have = ver(s);
            let dist: u64 = (0..3).map(|i| have.get(i).copied().unwrap_or(0).abs_diff(want.get(i).copied().unwrap_or(0)) << (32 - 16 * i)).sum();
            let cand = (dist, tc != rustc, e.path());
            if best.as_ref().map_or(true, |b| (cand.0, cand.1) < (b.0, b.1)) {
                best = Some(cand);
            }
        }
    }
    let Some((dist, _, path)) = best else {
        return (Table::default(), format!("no fingerprints in {}; run fingerprints/gen.sh {}", dirs.join(" or "), sdk.unwrap_or("<sdk version>")));
    };
    let mut table = Table::default();
    for l in std::fs::read_to_string(&path).unwrap_or_default().lines() {
        let mut it = l.splitn(3, ' ');
        let (Some(exact), Some(shape), Some(name)) = (it.next(), it.next(), it.next()) else { continue };
        let (Ok(exact), Ok(shape)) = (u64::from_str_radix(exact, 16), u64::from_str_radix(shape, 16)) else { continue };
        // Two functions with one body: say both.
        table
            .exact
            .entry(exact)
            .and_modify(|n| {
                if !n.contains(name) {
                    n.push_str(" | ");
                    n.push_str(name);
                }
            })
            .or_insert_with(|| name.to_string());
        let names = table.shape.entry(shape).or_default();
        if !names.iter().any(|n| n == name) {
            names.push(name.to_string());
        }
    }
    let file = path.file_name().map(|f| f.to_string_lossy().into_owned()).unwrap_or_default();
    (table, format!("fingerprints {file}{}", if dist > 0 { " (nearest)" } else { "" }))
}

/// A Rust identifier for a demangled path: `Type_method` for a method or a
/// trait impl, the bare name otherwise. `<soroban_sdk::vec::Vec<T> as
/// TryFromVal<E, Val>>::try_from_val` -> `Vec_try_from_val`.
pub(crate) fn sdk_ident(full: &str) -> String {
    let full = full.split(" | ").next().unwrap_or(full);
    let strip = |s: &str| -> String {
        let mut d = 0i32;
        s.chars()
            .filter(|&c| {
                if c == '<' {
                    d += 1
                }
                let keep = d == 0;
                if c == '>' {
                    d -= 1
                }
                keep
            })
            .collect()
    };
    let (ty, method) = if let Some(rest) = full.strip_prefix('<') {
        let mut d = 1i32;
        let close = rest
            .char_indices()
            .find(|&(_, c)| {
                if c == '<' {
                    d += 1
                }
                if c == '>' {
                    d -= 1
                }
                d == 0
            })
            .map(|(i, _)| i)
            .unwrap_or(rest.len());
        let ty = strip(rest[..close].split(" as ").next().unwrap_or(""));
        (ty, strip(rest.get(close + 1..).unwrap_or("")).trim_start_matches(':').to_string())
    } else {
        let s = strip(full);
        let mut segs = s.rsplit("::");
        let m = segs.next().unwrap_or("").to_string();
        (segs.next().filter(|t| t.starts_with(char::is_uppercase)).unwrap_or("").to_string(), m)
    };
    // `<U as IntoVal<E, T>>` is the blanket impl: no type to name. A tuple is one.
    let ty = if ty.starts_with('(') { "Tuple" } else { ty.rsplit("::").next().unwrap_or("").trim_start_matches('&') };
    let ty = if ty.len() == 1 && ty.starts_with(char::is_uppercase) { "" } else { ty };
    let raw = if ty.is_empty() { method } else { format!("{ty}_{method}") };
    raw.chars().map(|c| if c.is_ascii_alphanumeric() || c == '_' { c } else { '_' }).collect()
}
