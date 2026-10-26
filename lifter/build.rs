// The host ABI is generated, never transcribed. env.json is the same file the
// Soroban host generates its own dispatch layer from, so the table cannot drift
// into a wrong arity or a missing function.
//
// The only thing that matters for typing: which arguments are tagged `Val`s and
// which are raw machine integers. Everything in env.json is a Val except `u64`,
// `i64` and `StorageType`, which cross the boundary by direct marshalling.
use std::{env, fs, path::PathBuf};

fn vt(t: &str) -> &'static str {
    match t {
        "u64" | "i64" => "VT::Raw64",
        "StorageType" => "VT::Storage",
        _ => "VT::Val",
    }
}

fn main() {
    println!("cargo:rerun-if-changed=env.json");
    let src = fs::read_to_string("env.json").expect("env.json next to Cargo.toml");
    let root: serde_json::Value = serde_json::from_str(&src).unwrap();

    let mut out = String::from("pub static HOST_FNS: &[HostFn] = &[\n");
    let mut n = 0usize;
    for m in root["modules"].as_array().unwrap() {
        let m_code = m["export"].as_str().unwrap();
        let m_name = m["name"].as_str().unwrap();
        for f in m["functions"].as_array().unwrap() {
            let code = f["export"].as_str().unwrap();
            let name = f["name"].as_str().unwrap();
            let ret = f["return"].as_str().unwrap();
            let args: Vec<&str> = f["args"]
                .as_array()
                .map(|a| a.iter().map(|x| x["type"].as_str().unwrap()).collect())
                .unwrap_or_default();
            let arg_vts: Vec<String> = args.iter().map(|t| vt(t).to_string()).collect();
            let arg_names: Vec<String> = args.iter().map(|t| format!("{t:?}")).collect();
            out.push_str(&format!(
                "    HostFn {{ module: {m_code:?}, code: {code:?}, name: {:?}, \
                 args: &[{}], arg_tys: &[{}], ret: {}, ret_ty: {ret:?} }},\n",
                format!("{m_name}.{name}"),
                arg_vts.join(", "),
                arg_names.join(", "),
                vt(ret),
            ));
            n += 1;
        }
    }
    out.push_str("];\n");
    out.push_str(&format!("#[allow(dead_code)]\npub const HOST_FN_COUNT: usize = {n};\n"));

    let dst = PathBuf::from(env::var("OUT_DIR").unwrap()).join("hostfns.rs");
    fs::write(dst, out).unwrap();
}
