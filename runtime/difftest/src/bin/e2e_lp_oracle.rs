//! End-to-end oracle for the soroban-examples liquidity pool: deploys two token
//! contracts and the pool on the real soroban-env-host v30, then runs a seeded random
//! sequence of deposit / swap / withdraw / getter calls, carrying the ledger state.
//! Each call's footprint and auth tree come from a recording-mode run; the enforcing
//! run's inputs and outputs are printed like `e2e_token_oracle` (for the Lean host to
//! replay), plus, for successful pool calls, the before/after state in the key
//! format of stellar-diver's `--lean model` (`<tag> model ...` lines).
//!
//! Usage: e2e_lp_oracle [STEPS] [SEED]
use rand::{Rng, SeedableRng};
use rand_chacha::ChaCha8Rng;
use sha2v::{Digest, Sha256};
use soroban_env_host::{
    budget::Budget,
    e2e_invoke::{entry_size_for_rent, invoke_host_function, invoke_host_function_in_recording_mode,
        RecordingInvocationAuthMode, TtlLedgerEntryMeta},
    storage::{EntryWithLiveUntil, SnapshotSource},
    xdr::*,
    HostError, LedgerInfo,
};
use std::collections::BTreeMap;
use std::rc::Rc;

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
    LedgerInfo { protocol_version: 30, sequence_number: seq, timestamp: 1_700_000_000 + seq as u64, network_id: network_id(),
        base_reserve: 5_000_000, min_temp_entry_ttl: net.sa.min_temporary_ttl, min_persistent_entry_ttl: net.sa.min_persistent_ttl,
        max_entry_ttl: net.sa.max_entry_ttl }
}

type State = BTreeMap<Vec<u8>, (LedgerEntry, Option<u32>)>;

struct Snap(State);
impl SnapshotSource for Snap {
    fn get(&self, key: &Rc<LedgerKey>) -> Result<Option<EntryWithLiveUntil>, HostError> {
        Ok(self.0.get(&x(key.as_ref())).map(|(e, t)| (Rc::new(e.clone()), *t)))
    }
}

fn budget(net: &Net) -> Budget {
    Budget::try_from_configs(net.cpu_limit, net.mem_limit, net.cpu.clone(), net.mem.clone()).unwrap()
}

/// Recording-mode run: the footprint, and the auth entries with every entry for the
/// transaction source turned into `SourceAccount` credentials.
fn record(net: &Net, li: &LedgerInfo, hf: &HostFunction, src: &AccountId, state: &State)
    -> (Vec<LedgerKey>, Vec<LedgerKey>, Vec<SorobanAuthorizationEntry>) {
    let mut diag = vec![];
    let r = invoke_host_function_in_recording_mode(&budget(net), false, hf, src,
        RecordingInvocationAuthMode::recording(false, false), li.clone(), Rc::new(Snap(state.clone())),
        [0u8; 32], &mut diag).unwrap();
    if let Err(e) = &r.invoke_result { eprintln!("recording: {:?}", e.error); }
    let src_addr = ScAddress::Account(src.clone());
    let auth = r.auth.into_iter().map(|mut e| {
        if let SorobanCredentials::Address(c) = &e.credentials {
            if c.address == src_addr { e.credentials = SorobanCredentials::SourceAccount; }
        }
        e
    }).collect();
    (r.resources.footprint.read_only.to_vec(), r.resources.footprint.read_write.to_vec(), auth)
}

/// Enforcing run, printed under `tag`; ledger changes are applied to `state`.
/// Returns whether the invocation succeeded.
fn run(tag: &str, net: &Net, li: &LedgerInfo, hf: &HostFunction, src: &AccountId, ro: Vec<LedgerKey>, rw: Vec<LedgerKey>,
       auth: Vec<SorobanAuthorizationEntry>, state: &mut State) -> bool {
    let budget = budget(net);
    let fp = LedgerFootprint { read_only: ro.clone().try_into().unwrap(), read_write: rw.clone().try_into().unwrap() };
    let res = SorobanResources { footprint: fp, instructions: net.cpu_limit as u32, disk_read_bytes: 1_000_000, write_bytes: 1_000_000 };
    let hf_x = x(hf); let res_x = x(&res); let src_x = x(src);
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
    let ok = r.encoded_invoke_result.is_ok();
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
        } else if !c.read_only {
            state.remove(&c.encoded_key);
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
    ok
}

