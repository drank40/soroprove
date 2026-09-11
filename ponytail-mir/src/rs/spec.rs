//! contractspecv0 as the emitter sees it: types, cases, fields, signatures; keys and texts by rodata position.
use std::collections::HashMap;


/// What `contractspecv0` declares, recovered from the lines ponytail-wasm
/// rendered: enough to name error codes, enum discriminants, union cases and
/// export signatures. The shapes are ScVal shapes, not memory layout.
#[derive(Default)]
pub struct Spec {
    /// `fn name(..) -> ..` lines, by function name.
    pub(super) sigs: HashMap<String, String>,
    /// Function -> the declared type of each parameter.
    pub(super) params: HashMap<String, Vec<String>>,
    /// Integer enum -> (case, value).
    pub(super) enums: HashMap<String, Vec<(String, u32)>>,
    /// (error enum, case, value).
    pub(super) errors: Vec<(String, String, u32)>,
    /// (union, case name).
    pub(super) union_cases: Vec<(String, String)>,
    /// Struct -> field names, in declaration order.
    pub(super) struct_fields: HashMap<String, Vec<String>>,
    /// Map key names by their rodata position (`soroban.keys`).
    pub(super) keys: HashMap<u64, Vec<String>>,
    /// Symbol and string texts by their rodata position (`soroban.strings`).
    pub(super) strings: HashMap<u64, String>,
    /// The read-only data segments (`soroban.rodata`), base and bytes.
    pub(super) rodata: Vec<(u64, Vec<u8>)>,
    /// Function -> the SDK function its fingerprint says it is (`sdk.name`).
    pub(super) sdk: HashMap<String, String>,
}

/// Split on `sep` outside any brackets.
pub(super) fn split_top(s: &str, sep: char) -> Vec<String> {
    let (mut depth, mut cur, mut out) = (0i32, String::new(), Vec::new());
    for c in s.chars() {
        match c {
            '(' | '<' | '{' => depth += 1,
            ')' | '>' | '}' => depth -= 1,
            _ => {}
        }
        if c == sep && depth == 0 {
            out.push(cur.trim().to_string());
            cur.clear();
        } else {
            cur.push(c);
        }
    }
    if !cur.trim().is_empty() {
        out.push(cur.trim().to_string());
    }
    out
}

impl Spec {
    pub fn parse(lines: Vec<String>, key_lines: Vec<String>, string_lines: Vec<String>, rodata_lines: Vec<String>, sdk_lines: Vec<String>) -> Spec {
        let mut s = Spec::default();
        s.sdk = sdk_lines.iter().filter_map(|l| l.split_once(' ')).map(|(f, n)| (f.to_string(), n.to_string())).collect();
        for l in rodata_lines {
            if let Some((base, hex)) = l.split_once(' ') {
                let bytes: Vec<u8> = (0..hex.len() / 2).filter_map(|i| u8::from_str_radix(&hex[2 * i..2 * i + 2], 16).ok()).collect();
                if let Ok(base) = base.parse() {
                    s.rodata.push((base, bytes));
                }
            }
        }
        for l in key_lines {
            let mut it = l.split(' ');
            if let Some(pos) = it.next().and_then(|p| p.parse().ok()) {
                s.keys.insert(pos, it.map(str::to_string).collect());
            }
        }
        for l in string_lines {
            if let Some((pos, text)) = l.split_once(' ') {
                if let Ok(pos) = pos.parse() {
                    s.strings.insert(pos, text.to_string());
                }
            }
        }
        let body = |l: &str| -> (String, Vec<String>) {
            let name = l.split_whitespace().nth(1).unwrap_or("").trim_end_matches('{').to_string();
            let inner = l.find('{').map(|i| &l[i + 1..l.rfind('}').unwrap_or(l.len())]).unwrap_or("");
            (name, split_top(inner, ','))
        };
        let cases = |items: &[String]| -> Vec<(String, u32)> {
            items.iter().filter_map(|c| {
                let (n, v) = c.split_once('=')?;
                Some((n.trim().to_string(), v.trim().parse().ok()?))
            }).collect()
        };
        for l in lines {
            if let Some(rest) = l.strip_prefix("fn ") {
                let name = rest.split('(').next().unwrap_or("").to_string();
                // The parameter list: up to the paren matching the first one,
                // not the last paren of the line (the return type has its own).
                let inner = rest.find('(').map(|i| {
                    let (mut depth, mut end) = (0i32, rest.len());
                    for (j, c) in rest[i..].char_indices() {
                        depth += match c {
                            '(' => 1,
                            ')' => -1,
                            _ => 0,
                        };
                        if depth == 0 {
                            end = i + j;
                            break;
                        }
                    }
                    &rest[i + 1..end]
                }).unwrap_or("");
                let types = split_top(inner, ',').iter().map(|p| p.split_once(": ").map(|(_, t)| t.to_string()).unwrap_or_default()).collect();
                s.params.insert(name.clone(), types);
                s.sigs.insert(name, l.clone());
            } else if l.starts_with("enum ") {
                let (name, items) = body(&l);
                s.enums.insert(name, cases(&items));
            } else if l.starts_with("error ") {
                let (name, items) = body(&l);
                s.errors.extend(cases(&items).into_iter().map(|(c, v)| (name.clone(), c, v)));
            } else if l.starts_with("union ") {
                let (name, items) = body(&l);
                s.union_cases.extend(items.iter().map(|c| (name.clone(), c.split('(').next().unwrap_or(c).to_string())));
            } else if l.starts_with("struct ") {
                let (name, items) = body(&l);
                s.struct_fields.insert(name, items.iter().map(|f| f.split(':').next().unwrap_or(f).trim().to_string()).collect());
            }
        }
        s
    }

