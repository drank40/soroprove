//! Run wast2json spec commands on real soroban-wasmi 29.0.0 configured exactly as
//! Soroban does (src: soroban-env-host/src/budget/wasmi_helper.rs:126-159) and print,
//! per command: `<line> <outcome> fuel=<cumulative consumed>`.
use serde_json::Value as J;
use wasmi::{Config, Engine, Extern, FuelConsumptionMode, Func, Global, Linker, Module, Mutability, Store, Value};

fn cfg() -> Config {
    let mut fc = wasmi::FuelCosts::default();
    fc.base = 1; fc.entity = 3; fc.load = 2; fc.store = 1; fc.call = 67;
    let mut c = Config::default();
    c.consume_fuel(true).wasm_bulk_memory(true).wasm_mutable_global(true).wasm_sign_extension(true)
        .wasm_saturating_float_to_int(false).wasm_multi_value(false).wasm_reference_types(false)
        .wasm_tail_call(false).wasm_extended_const(false).floats(false)
        .fuel_consumption_mode(FuelConsumptionMode::Eager).set_fuel_costs(fc);
    c
}

fn val(j: &J) -> Option<Value> {
    let v = j["value"].as_str()?;
    match j["type"].as_str()? { "i32" => Some(Value::I32(v.parse::<u32>().ok()? as i32)), "i64" => Some(Value::I64(v.parse::<u64>().ok()? as i64)), _ => None }
}
fn show(v: &Value) -> String { match v { Value::I32(x) => format!("i32:{}", *x as u32), Value::I64(x) => format!("i64:{}", *x as u64), _ => "?".into() } }

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let dir = &a[1];
    let j: J = serde_json::from_str(&std::fs::read_to_string(&a[2]).unwrap()).unwrap();
    let engine = Engine::new(&cfg());
    let mut cur: Option<(Store<()>, wasmi::Instance)> = None;
    for c in j["commands"].as_array().unwrap() {
        let line = c["line"].as_u64().unwrap_or(0);
        match c["type"].as_str().unwrap_or("") {
            "module" => {
                cur = None;
                let bytes = std::fs::read(format!("{}/{}", dir, c["filename"].as_str().unwrap())).unwrap();
                let Ok(module) = Module::new(&engine, &bytes[..]) else { continue };
                if module.imports().any(|i| i.module() != "spectest") { continue; }
                let mut store = Store::new(&engine, ());
                store.add_fuel(1_000_000_000_000).unwrap();
                let mut linker = <Linker<()>>::new(&engine);
                for i in module.imports() {
                    let ext: Option<Extern> = match i.ty() {
                        wasmi::ExternType::Func(ft) => Some(Func::new(&mut store, ft.clone(), |_, _, _| Ok(())).into()),
                        wasmi::ExternType::Global(gt) => Some(Global::new(&mut store, match gt.content() { wasmi::core::ValueType::I32 => Value::I32(666), _ => Value::I64(666) }, Mutability::Const).into()),
                        _ => None,
                    };
                    if let Some(e) = ext { let _ = linker.define(i.module(), i.name(), e); }
                }
                let Ok(pre) = linker.instantiate(&mut store, &module) else { continue };
                // Soroban rejects start functions (vm.rs ensure_no_start); mirror the Lean runner.
                let Ok(inst) = pre.ensure_no_start(&mut store) else { continue };
                cur = Some((store, inst));
            }
            "assert_return" | "assert_trap" | "assert_exhaustion" | "action" => {
                let Some((store, inst)) = cur.as_mut() else { continue };
                let act = &c["action"];
                if act["type"] != "invoke" || act.get("module").is_some() { continue; }
                let args: Option<Vec<Value>> = act["args"].as_array().unwrap().iter().map(val).collect();
                let Some(args) = args else { continue };
                let Some(f) = inst.get_func(&*store, act["field"].as_str().unwrap()) else { continue };
                let nres = f.ty(&*store).results().len();
                let mut res = vec![Value::I32(0); nres];
                let out = match f.call(&mut *store, &args, &mut res) {
                    Ok(()) => format!("ok [{}]", res.iter().map(show).collect::<Vec<_>>().join(",")),
                    Err(e) => match &e { wasmi::Error::Trap(t) => match t.trap_code() { Some(tc) => format!("trap {:?}", tc), None => format!("error {}", e) }, _ => format!("error {}", e) },
                };
                println!("{} {} fuel={}", line, out, store.fuel_consumed().unwrap());
            }
            _ => {}
        }
    }
}
