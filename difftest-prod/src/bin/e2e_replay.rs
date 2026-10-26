//! Replays every invocation in an oracle file (`e2e_*_oracle` output) on the production
//! build of soroban-env-host and prints its outputs in the oracle's format.
//! Usage: e2e_replay ORACLE_FILE
use soroban_env_host::{budget::Budget, e2e_invoke::{invoke_host_function, TtlLedgerEntryMeta}, xdr::*, LedgerInfo};

fn unhex(s: &str) -> Vec<u8> { (0..s.len() / 2).map(|i| u8::from_str_radix(&s[2 * i..2 * i + 2], 16).unwrap()).collect() }
fn hex(b: &[u8]) -> String { b.iter().map(|x| format!("{x:02x}")).collect() }
fn opt(s: &str, p: &str) -> Option<u32> { s.strip_prefix(p).and_then(|r| r.strip_prefix("Some(")).map(|r| r.trim_end_matches(')').parse().unwrap()) }

#[derive(Default)]
struct Inp { hf: Vec<u8>, res: Vec<u8>, src: Vec<u8>, auth: Vec<Vec<u8>>, ents: Vec<(Option<Vec<u8>>, Option<TtlLedgerEntryMeta>)>, li: Option<LedgerInfo> }

fn main() {
    let path = std::env::args().nth(1).expect("usage: e2e_replay ORACLE_FILE");
    let text = std::fs::read_to_string(path).unwrap();
    let b64 = std::fs::read_to_string("../vendor/network/mainnet_settings.xdr").unwrap();
    let set = ConfigUpgradeSet::from_xdr_base64(b64.trim(), Limits::none()).unwrap();
    let (mut cpu, mut mem, mut cl, mut ml) = (None, None, 0, 0);
    for e in set.updated_entry.iter() {
        match e {
            ConfigSettingEntry::ContractCostParamsCpuInstructions(p) => cpu = Some(p.clone()),
            ConfigSettingEntry::ContractCostParamsMemoryBytes(p) => mem = Some(p.clone()),
            ConfigSettingEntry::ContractComputeV0(c) => { cl = c.tx_max_instructions as u64; ml = c.tx_memory_limit as u64; }
            _ => {}
        }
    }
    let (cpu, mem) = (cpu.unwrap(), mem.unwrap());
    let mut order: Vec<String> = vec![];
    let mut inps: std::collections::HashMap<String, Inp> = Default::default();
    for l in text.lines() {
        let w: Vec<&str> = l.split(' ').collect();
        if w.len() < 3 || w[1] != "input" { continue; }
        let tag = w[0].to_string();
        if !inps.contains_key(&tag) { order.push(tag.clone()); }
        let i = inps.entry(tag).or_default();
        match w[2] {
            "host_fn" => i.hf = unhex(w[3]),
            "resources" => i.res = unhex(w[3]),
            "source" => i.src = unhex(w[3]),
            "auth" => i.auth.push(unhex(w[3])),
            "entry" => {
                let e = if w[3] == "-" { None } else { Some(unhex(w[3])) };
                let t = match (opt(w[4], "ttl="), opt(w[5], "rent_size=")) {
                    (Some(a), Some(b)) => Some(TtlLedgerEntryMeta { live_until_ledger: a, entry_size_for_rent: b }), _ => None };
                i.ents.push((e, t));
            }
            "ledger" => {
                let kv = |k: &str| w[3..].iter().find_map(|x| x.strip_prefix(&format!("{k}="))).unwrap();
                let nid: [u8; 32] = unhex(kv("nid")).try_into().unwrap();
                i.li = Some(LedgerInfo { protocol_version: kv("proto").parse().unwrap(), sequence_number: kv("seq").parse().unwrap(),
                    timestamp: kv("ts").parse().unwrap(), network_id: nid, base_reserve: kv("reserve").parse().unwrap(),
                    min_temp_entry_ttl: kv("min_temp").parse().unwrap(), min_persistent_entry_ttl: kv("min_pers").parse().unwrap(),
                    max_entry_ttl: kv("max_ttl").parse().unwrap() });
            }
            _ => {}
        }
    }
    for tag in order {
        let i = &inps[&tag];
        let budget = Budget::try_from_configs(cl, ml, cpu.clone(), mem.clone()).unwrap();
        let mut diag = vec![];
        let r = invoke_host_function(&budget, false, i.hf.clone(), i.res.clone(), &[], i.src.clone(), i.auth.iter().cloned(),
            i.li.clone().unwrap(), i.ents.iter().cloned(), [0u8; 32].to_vec(), &mut diag, None, None).unwrap();
        match &r.encoded_invoke_result {
            Ok(b) => println!("{tag} output result ok {}", hex(b)),
            Err(e) => println!("{tag} output result err {:?}", e.error),
        }
        for c in &r.ledger_changes {
            println!("{tag} output change ro={} key={} old_size={} new={} new_size={} ttl={:?}", c.read_only, hex(&c.encoded_key),
                c.old_entry_size_bytes_for_rent, c.encoded_new_value.as_ref().map(|v| hex(v)).unwrap_or("-".into()),
                c.new_entry_size_bytes_for_rent, c.ttl_change.as_ref().map(|t| (t.old_live_until_ledger, t.new_live_until_ledger)));
        }
        for e in &r.encoded_contract_events { println!("{tag} output event {}", hex(e)); }
        println!("{tag} output budget cpu={} mem={}", budget.get_cpu_insns_consumed().unwrap(), budget.get_mem_bytes_consumed().unwrap());
    }
}
