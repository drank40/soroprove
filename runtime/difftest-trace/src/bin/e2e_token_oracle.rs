//! End-to-end oracle for the soroban-examples token contract: runs the real
//! soroban-env-host v30 `invoke_host_function` on upload, create (with constructor),
//! mint, transfer, an overdrafting transfer and balance reads, carrying the ledger
//! state between invocations. Prints every input blob and every observable output.
use soroban_env_host::{budget::Budget, e2e_invoke::{invoke_host_function, entry_size_for_rent, TtlLedgerEntryMeta}, xdr::*, LedgerInfo};
use sha2v::{Digest, Sha256};
use std::collections::BTreeMap;

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

fn network_id() -> [u8; 32] { Sha256::digest(b"Public Global Stellar Network ; September 2015").into() }

fn ledger_info(net: &Net, seq: u32) -> LedgerInfo {
    LedgerInfo { protocol_version: 30, sequence_number: seq, timestamp: 1_700_000_000, network_id: network_id(),
        base_reserve: 5_000_000, min_temp_entry_ttl: net.sa.min_temporary_ttl, min_persistent_entry_ttl: net.sa.min_persistent_ttl,
        max_entry_ttl: net.sa.max_entry_ttl }
}

type State = BTreeMap<Vec<u8>, (LedgerEntry, Option<u32>)>;

/// Run one invocation with the given footprint (entries taken from `state`), print
/// everything under `tag`, and apply the ledger changes to `state`.
fn run(tag: &str, net: &Net, li: &LedgerInfo, hf: &HostFunction, ro: Vec<LedgerKey>, rw: Vec<LedgerKey>,
       auth: Vec<SorobanAuthorizationEntry>, state: &mut State) {
    eprintln!("RUN {tag}");
    let budget = Budget::try_from_configs(net.cpu_limit, net.mem_limit, net.cpu.clone(), net.mem.clone()).unwrap();
    let fp = LedgerFootprint { read_only: ro.clone().try_into().unwrap(), read_write: rw.clone().try_into().unwrap() };
    let res = SorobanResources { footprint: fp, instructions: net.cpu_limit as u32, disk_read_bytes: 1_000_000, write_bytes: 1_000_000 };
    let src = AccountId(PublicKey::PublicKeyTypeEd25519(Uint256([7u8; 32])));
    let hf_x = x(hf); let res_x = x(&res); let src_x = x(&src);
    let sz_budget = Budget::try_from_configs(u64::MAX, u64::MAX, net.cpu.clone(), net.mem.clone()).unwrap();
    let keys: Vec<LedgerKey> = ro.iter().chain(rw.iter()).cloned().collect();
    let ents: Vec<Option<(Vec<u8>, Option<TtlLedgerEntryMeta>)>> = keys.iter().map(|k| state.get(&x(k)).map(|(e, ttl)| {
        let ex = x(e);
        let sz = entry_size_for_rent(&sz_budget, e, ex.len() as u32).unwrap();
        (ex, ttl.map(|t| TtlLedgerEntryMeta { live_until_ledger: t, entry_size_for_rent: sz })) })).collect();
    let auth_x: Vec<Vec<u8>> = auth.iter().map(|a| x(a)).collect();
    println!("{tag} input host_fn {}", hex(&hf_x));
    println!("{tag} input resources {}", hex(&res_x));
    println!("{tag} input source {}", hex(&src_x));
    for a in &auth_x { println!("{tag} input auth {}", hex(a)); }
    for o in &ents { match o { Some((e, t)) => println!("{tag} input entry {} ttl={:?} rent_size={:?}", hex(e), t.as_ref().map(|t| t.live_until_ledger), t.as_ref().map(|t| t.entry_size_for_rent)), None => println!("{tag} input entry - ttl=None rent_size=None") } }
    println!("{tag} input ledger seq={} proto={} ts={} reserve={} min_temp={} min_pers={} max_ttl={} nid={}", li.sequence_number,
        li.protocol_version, li.timestamp, li.base_reserve, li.min_temp_entry_ttl, li.min_persistent_entry_ttl, li.max_entry_ttl, hex(&li.network_id));
    let mut diag = vec![];
    let ents_in = ents.iter().map(|o| match o { Some((e, t)) => (Some(e.clone()), *t), None => (None, None) });
    let r = invoke_host_function(&budget, false, hf_x.clone(), res_x.clone(), &[], src_x.clone(), auth_x.iter().cloned(),
        li.clone(), ents_in, [0u8; 32].to_vec(), &mut diag, None, None).unwrap();
    match &r.encoded_invoke_result {
        Ok(b) => println!("{tag} output result ok {}", hex(b)),
        Err(e) => println!("{tag} output result err {:?}", e.error),
    }
    for c in &r.ledger_changes {
        println!("{tag} output change ro={} key={} old_size={} new={} new_size={} ttl={:?}", c.read_only, hex(&c.encoded_key),
            c.old_entry_size_bytes_for_rent, c.encoded_new_value.as_ref().map(|v| hex(v)).unwrap_or("-".into()),
            c.new_entry_size_bytes_for_rent, c.ttl_change.as_ref().map(|t| (t.old_live_until_ledger, t.new_live_until_ledger)));
        if let Some(v) = &c.encoded_new_value {
            let e = LedgerEntry::from_xdr(v, lim()).unwrap();
            let ttl = c.ttl_change.as_ref().map(|t| t.new_live_until_ledger);
            state.insert(c.encoded_key.clone(), (e, ttl));
        } else if let Some(t) = &c.ttl_change {
            if let Some(ent) = state.get_mut(&c.encoded_key) { ent.1 = Some(t.new_live_until_ledger); }
        }
    }
    for e in &r.encoded_contract_events { println!("{tag} output event {}", hex(e)); }
    println!("{tag} output budget cpu={} mem={}", budget.get_cpu_insns_consumed().unwrap(), budget.get_mem_bytes_consumed().unwrap());
    for ct in ContractCostType::variants() {
        let t = budget.get_tracker(ct).unwrap();
        if t.iterations > 0 { println!("{tag} tracker {:?} it={} in={:?} cpu={} mem={}", ct, t.iterations, t.inputs, t.cpu, t.mem); }
    }
}