fn account(b: u8) -> AccountId { AccountId(PublicKey::PublicKeyTypeEd25519(Uint256([b; 32]))) }
fn i128v(v: i128) -> ScVal { ScVal::I128(Int128Parts { hi: (v >> 64) as i64, lo: v as u64 }) }
fn i128of(p: &Int128Parts) -> i128 { ((p.hi as i128) << 64) | p.lo as i128 }
fn sym(s: &str) -> ScVal { ScVal::Symbol(ScSymbol(s.try_into().unwrap())) }
fn call(contract: &ScAddress, f: &str, args: Vec<ScVal>) -> HostFunction {
    HostFunction::InvokeContract(InvokeContractArgs { contract_address: contract.clone(), function_name: f.try_into().unwrap(), args: args.try_into().unwrap() })
}
fn instance_key(c: &ScAddress) -> LedgerKey {
    LedgerKey::ContractData(LedgerKeyContractData { contract: c.clone(), key: ScVal::LedgerKeyContractInstance, durability: ContractDataDurability::Persistent })
}

/// Upload `wasm` and create a contract from it with the given constructor arguments
/// (source and deployer: `admin`); returns its address.
fn deploy(tag: &str, net: &Net, seq: &mut u32, wasm: &[u8], salt: u8, ctor: Vec<ScVal>, admin: &AccountId, state: &mut State) -> ScAddress {
    let hash = Hash(Sha256::digest(wasm).into());
    let code_key = LedgerKey::ContractCode(LedgerKeyContractCode { hash: hash.clone() });
    if !state.contains_key(&x(&code_key)) {
        *seq += 1;
        run(&format!("upload_{tag}"), net, &ledger_info(net, *seq), &HostFunction::UploadContractWasm(wasm.to_vec().try_into().unwrap()),
            admin, vec![], vec![code_key.clone()], vec![], state);
    }
    let preimage = ContractIdPreimage::Address(ContractIdPreimageFromAddress { address: ScAddress::Account(admin.clone()), salt: Uint256([salt; 32]) });
    let create = HostFunction::CreateContractV2(CreateContractArgsV2 { contract_id_preimage: preimage, executable: ContractExecutable::Wasm(hash), constructor_args: ctor.try_into().unwrap() });
    *seq += 1;
    let li = ledger_info(net, *seq);
    let (ro, rw, auth) = record(net, &li, &create, admin, state);
    assert!(run(&format!("create_{tag}"), net, &li, &create, admin, ro, rw, auth, state), "create {tag} failed");
    let HostFunction::CreateContractV2(a) = &create else { unreachable!() };
    let cid_pre = HashIdPreimage::ContractId(HashIdPreimageContractId { network_id: Hash(network_id()), contract_id_preimage: a.contract_id_preimage.clone() });
    ScAddress::Contract(ContractId(Hash(Sha256::digest(&x(&cid_pre)).into())))
}

/// Addresses as the model's `Addr` (an `Int`): 1 + the index in host (`ScAddress`) order.
struct Codes(Vec<ScAddress>);
impl Codes {
    fn of(&self, a: &ScAddress) -> usize { 1 + self.0.iter().position(|b| b == a).expect("unknown address") }
}

/// A stored value as the model's `Int`, if it is one the model represents.
fn val_int(v: &ScVal, codes: &Codes) -> Option<String> {
    match v {
        ScVal::I128(p) => Some(i128of(p).to_string()),
        ScVal::Address(a) => Some(codes.of(a).to_string()),
        ScVal::U32(n) => Some(n.to_string()),
        ScVal::Bool(b) => Some((*b as u8).to_string()),
        _ => None,
    }
}

