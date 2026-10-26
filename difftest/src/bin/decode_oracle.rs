//! Canonical dump of a module as parsed by wasmparser-nostd 0.100.2 (Soroban's
//! parser), plus validation with Soroban's feature set
//! (src: soroban-env-host/src/budget/wasmi_helper.rs:144-156 -> wasmi Config::wasm_features).
use std::fmt::Write;
use wasmparser::{
    BlockType, DataKind, ElementItems, ElementKind, ExternalKind, Operator, Parser, Payload, TypeRef,
    ValType, Validator, WasmFeatures,
};

fn vt(t: ValType) -> &'static str {
    match t { ValType::I32 => "i32", ValType::I64 => "i64", ValType::F32 => "f32", ValType::F64 => "f64",
              ValType::V128 => "v128", ValType::FuncRef => "funcref", ValType::ExternRef => "externref" }
}
fn bt(b: BlockType) -> String {
    match b { BlockType::Empty => "empty".into(), BlockType::Type(t) => vt(t).into(), BlockType::FuncType(i) => format!("type{}", i) }
}
fn op(o: &Operator) -> Option<String> {
    use Operator::*;
    let m = |a: &wasmparser::MemArg| format!("{} {}", a.align, a.offset);
    Some(match o {
        Unreachable => "unreachable".into(), Nop => "nop".into(),
        Block { blockty } => format!("block {}", bt(*blockty)), Loop { blockty } => format!("loop {}", bt(*blockty)),
        If { blockty } => format!("if {}", bt(*blockty)), Else => "else".into(), End => "end".into(),
        Br { relative_depth } => format!("br {}", relative_depth), BrIf { relative_depth } => format!("br_if {}", relative_depth),
        BrTable { targets } => { let ts: Vec<u32> = targets.targets().map(|t| t.unwrap()).collect();
            format!("br_table {:?} {}", ts, targets.default()) }
        Return => "return".into(), Call { function_index } => format!("call {}", function_index),
        CallIndirect { type_index, table_index, .. } => format!("call_indirect {} {}", type_index, table_index),
        Drop => "drop".into(), Select => "select".into(),
        LocalGet { local_index } => format!("local.get {}", local_index), LocalSet { local_index } => format!("local.set {}", local_index),
        LocalTee { local_index } => format!("local.tee {}", local_index), GlobalGet { global_index } => format!("global.get {}", global_index),
        GlobalSet { global_index } => format!("global.set {}", global_index),
        I32Load { memarg } => format!("i32.load {}", m(memarg)), I64Load { memarg } => format!("i64.load {}", m(memarg)),
        I32Load8S { memarg } => format!("i32.load8_s {}", m(memarg)), I32Load8U { memarg } => format!("i32.load8_u {}", m(memarg)),
        I32Load16S { memarg } => format!("i32.load16_s {}", m(memarg)), I32Load16U { memarg } => format!("i32.load16_u {}", m(memarg)),
        I64Load8S { memarg } => format!("i64.load8_s {}", m(memarg)), I64Load8U { memarg } => format!("i64.load8_u {}", m(memarg)),
        I64Load16S { memarg } => format!("i64.load16_s {}", m(memarg)), I64Load16U { memarg } => format!("i64.load16_u {}", m(memarg)),
        I64Load32S { memarg } => format!("i64.load32_s {}", m(memarg)), I64Load32U { memarg } => format!("i64.load32_u {}", m(memarg)),
        I32Store { memarg } => format!("i32.store {}", m(memarg)), I64Store { memarg } => format!("i64.store {}", m(memarg)),
        I32Store8 { memarg } => format!("i32.store8 {}", m(memarg)), I32Store16 { memarg } => format!("i32.store16 {}", m(memarg)),
        I64Store8 { memarg } => format!("i64.store8 {}", m(memarg)), I64Store16 { memarg } => format!("i64.store16 {}", m(memarg)),
        I64Store32 { memarg } => format!("i64.store32 {}", m(memarg)),
        MemorySize { .. } => "memory.size".into(), MemoryGrow { .. } => "memory.grow".into(),
        I32Const { value } => format!("i32.const {}", *value as u32), I64Const { value } => format!("i64.const {}", *value as u64),
        I32Eqz => "i32.eqz".into(), I32Eq => "i32.eq".into(), I32Ne => "i32.ne".into(), I32LtS => "i32.lt_s".into(), I32LtU => "i32.lt_u".into(),
        I32GtS => "i32.gt_s".into(), I32GtU => "i32.gt_u".into(), I32LeS => "i32.le_s".into(), I32LeU => "i32.le_u".into(),
        I32GeS => "i32.ge_s".into(), I32GeU => "i32.ge_u".into(),
        I64Eqz => "i64.eqz".into(), I64Eq => "i64.eq".into(), I64Ne => "i64.ne".into(), I64LtS => "i64.lt_s".into(), I64LtU => "i64.lt_u".into(),
        I64GtS => "i64.gt_s".into(), I64GtU => "i64.gt_u".into(), I64LeS => "i64.le_s".into(), I64LeU => "i64.le_u".into(),
        I64GeS => "i64.ge_s".into(), I64GeU => "i64.ge_u".into(),
        I32Clz => "i32.clz".into(), I32Ctz => "i32.ctz".into(), I32Popcnt => "i32.popcnt".into(),
        I32Add => "i32.add".into(), I32Sub => "i32.sub".into(), I32Mul => "i32.mul".into(), I32DivS => "i32.div_s".into(), I32DivU => "i32.div_u".into(),
        I32RemS => "i32.rem_s".into(), I32RemU => "i32.rem_u".into(), I32And => "i32.and".into(), I32Or => "i32.or".into(), I32Xor => "i32.xor".into(),
        I32Shl => "i32.shl".into(), I32ShrS => "i32.shr_s".into(), I32ShrU => "i32.shr_u".into(), I32Rotl => "i32.rotl".into(), I32Rotr => "i32.rotr".into(),
        I64Clz => "i64.clz".into(), I64Ctz => "i64.ctz".into(), I64Popcnt => "i64.popcnt".into(),
        I64Add => "i64.add".into(), I64Sub => "i64.sub".into(), I64Mul => "i64.mul".into(), I64DivS => "i64.div_s".into(), I64DivU => "i64.div_u".into(),
        I64RemS => "i64.rem_s".into(), I64RemU => "i64.rem_u".into(), I64And => "i64.and".into(), I64Or => "i64.or".into(), I64Xor => "i64.xor".into(),
        I64Shl => "i64.shl".into(), I64ShrS => "i64.shr_s".into(), I64ShrU => "i64.shr_u".into(), I64Rotl => "i64.rotl".into(), I64Rotr => "i64.rotr".into(),
        I32WrapI64 => "i32.wrap_i64".into(), I64ExtendI32S => "i64.extend_i32_s".into(), I64ExtendI32U => "i64.extend_i32_u".into(),
        I32Extend8S => "i32.extend8_s".into(), I32Extend16S => "i32.extend16_s".into(), I64Extend8S => "i64.extend8_s".into(),
        I64Extend16S => "i64.extend16_s".into(), I64Extend32S => "i64.extend32_s".into(),
        MemoryInit { data_index, .. } => format!("memory.init {}", data_index), DataDrop { data_index } => format!("data.drop {}", data_index),
        MemoryCopy { .. } => "memory.copy".into(), MemoryFill { .. } => "memory.fill".into(),
        TableInit { elem_index, table } => format!("table.init {} {}", elem_index, table), ElemDrop { elem_index } => format!("elem.drop {}", elem_index),
        TableCopy { dst_table, src_table } => format!("table.copy {} {}", dst_table, src_table),
        _ => return None,
    })
}

