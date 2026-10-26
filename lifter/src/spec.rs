//! `contractspecv0`: the ABI the contract declares, as `ScSpecEntry` XDR.
//!
//! It states what nothing else in the binary does: the exported functions'
//! parameter names and declared types, and the user-defined types -- structs
//! with their field names, unions with their cases, integer and error enums
//! with their values. Rendered here once, in a compact Rust-like line per
//! entry, for the reader and for the MIR stage, which recovers the structure
//! it needs from the lines. The shapes are `ScVal` shapes, not memory layout.
use stellar_xdr::curr::{Limited, Limits, ReadXdr, ScSpecEntry, ScSpecTypeDef, ScSpecUdtUnionCaseV0};

#[derive(Default)]
pub struct Spec {
    /// One line per entry: `struct P { a: Address, b: Address }`, `union ..`,
    /// `enum ..`, `error ..`, `fn name(p: T) -> R`, `event ..`.
    pub lines: Vec<String>,
    /// Exported function -> its parameters' names and rendered types, and
    /// its rendered return type.
    pub fns: Vec<(String, Vec<(String, String)>, Option<String>)>,
    /// Struct name -> field names, in declaration order.
    pub structs: Vec<(String, Vec<String>)>,
}

pub fn parse(bytes: &[u8]) -> Spec {
    let mut spec = Spec::default();
    let mut lim = Limited::new(bytes, Limits::none());
    for e in ScSpecEntry::read_xdr_iter(&mut lim).flatten() {
        match e {
            ScSpecEntry::FunctionV0(f) => {
                let name = f.name.to_utf8_string_lossy();
                let params: Vec<(String, String)> =
                    f.inputs.iter().map(|i| (i.name.to_utf8_string_lossy(), ty(&i.type_))).collect();
                let ret = f.outputs.first().map(ty);
                let ps: Vec<String> = params.iter().map(|(n, t)| format!("{n}: {t}")).collect();
                spec.lines.push(format!("fn {name}({}){}", ps.join(", "), ret.as_deref().map(|r| format!(" -> {r}")).unwrap_or_default()));
                spec.fns.push((name, params, ret));
            }
            ScSpecEntry::UdtStructV0(s) => {
                let name = s.name.to_utf8_string_lossy();
                let fields: Vec<String> = s.fields.iter().map(|f| format!("{}: {}", f.name.to_utf8_string_lossy(), ty(&f.type_))).collect();
                spec.lines.push(format!("struct {name} {{ {} }}", fields.join(", ")));
                spec.structs.push((name, s.fields.iter().map(|f| f.name.to_utf8_string_lossy()).collect()));
            }
            ScSpecEntry::UdtUnionV0(u) => {
                let cases: Vec<String> = u
                    .cases
                    .iter()
                    .map(|c| match c {
                        ScSpecUdtUnionCaseV0::VoidV0(v) => v.name.to_utf8_string_lossy(),
                        ScSpecUdtUnionCaseV0::TupleV0(t) => {
                            format!("{}({})", t.name.to_utf8_string_lossy(), t.type_.iter().map(ty).collect::<Vec<_>>().join(", "))
                        }
                    })
                    .collect();
                spec.lines.push(format!("union {} {{ {} }}", u.name.to_utf8_string_lossy(), cases.join(", ")));
            }
            ScSpecEntry::UdtEnumV0(e) => {
                let cases: Vec<String> = e.cases.iter().map(|c| format!("{} = {}", c.name.to_utf8_string_lossy(), c.value)).collect();
                spec.lines.push(format!("enum {} {{ {} }}", e.name.to_utf8_string_lossy(), cases.join(", ")));
            }
            ScSpecEntry::UdtErrorEnumV0(e) => {
                let cases: Vec<String> = e.cases.iter().map(|c| format!("{} = {}", c.name.to_utf8_string_lossy(), c.value)).collect();
                spec.lines.push(format!("error {} {{ {} }}", e.name.to_utf8_string_lossy(), cases.join(", ")));
            }
            ScSpecEntry::EventV0(e) => spec.lines.push(format!("event {}", e.name.to_utf8_string_lossy())),
        }
    }
    spec
}

fn ty(t: &ScSpecTypeDef) -> String {
    use ScSpecTypeDef::*;
    match t {
        Val => "Val".into(),
        Bool => "bool".into(),
        Void => "()".into(),
        Error => "Error".into(),
        U32 => "u32".into(),
        I32 => "i32".into(),
        U64 => "u64".into(),
        I64 => "i64".into(),
        Timepoint => "Timepoint".into(),
        Duration => "Duration".into(),
        U128 => "u128".into(),
        I128 => "i128".into(),
        U256 => "U256".into(),
        I256 => "I256".into(),
        Bytes => "Bytes".into(),
        String => "String".into(),
        Symbol => "Symbol".into(),
        Address => "Address".into(),
        MuxedAddress => "MuxedAddress".into(),
        Option(o) => format!("Option<{}>", ty(&o.value_type)),
        Result(r) => format!("Result<{}, {}>", ty(&r.ok_type), ty(&r.error_type)),
        Vec(v) => format!("Vec<{}>", ty(&v.element_type)),
        Map(m) => format!("Map<{}, {}>", ty(&m.key_type), ty(&m.value_type)),
        Tuple(t) => format!("({})", t.value_types.iter().map(ty).collect::<std::vec::Vec<_>>().join(", ")),
        BytesN(b) => format!("BytesN<{}>", b.n),
        Udt(u) => u.name.to_utf8_string_lossy(),
    }
}

/// `PairKey` -> `pair_key`: a value named after the struct it is.
pub fn snake(s: &str) -> String {
    let mut o = String::new();
    for (i, c) in s.chars().enumerate() {
        if c.is_ascii_uppercase() && i > 0 {
            o.push('_');
        }
        o.push(c.to_ascii_lowercase());
    }
    o
}