/// The ledger as the model's storage: the pool's instance storage (`var` / `entry`
/// keys, each with its `has` presence key) and the tokens' `Balance` entries (`bal`).
fn abstract_state(state: &State, pool: &ScAddress, tokens: &[ScAddress], codes: &Codes) -> Vec<(String, String)> {
    let mut out = vec![];
    for (e, _) in state.values() {
        let LedgerEntryData::ContractData(d) = &e.data else { continue };
        if &d.contract == pool {
            // Instance storage is one entry holding a map; persistent and temporary
            // storage are an entry per key. The model doesn't distinguish them.
            let kvs: Vec<(&ScVal, &ScVal)> = match (&d.key, &d.val) {
                (ScVal::LedgerKeyContractInstance, ScVal::ContractInstance(inst)) =>
                    inst.storage.iter().flat_map(|m| m.0.iter()).map(|kv| (&kv.key, &kv.val)).collect(),
                (k, v) => vec![(k, v)],
            };
            for (k, v) in kvs {
                let ScVal::Vec(Some(parts)) = k else { continue };
                let key = match parts.as_slice() {
                    [ScVal::Symbol(n)] => format!("var {}", n.to_utf8_string_lossy()),
                    [ScVal::Symbol(n), ScVal::Address(a)] => format!("entry {} {}", n.to_utf8_string_lossy(), codes.of(a)),
                    _ => continue,
                };
                if let Some(v) = val_int(v, codes) { out.push((key.clone(), v)); }
                out.push((format!("has {key}"), "1".into()));
            }
        } else if tokens.contains(&d.contract) {
            let ScVal::Vec(Some(parts)) = &d.key else { continue };
            if let [ScVal::Symbol(n), ScVal::Address(a)] = parts.as_slice() {
                if n.to_utf8_string_lossy() == "Balance" {
                    if let Some(v) = val_int(&d.val, codes) {
                        out.push((format!("bal {} {}", codes.of(&d.contract), codes.of(a)), v));
                    }
                }
            }
        }
    }
    out
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let steps: usize = args.get(1).map(|s| s.parse().unwrap()).unwrap_or(200);
    let seed: u64 = args.get(2).map(|s| s.parse().unwrap()).unwrap_or(1);
    let mut rng = ChaCha8Rng::seed_from_u64(seed);
    let net = load_net();
    let mut state: State = BTreeMap::new();
    let mut seq = 1000u32;
    let token_wasm = std::fs::read("../corpus/examples/soroban_token_contract.wasm").unwrap();
    let lp_wasm = std::fs::read("../corpus/examples/soroban_liquidity_pool_contract.wasm").unwrap();
    let admin = account(1);
    let users: Vec<AccountId> = (2..5).map(account).collect();
    let tok = |name: &str| vec![ScVal::Address(ScAddress::Account(admin.clone())), ScVal::U32(7),
        ScVal::String(ScString(name.try_into().unwrap())), ScVal::String(ScString(name.try_into().unwrap()))];
    let t1 = deploy("token1", &net, &mut seq, &token_wasm, 0x11, tok("TKA"), &admin, &mut state);
    let t2 = deploy("token2", &net, &mut seq, &token_wasm, 0x12, tok("TKB"), &admin, &mut state);
    // The pool requires token_a < token_b (host order).
    let (ta, tb) = if t1 < t2 { (t1, t2) } else { (t2, t1) };
    let pool = deploy("pool", &net, &mut seq, &lp_wasm, 0x13, vec![ScVal::Address(ta.clone()), ScVal::Address(tb.clone())], &admin, &mut state);

    let mut all: Vec<ScAddress> = vec![ScAddress::Account(admin.clone()), ta.clone(), tb.clone(), pool.clone()];
    all.extend(users.iter().map(|u| ScAddress::Account(u.clone())));
    all.sort();
    let codes = Codes(all);
    for (n, a) in [("admin", ScAddress::Account(admin.clone())), ("tokenA", ta.clone()), ("tokenB", tb.clone()), ("pool", pool.clone())] {
        println!("addr {n} {}", codes.of(&a));
    }

    // Fund the users.
    for (i, u) in users.iter().enumerate() {
        for (j, t) in [&ta, &tb].into_iter().enumerate() {
            seq += 1;
            let li = ledger_info(&net, seq);
            let hf = call(t, "mint", vec![ScVal::Address(ScAddress::Account(u.clone())), i128v(1_000_000_000)]);
            let (ro, rw, auth) = record(&net, &li, &hf, &admin, &state);
            assert!(run(&format!("mint_{i}_{j}"), &net, &li, &hf, &admin, ro, rw, auth, &mut state));
        }
    }

    let (mut n_ok, mut n_err) = (0, 0);
    for step in 0..steps {
        seq += 1;
        let li = ledger_info(&net, seq);
        let u = &users[rng.gen_range(0..users.len())];
        let ua = ScAddress::Account(u.clone());
        // Arguments mostly derived from the current state so calls tend to succeed;
        // one call in five uses unrelated random amounts to exercise the panics.
        let pre = abstract_state(&state, &pool, &[ta.clone(), tb.clone()], &codes);
        let get = |k: &str| -> i128 { pre.iter().find(|(a, _)| a == k).map(|(_, v)| v.parse().unwrap()).unwrap_or(0) };
        let (ra, rb) = (get("var ReserveA"), get("var ReserveB"));
        let shares = get(&format!("entry Shares {}", codes.of(&ua)));
        let junk = rng.gen_range(0..5) == 0;
        let mut r = |lo: i128, hi: i128| -> i128 { if hi <= lo { lo } else { rng.gen_range(lo..hi) } };
        let (f, named): (&str, Vec<(&str, ScVal)>) = match r(0, 10) {
            0..=3 => {
                let da = r(1, 5_000_000);
                let db = if ra > 0 && !junk { (da * rb / ra + r(-2, 3)).max(1) } else { r(1, 5_000_000) };
                let (ma, mb) = if junk { (r(-10, 5_000_000), r(-10, 5_000_000)) } else { (r(0, da / 2 + 1), r(0, db / 2 + 1)) };
                ("deposit", vec![("to", ScVal::Address(ua.clone())), ("desired_a", i128v(da)), ("min_a", i128v(ma)),
                                 ("desired_b", i128v(db)), ("min_b", i128v(mb))])
            }
            4..=6 => {
                let buy_a = r(0, 2) == 1;
                let rout = if buy_a { ra } else { rb };
                let out = if junk { r(-10, 5_000_000) } else { r(1, rout / 3 + 2) };
                let in_max = if junk { r(-10, 5_000_000) } else { r(out, out * 10 + 1000) };
                ("swap", vec![("to", ScVal::Address(ua.clone())), ("buy_a", ScVal::Bool(buy_a)), ("out", i128v(out)), ("in_max", i128v(in_max))])
            }
            7..=8 => {
                let sh = if junk { r(-10, 5_000_000) } else { r(1, shares + 1) };
                let (ma, mb) = if junk { (r(-10, 1_000_000), r(-10, 1_000_000)) } else { (r(0, 2), r(0, 2)) };
                ("withdraw", vec![("to", ScVal::Address(ua.clone())), ("share_amount", i128v(sh)), ("min_a", i128v(ma)), ("min_b", i128v(mb))])
            }
            9 => if rng.gen() { ("get_rsrvs", vec![]) } else { ("balance_shares", vec![("user", ScVal::Address(ua.clone()))]) },
            _ => unreachable!(),
        };
        let hf = call(&pool, f, named.iter().map(|(_, v)| v.clone()).collect());
        let (ro, rw, auth) = record(&net, &li, &hf, u, &state);
        let tag = format!("s{step}");
        let ok = run(&tag, &net, &li, &hf, u, ro, rw, auth.clone(), &mut state);
        if !ok { n_err += 1; continue; }
        n_ok += 1;
        let post = abstract_state(&state, &pool, &[ta.clone(), tb.clone()], &codes);
        println!("{tag} model fn {f}");
        println!("{tag} model caller {}", codes.of(&ua));
        println!("{tag} model self {}", codes.of(&pool));
        for e in &auth {
            let who = match &e.credentials { SorobanCredentials::SourceAccount => ua.clone(),
                SorobanCredentials::Address(c) => c.address.clone(), SorobanCredentials::AddressV2(c) => c.address.clone(), _ => continue };
            println!("{tag} model signer {}", codes.of(&who));
        }
        println!("{tag} model env sequence {}", li.sequence_number);
        println!("{tag} model env timestamp {}", li.timestamp);
        for (n, v) in &named {
            match v {
                ScVal::Address(a) => println!("{tag} model argA {n} {}", codes.of(a)),
                _ => println!("{tag} model arg {n} {}", val_int(v, &codes).unwrap()),
            }
        }
        for (k, v) in &pre { println!("{tag} model pre {k} {v}"); }
        for (k, v) in &post { println!("{tag} model post {k} {v}"); }
    }
    eprintln!("{steps} pool calls: {n_ok} succeeded, {n_err} failed");
}