fn acct(b: u8) -> ScAddress { ScAddress::Account(AccountId(PublicKey::PublicKeyTypeEd25519(Uint256([b; 32])))) }
fn i128v(v: i128) -> ScVal { ScVal::I128(Int128Parts { hi: (v >> 64) as i64, lo: v as u64 }) }
fn sym(s: &str) -> ScVal { ScVal::Symbol(ScSymbol(s.try_into().unwrap())) }
fn balance_key(contract: &ScAddress, a: &ScAddress) -> LedgerKey {
    LedgerKey::ContractData(LedgerKeyContractData { contract: contract.clone(),
        key: ScVal::Vec(Some(vec![sym("Balance"), ScVal::Address(a.clone())].try_into().unwrap())),
        durability: ContractDataDurability::Persistent })
}
fn src_auth(f: SorobanAuthorizedFunction) -> SorobanAuthorizationEntry {
    SorobanAuthorizationEntry { credentials: SorobanCredentials::SourceAccount,
        root_invocation: SorobanAuthorizedInvocation { function: f, sub_invocations: vec![].try_into().unwrap() } }
}
fn call(contract: &ScAddress, f: &str, args: Vec<ScVal>) -> InvokeContractArgs {
    InvokeContractArgs { contract_address: contract.clone(), function_name: f.try_into().unwrap(), args: args.try_into().unwrap() }
}

fn main() {
    let wasm = std::fs::read("../corpus/examples/soroban_token_contract.wasm").unwrap();
    let net = load_net();
    let mut state: State = BTreeMap::new();
    let hash = Hash(Sha256::digest(&wasm).into());
    let code_key = LedgerKey::ContractCode(LedgerKeyContractCode { hash: hash.clone() });
    let a = acct(7);
    let b = acct(9);
    // upload
    run("upload", &net, &ledger_info(&net, 1000), &HostFunction::UploadContractWasm(wasm.clone().try_into().unwrap()),
        vec![], vec![code_key.clone()], vec![], &mut state);
    // create with constructor (admin = a, the transaction source)
    let preimage = ContractIdPreimage::Address(ContractIdPreimageFromAddress { address: a.clone(), salt: Uint256([0x22; 32]) });
    let cid_pre = HashIdPreimage::ContractId(HashIdPreimageContractId { network_id: Hash(network_id()), contract_id_preimage: preimage.clone() });
    let cid = ContractId(Hash(Sha256::digest(&x(&cid_pre)).into()));
    let contract = ScAddress::Contract(cid.clone());
    let inst_key = LedgerKey::ContractData(LedgerKeyContractData { contract: contract.clone(), key: ScVal::LedgerKeyContractInstance, durability: ContractDataDurability::Persistent });
    let ctor_args = vec![ScVal::Address(a.clone()), ScVal::U32(7), ScVal::String(ScString("Token".try_into().unwrap())), ScVal::String(ScString("TOK".try_into().unwrap()))];
    let create = CreateContractArgsV2 { contract_id_preimage: preimage, executable: ContractExecutable::Wasm(hash.clone()), constructor_args: ctor_args.try_into().unwrap() };
    run("create", &net, &ledger_info(&net, 1001), &HostFunction::CreateContractV2(create.clone()), vec![code_key.clone()], vec![inst_key.clone()],
        vec![src_auth(SorobanAuthorizedFunction::CreateContractV2HostFn(create))], &mut state);
    let bal_a = balance_key(&contract, &a);
    let bal_b = balance_key(&contract, &b);
    // mint 1000 to a
    let mint = call(&contract, "mint", vec![ScVal::Address(a.clone()), i128v(1000)]);
    run("mint", &net, &ledger_info(&net, 1002), &HostFunction::InvokeContract(mint.clone()), vec![code_key.clone()], vec![inst_key.clone(), bal_a.clone()],
        vec![src_auth(SorobanAuthorizedFunction::ContractFn(mint))], &mut state);
    // transfer 300 a -> b
    let tr = call(&contract, "transfer", vec![ScVal::Address(a.clone()), ScVal::Address(b.clone()), i128v(300)]);
    run("transfer", &net, &ledger_info(&net, 1003), &HostFunction::InvokeContract(tr.clone()), vec![code_key.clone()], vec![inst_key.clone(), bal_a.clone(), bal_b.clone()],
        vec![src_auth(SorobanAuthorizedFunction::ContractFn(tr))], &mut state);
    // overdraft: transfer 10^6 a -> b (a has 700)
    let od = call(&contract, "transfer", vec![ScVal::Address(a.clone()), ScVal::Address(b.clone()), i128v(1_000_000)]);
    run("overdraft", &net, &ledger_info(&net, 1004), &HostFunction::InvokeContract(od.clone()), vec![code_key.clone()], vec![inst_key.clone(), bal_a.clone(), bal_b.clone()],
        vec![src_auth(SorobanAuthorizedFunction::ContractFn(od))], &mut state);
    // balances
    for (tag, who, k) in [("balance_a", &a, &bal_a), ("balance_b", &b, &bal_b)] {
        let q = call(&contract, "balance", vec![ScVal::Address(who.clone())]);
        run(tag, &net, &ledger_info(&net, 1005), &HostFunction::InvokeContract(q), vec![code_key.clone()], vec![inst_key.clone(), k.clone()], vec![], &mut state);
    }
}