    /// The struct whose field set is exactly these keys, if there is one.
    /// The union whose cases are exactly these names, if there is one.
    pub(super) fn union_for_cases(&self, names: &[String]) -> Option<&str> {
        let mut want: Vec<&str> = names.iter().map(String::as_str).collect();
        want.sort();
        let mut unions: Vec<&str> = self.union_cases.iter().map(|(u, _)| u.as_str()).collect();
        unions.dedup();
        let mut it = unions.into_iter().filter(|u| {
            let mut have: Vec<&str> = self.union_cases.iter().filter(|(n, _)| n == u).map(|(_, c)| c.as_str()).collect();
            have.sort();
            have == want
        });
        match (it.next(), it.next()) {
            (Some(u), None) => Some(u),
            _ => None,
        }
    }

    pub(super) fn struct_for_keys(&self, keys: &[String]) -> Option<&str> {
        let mut want: Vec<&str> = keys.iter().map(String::as_str).collect();
        want.sort();
        let mut it = self.struct_fields.iter().filter(|(_, fs)| {
            let mut have: Vec<&str> = fs.iter().map(String::as_str).collect();
            have.sort();
            have == want
        });
        match (it.next(), it.next()) {
            (Some((n, _)), None) => Some(n.as_str()),
            _ => None,
        }
    }

    /// The text at a read-only data position, when the data is there.
    pub(super) fn text_at(&self, pos: u64, len: u64) -> Option<String> {
        self.rodata.iter().find_map(|(base, d)| {
            let off = pos.checked_sub(*base)? as usize;
            let bytes = d.get(off..off.checked_add(len as usize)?)?;
            Some(String::from_utf8_lossy(bytes).into_owned())
        })
    }

    /// `Error::AnError` for a contract error code, when exactly one case has it.
    pub(super) fn error_name(&self, code: u64) -> Option<String> {
        let mut it = self.errors.iter().filter(|(_, _, v)| *v as u64 == code);
        match (it.next(), it.next()) {
            (Some((e, c, _)), None) => Some(format!("{e}::{c}")),
            _ => None,
        }
    }

    /// `DataKey::Pair` for a symbol that is exactly one union's case name.
    pub(super) fn union_case(&self, sym: &str) -> Option<String> {
        let mut it = self.union_cases.iter().filter(|(_, c)| c == sym);
        match (it.next(), it.next()) {
            (Some((u, c)), None) => Some(format!("{u}::{c}")),
            _ => None,
        }
    }

    /// The enum a function's parameter is declared as, if it is an integer enum.
    pub(super) fn param_enum(&self, f: &str, i: usize) -> Option<&str> {
        let t = self.params.get(f)?.get(i)?;
        self.enums.contains_key(t).then_some(t.as_str())
    }

    pub(super) fn enum_case(&self, e: &str, v: u64) -> Option<&str> {
        self.enums.get(e)?.iter().find(|(_, x)| *x as u64 == v).map(|(c, _)| c.as_str())
    }
}
