//! End-to-end oracle: runs the real soroban-env-host v30 `invoke_host_function`
//! (src: soroban-env-host/src/e2e_invoke.rs:470-589) on a scenario and prints
//! every input blob (hex XDR) and every observable output, plus the budget
//! totals and per-cost-type trackers.
use soroban_env_host::{budget::Budget, e2e_invoke::{invoke_host_function, entry_size_for_rent, TtlLedgerEntryMeta}, xdr::*, LedgerInfo};
use sha2v::{Digest, Sha256};

fn hex(b: &[u8]) -> String { b.iter().map(|x| format!("{x:02x}")).collect() }
fn lim() -> Limits { Limits::none() }
fn x<T: WriteXdr>(t: &T) -> Vec<u8> { t.to_xdr(lim()).unwrap() }

struct Net { cpu: ContractCostParams, mem: ContractCostParams, cpu_limit: u64, mem_limit: u64, sa: StateArchivalSettings }

fn load_net() -> Net {
    let b64 = std::fs::read_to_string("../vendor/network/mainnet_settings.xdr").unwrap();
    let set = ConfigUpgradeSet::from_xdr_base64(b64.trim(), lim()).unwrap();
    let (mut cpu, mut mem, mut cl, mut ml, mut sa) = (None, None, 0, 0, None);
    for e in set.updated_entry.iter() {
        match e {
            ConfigSettingEntry::ContractCostParamsCpuInstructions(p) => cpu = Some(p.clone()),
            ConfigSettingEntry::ContractCostParamsMemoryBytes(p) => mem = Some(p.clone()),
            ConfigSettingEntry::ContractComputeV0(c) => { cl = c.tx_max_instructions as u64; ml = c.tx_memory_limit as u64; }
            ConfigSettingEntry::StateArchival(s) => sa = Some(s.clone()),
            _ => {}
        }
    }
    Net { cpu: cpu.unwrap(), mem: mem.unwrap(), cpu_limit: cl, mem_limit: ml, sa: sa.unwrap() }
}

fn ledger_info(net: &Net, seq: u32) -> LedgerInfo {
    let nid: [u8; 32] = Sha256::digest(b"Public Global Stellar Network ; September 2015").into();
    LedgerInfo { protocol_version: 30, sequence_number: seq, timestamp: 1_700_000_000, network_id: nid,
        base_reserve: 5_000_000, min_temp_entry_ttl: net.sa.min_temporary_ttl, min_persistent_entry_ttl: net.sa.min_persistent_ttl,
        max_entry_ttl: net.sa.max_entry_ttl }
}

/// Run one invocation, print inputs and outputs under `tag`, return the ledger changes.
fn run(tag: &str, net: &Net, li: &LedgerInfo, hf: &HostFunction, fp: LedgerFootprint,
       entries: &[Option<(LedgerEntry, Option<u32>)>]) -> Vec<(LedgerKey, Option<LedgerEntry>, Option<u32>)> {
    eprintln!("RUN {tag}");
    let budget = Budget::try_from_configs(net.cpu_limit, net.mem_limit, net.cpu.clone(), net.mem.clone()).unwrap();
    let res = SorobanResources { footprint: fp.clone(), instructions: net.cpu_limit as u32, disk_read_bytes: 1_000_000, write_bytes: 1_000_000 };
    let src = AccountId(PublicKey::PublicKeyTypeEd25519(Uint256([7u8; 32])));
    let hf_x = x(hf); let res_x = x(&res); let src_x = x(&src);
    // entry_size_for_rent as stellar-core computes it (e2e_invoke.rs:427-447), on a separate budget
    let sz_budget = Budget::try_from_configs(u64::MAX, u64::MAX, net.cpu.clone(), net.mem.clone()).unwrap();
    let ents: Vec<Option<(Vec<u8>, Option<TtlLedgerEntryMeta>)>> = entries.iter().map(|o| o.as_ref().map(|(e, ttl)| { let ex = x(e);
        let sz = entry_size_for_rent(&sz_budget, e, ex.len() as u32).unwrap();
        (ex, ttl.map(|t| TtlLedgerEntryMeta { live_until_ledger: t, entry_size_for_rent: sz })) })).collect();
    println!("{tag} input host_fn {}", hex(&hf_x));
    println!("{tag} input resources {}", hex(&res_x));
    println!("{tag} input source {}", hex(&src_x));
    for o in &ents { match o { Some((e, t)) => println!("{tag} input entry {} ttl={:?} rent_size={:?}", hex(e), t.as_ref().map(|t| t.live_until_ledger), t.as_ref().map(|t| t.entry_size_for_rent)), None => println!("{tag} input entry - ttl=None rent_size=None") } }
    println!("{tag} input ledger seq={} proto={} ts={} reserve={} min_temp={} min_pers={} max_ttl={} nid={}", li.sequence_number,
        li.protocol_version, li.timestamp, li.base_reserve, li.min_temp_entry_ttl, li.min_persistent_entry_ttl, li.max_entry_ttl, hex(&li.network_id));
    let mut diag = vec![];
    let ents_in = ents.iter().map(|o| match o { Some((e, t)) => (Some(e.clone()), *t), None => (None, None) });
    let r = invoke_host_function(&budget, false, hf_x.clone(), res_x.clone(), &[], src_x.clone(), std::iter::empty::<Vec<u8>>(),
        li.clone(), ents_in, [0u8; 32].to_vec(), &mut diag, None, None).unwrap();
    match &r.encoded_invoke_result {
        Ok(b) => println!("{tag} output result ok {}", hex(b)),
        Err(e) => println!("{tag} output result err {:?}", e.error),
    }
    let mut out = vec![];
    for c in &r.ledger_changes {
        println!("{tag} output change ro={} key={} old_size={} new={} new_size={} ttl={:?}", c.read_only, hex(&c.encoded_key),
            c.old_entry_size_bytes_for_rent, c.encoded_new_value.as_ref().map(|v| hex(v)).unwrap_or("-".into()),
            c.new_entry_size_bytes_for_rent, c.ttl_change.as_ref().map(|t| (t.old_live_until_ledger, t.new_live_until_ledger)));
        let k = LedgerKey::from_xdr(&c.encoded_key, lim()).unwrap();
        let v = c.encoded_new_value.as_ref().map(|v| LedgerEntry::from_xdr(v, lim()).unwrap());
        out.push((k, v, c.ttl_change.as_ref().map(|t| t.new_live_until_ledger)));
    }
    for e in &r.encoded_contract_events { println!("{tag} output event {}", hex(e)); }
    println!("{tag} output budget cpu={} mem={}", budget.get_cpu_insns_consumed().unwrap(), budget.get_mem_bytes_consumed().unwrap());
    for ct in ContractCostType::variants() {
        let t = budget.get_tracker(ct).unwrap();
        if t.iterations > 0 { println!("{tag} tracker {:?} it={} in={:?} cpu={} mem={}", ct, t.iterations, t.inputs, t.cpu, t.mem); }
    }
    out
}

