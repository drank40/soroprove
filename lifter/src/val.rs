//! Val constants decoded: tags, small symbols, names for values.


pub(crate) const SMALL_TAGS: [&str; 15] = [
    "False", "True", "Void", "Error", "U32Val", "I32Val", "U64Small", "I64Small", "TimepointSmall",
    "DurationSmall", "U128Small", "I128Small", "U256Small", "I256Small", "SymbolSmall",
];

pub(crate) fn decode_symbol_small(body: u64) -> Option<String> {
    let mut s = String::new();
    for i in (0..9).rev() {
        let c = ((body >> (i * 6)) & 0x3f) as u8;
        if c == 0 {
            continue;
        }
        s.push(match c {
            1 => '_',
            2..=11 => (b'0' + c - 2) as char,
            12..=37 => (b'A' + c - 12) as char,
            38..=63 => (b'a' + c - 38) as char,
            _ => return None,
        });
    }
    (!s.is_empty()).then_some(s)
}

/// What a `Val`-typed constant actually means.
pub fn explain_val(payload: u64) -> String {
    let tag = (payload & 0xff) as usize;
    let body = payload >> 8;
    match tag {
        0 => "false".into(),
        1 => "true".into(),
        2 => "void".into(),
        3 => format!("Error(type {}, code {})", body & 0xff_ffff, body >> 24),
        4 => format!("u32 {}", body >> 24),
        5 => format!("i32 {}", (body >> 24) as i32),
        14 => decode_symbol_small(body & 0x3f_ffff_ffff_ffff)
            .map(|s| format!("Symbol({s:?})"))
            .unwrap_or_else(|| "SymbolSmall(?)".into()),
        t if t < 15 => format!("{} {}", SMALL_TAGS[t], body),
        t if (64..79).contains(&t) => format!("object handle {} (frame-relative)", body >> 24),
        t => format!("BAD tag {t}"),
    }
}

/// Text as an LLVM-safe SSA name.
pub(crate) fn ident(s: &str) -> String {
    let mut o: String = s.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '_' }).collect();
    o.truncate(40);
    o
}

/// The decode, as an LLVM-safe SSA name. inkwell emits no comments, so the
/// meaning rides on the value name instead -- which is strictly better: it is
/// machine-readable and survives optimisation passes.
pub(crate) fn val_name(payload: u64) -> String {
    ident(&format!("v_{}", explain_val(payload)))
}

/// `StorageType` is not a `Val` -- it is a direct-marshalled u64 with three
/// legal values. Naming them is the difference between `i64 1` and `Persistent`.
pub(crate) fn storage_name(c: i64) -> String {
    match c {
        0 => "Temporary".into(),
        1 => "Persistent".into(),
        2 => "Instance".into(),
        // Not a value the host accepts; say so rather than inventing a name.
        n => format!("StorageType_invalid_{n}"),
    }
}