fn dump(bytes: &[u8]) -> Result<String, String> {
    let mut o = String::new();
    let mut fn_types: Vec<u32> = vec![];
    let mut code_i = 0usize;
    for p in Parser::new(0).parse_all(bytes) {
        let p = p.map_err(|e| e.message().to_string())?;
        match p {
            Payload::TypeSection(r) => for t in r { match t.map_err(|e| e.message().to_string())? {
                wasmparser::Type::Func(f) => { let ps: Vec<_> = f.params().iter().map(|t| vt(*t)).collect(); let rs: Vec<_> = f.results().iter().map(|t| vt(*t)).collect();
                    writeln!(o, "type {:?} -> {:?}", ps, rs).unwrap(); } } },
            Payload::ImportSection(r) => for i in r { let i = i.map_err(|e| e.message().to_string())?;
                let d = match i.ty { TypeRef::Func(t) => format!("func {}", t), TypeRef::Memory(m) => format!("mem {} {:?}", m.initial, m.maximum),
                    TypeRef::Global(g) => format!("global {} {}", vt(g.content_type), g.mutable as u8), TypeRef::Table(t) => format!("table {} {:?}", t.initial, t.maximum), _ => "other".into() };
                writeln!(o, "import {} {} {}", i.module, i.name, d).unwrap(); },
            Payload::FunctionSection(r) => for t in r { fn_types.push(t.map_err(|e| e.message().to_string())?); },
            Payload::TableSection(r) => for t in r { let t = t.map_err(|e| e.message().to_string())?; writeln!(o, "table {} {:?}", t.initial, t.maximum).unwrap(); },
            Payload::MemorySection(r) => for m in r { let m = m.map_err(|e| e.message().to_string())?; writeln!(o, "memory {} {:?}", m.initial, m.maximum).unwrap(); },
            Payload::GlobalSection(r) => for g in r { let g = g.map_err(|e| e.message().to_string())?;
                let mut ops = g.init_expr.get_operators_reader(); let first = op(&ops.read().map_err(|e| e.message().to_string())?).unwrap_or("?".into());
                writeln!(o, "global {} {} {}", vt(g.ty.content_type), g.ty.mutable as u8, first).unwrap(); },
            Payload::ExportSection(r) => for e in r { let e = e.map_err(|e| e.message().to_string())?;
                let k = match e.kind { ExternalKind::Func => "func", ExternalKind::Table => "table", ExternalKind::Memory => "mem", ExternalKind::Global => "global", _ => "other" };
                writeln!(o, "export {} {} {}", e.name, k, e.index).unwrap(); },
            Payload::StartSection { func, .. } => writeln!(o, "start {}", func).unwrap(),
            Payload::ElementSection(r) => for e in r { let e = e.map_err(|e| e.message().to_string())?;
                let mode = match e.kind { ElementKind::Passive => "passive".to_string(), ElementKind::Declared => "declared".into(),
                    ElementKind::Active { table_index, offset_expr } => { let mut ops = offset_expr.get_operators_reader();
                        format!("active {} {}", table_index, op(&ops.read().unwrap()).unwrap_or("?".into())) } };
                let items: Vec<String> = match e.items { ElementItems::Functions(fs) => fs.into_iter().map(|f| format!("f{}", f.unwrap())).collect(),
                    ElementItems::Expressions(es) => es.into_iter().map(|x| { let x = x.unwrap(); let mut r = x.get_operators_reader(); format!("{:?}", r.read().unwrap()) }).collect() };
                writeln!(o, "elem {} {:?}", mode, items).unwrap(); },
            Payload::DataCountSection { count, .. } => writeln!(o, "datacount {}", count).unwrap(),
            Payload::DataSection(r) => for d in r { let d = d.map_err(|e| e.message().to_string())?;
                let mode = match d.kind { DataKind::Passive => "passive".to_string(),
                    DataKind::Active { memory_index, offset_expr } => { let mut ops = offset_expr.get_operators_reader();
                        format!("active {} {}", memory_index, op(&ops.read().unwrap()).unwrap_or("?".into())) } };
                let h: u64 = d.data.iter().fold(1469598103934665603u64, |h, b| (h ^ *b as u64).wrapping_mul(1099511628211));
                writeln!(o, "data {} {} {:x}", mode, d.data.len(), h).unwrap(); },
            Payload::CodeSectionEntry(body) => {
                let mut groups = vec![];
                for l in body.get_locals_reader().map_err(|e| e.message().to_string())? { let (n, t) = l.map_err(|e| e.message().to_string())?; groups.push(format!("{}x{}", n, vt(t))); }
                writeln!(o, "func {} type {} locals {:?}", code_i, fn_types.get(code_i).copied().unwrap_or(u32::MAX), groups).unwrap();
                code_i += 1;
                let mut rd = body.get_operators_reader().map_err(|e| e.message().to_string())?;
                while !rd.eof() { let x = rd.read().map_err(|e| e.message().to_string())?;
                    match op(&x) { Some(s) => writeln!(o, "  {}", s).unwrap(), None => return Err(format!("unsupported operator {:?}", x)) } }
            }
            Payload::CustomSection(c) => { writeln!(o, "custom {} {}", c.name(), c.data().len()).unwrap(); }
            _ => {}
        }
    }
    Ok(o)
}

fn main() {
    let path = std::env::args().nth(1).unwrap();
    let bytes = std::fs::read(&path).unwrap();
    let features = WasmFeatures { mutable_global: true, sign_extension: true, bulk_memory: true, saturating_float_to_int: false,
        multi_value: false, reference_types: false, tail_call: false, extended_const: false, floats: false, simd: false,
        relaxed_simd: false, threads: false, multi_memory: false, exceptions: false, memory64: false, memory_control: false, component_model: false };
    let valid = Validator::new_with_features(features).validate_all(&bytes);
    match &valid { Ok(_) => println!("VALID"), Err(e) => println!("INVALID {}", e.message()) }
    match dump(&bytes) { Ok(s) => print!("{}", s), Err(e) => println!("PARSE-ERROR {}", e) }
}