fn main() {
    let wasm_path = std::env::args().nth(1).unwrap_or("../corpus/examples/soroban_increment_contract.wasm".into());
    let wasm = std::fs::read(&wasm_path).unwrap();
    let net = load_net();
    let li = ledger_info(&net, 1000);
    let hash = Hash(Sha256::digest(&wasm).into());
    let code_key = LedgerKey::ContractCode(LedgerKeyContractCode { hash: hash.clone() });
    // 1. upload
    let up = HostFunction::UploadContractWasm(wasm.clone().try_into().unwrap());
    let ch = run("upload", &net, &li, &up, LedgerFootprint { read_only: vec![].try_into().unwrap(), read_write: vec![code_key.clone()].try_into().unwrap() }, &[None]);
    let (_, code_entry, code_ttl) = ch.into_iter().find(|(k, _, _)| *k == code_key).unwrap();
    let code_entry = code_entry.unwrap();
    // 2. instance entry
    let cid = ContractId(Hash([0x11; 32]));
    let addr = ScAddress::Contract(cid.clone());
    let inst_key = LedgerKey::ContractData(LedgerKeyContractData { contract: addr.clone(), key: ScVal::LedgerKeyContractInstance, durability: ContractDataDurability::Persistent });
    let mut inst_entry = LedgerEntry { last_modified_ledger_seq: 1000, ext: LedgerEntryExt::V0,
        data: LedgerEntryData::ContractData(ContractDataEntry { ext: ExtensionPoint::V0, contract: addr.clone(), key: ScVal::LedgerKeyContractInstance,
            durability: ContractDataDurability::Persistent, val: ScVal::ContractInstance(ScContractInstance { executable: ContractExecutable::Wasm(hash.clone()), storage: None }) }) };
    let mut inst_ttl = Some(li.sequence_number + 1000);
    // 3. three chained invocations
    for i in 0..3 {
        let li = ledger_info(&net, 1000 + i);
        let hf = HostFunction::InvokeContract(InvokeContractArgs { contract_address: addr.clone(), function_name: "increment".try_into().unwrap(), args: vec![].try_into().unwrap() });
        let fp = LedgerFootprint { read_only: vec![code_key.clone()].try_into().unwrap(), read_write: vec![inst_key.clone()].try_into().unwrap() };
        let ch = run(&format!("call{i}"), &net, &li, &hf, fp, &[Some((code_entry.clone(), code_ttl)), Some((inst_entry.clone(), inst_ttl))]);
        if let Some((_, Some(e), t)) = ch.into_iter().find(|(k, _, _)| *k == inst_key) { inst_entry = e; if t.is_some() { inst_ttl = t; } }
    }
}
