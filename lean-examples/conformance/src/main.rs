//! Conformance harness for the `--lean model`s in `lean-examples/`.
//!
//! Runs each example contract's real wasm in the Soroban test VM under random
//! invocations and records every SUCCESSFUL one as a concrete `Step` (call,
//! signers, ledger info, storage and token balances before and after, return
//! value), written as Lean data. `check.lean` then evaluates the model's own
//! conjuncts and post state on each: a step the model does not admit is a bug
//! in the model (the over-approximation claim failing), reported per entrypoint.
//!
//!   conformance <soroban-examples dir> <out dir> [runs]

use soroban_sdk::testutils::{Address as _, Ledger};
use soroban_sdk::token::{StellarAssetClient, TokenClient};
use soroban_sdk::xdr::{LedgerEntryData, ScAddress, ScVal};
use soroban_sdk::{Address, Env, IntoVal, String as SString, Symbol, TryFromVal, Val};
use std::collections::BTreeMap;
use std::fmt::Write as _;

/// Storage and balances at one point: model keys (as Lean source) -> value.
#[derive(Clone, Default)]
struct Snap {
    vals: BTreeMap<String, i128>, // present values (struct fields flattened), `.has k` bits, balances
    roots: Vec<String>,           // present root keys
}

struct Obs {
    entry: String,
    me: ScAddress, // the contract instance called
    args: Vec<(String, ScVal)>,
    signers: Vec<ScAddress>,
    seq: u32,
    ts: u64,
    pre: Snap,
    post: Snap,
    ret: ScVal,
}

/// One contract under test, with its environment and what has been observed.
struct World {
    env: Env,
    id: Address,
    tokens: Vec<Address>,
    users: Vec<Address>,
    instances: Vec<Address>, // earlier instances of the contract (re-registered)
    caller: Address,
    rng: u64,
    obs: Vec<Obs>,
    ids: BTreeMap<ScAddress, i128>, // filled at emission (host order)
    tried: usize,
}

fn sc_addr(env: &Env, a: &Address) -> ScAddress {
    match ScVal::try_from_val(env, &a.to_val()).unwrap() {
        ScVal::Address(a) => a,
        _ => unreachable!(),
    }
}

impl World {
    fn new(seed: u64) -> World {
        let env = Env::default();
        env.mock_all_auths();
        let caller = Address::generate(&env);
        World { id: caller.clone(), env, tokens: vec![], users: vec![], instances: vec![], caller, rng: seed | 1, obs: vec![], ids: BTreeMap::new(), tried: 0 }
    }

    fn rand(&mut self, n: u64) -> u64 {
        self.rng ^= self.rng << 13;
        self.rng ^= self.rng >> 7;
        self.rng ^= self.rng << 17;
        self.rng % n.max(1)
    }
    fn user(&mut self) -> Address {
        let k = self.rand(self.users.len() as u64) as usize;
        self.users[k].clone()
    }
    fn amount(&mut self) -> i128 {
        match self.rand(10) {
            0 => -(self.rand(100) as i128),
            1 => 0,
            2 => 10_000_000 + self.rand(1000) as i128,
            _ => self.rand(2_000) as i128,
        }
    }

    fn token(&mut self, holders: &[Address], amount: i128) -> Address {
        let admin = Address::generate(&self.env);
        let t = self.env.register_stellar_asset_contract_v2(admin).address();
        for h in holders {
            StellarAssetClient::new(&self.env, &t).mint(h, &amount);
        }
        self.tokens.push(t.clone());
        t
    }

    fn advance(&mut self, ledgers: u32, secs: u64) {
        self.env.ledger().with_mut(|l| {
            l.sequence_number += ledgers;
            l.timestamp += secs;
        });
    }

    /// The contract's storage and every (token, address) balance, as model keys.
    fn snap(&self) -> Snap {
        let me = sc_addr(&self.env, &self.id);
        let mut s = Snap::default();
        let mut durs: BTreeMap<String, String> = BTreeMap::new();
        let mut add = |s: &mut Snap, k: &ScVal, v: &ScVal, dur: &str| {
            let Some(key) = key_lean(k, &self.ids_now()) else { return };
            if let Some(d) = durs.insert(key.clone(), dur.to_string()) {
                assert_eq!(d, dur, "key {key} stored under two durabilities: the model would conflate them");
            }
            flatten(&key, v, &self.ids_now(), &mut s.vals);
            s.vals.insert(format!(".has ({key})"), 1);
            s.roots.push(key);
        };
        let seq = self.env.ledger().sequence();
        for (_, (entry, live_until)) in self.env.to_ledger_snapshot().ledger_entries {
            let LedgerEntryData::ContractData(cd) = &entry.data else { continue };
            if cd.contract != me {
                continue;
            }
            // an expired temporary entry is gone (the host reads it as absent).
            if cd.durability == soroban_sdk::xdr::ContractDataDurability::Temporary && live_until.is_some_and(|l| l < seq) {
                continue;
            }
            match (&cd.key, &cd.val) {
                (ScVal::LedgerKeyContractInstance, ScVal::ContractInstance(inst)) => {
                    for e in inst.storage.iter().flat_map(|m| m.0.iter()) {
                        add(&mut s, &e.key, &e.val, "instance");
                    }
                }
                (k, v) => add(&mut s, k, v, &format!("{:?}", cd.durability)),
            }
        }
        let mut who = self.users.clone();
        who.push(self.id.clone());
        who.extend(self.instances.iter().cloned());
        who.extend(self.tokens.iter().cloned());
        for t in &self.tokens {
            for a in &who {
                let b = TokenClient::new(&self.env, t).balance(a);
                let (ti, ai) = (addr_lean(&sc_addr(&self.env, t), &self.ids_now()), addr_lean(&sc_addr(&self.env, a), &self.ids_now()));
                s.vals.insert(format!(".bal ({ti}) ({ai})"), b);
            }
        }
        s
    }

    /// Addresses are written symbolically (`@A<n>`) and numbered at emission.
    fn ids_now(&self) -> BTreeMap<ScAddress, i128> {
        BTreeMap::new()
    }

    /// Invoke `f(args)`; a successful call is recorded as an observation.
    fn call(&mut self, f: &str, args: Vec<(&str, Val)>) -> bool {
        self.tried += 1;
        self.env.cost_estimate().budget().reset_unlimited();
        let pre = self.snap();
        let (seq, ts) = (self.env.ledger().sequence(), self.env.ledger().timestamp());
        let vals: Vec<Val> = args.iter().map(|(_, v)| *v).collect();
        let r = self.env.try_invoke_contract::<Val, soroban_sdk::Error>(&self.id, &Symbol::new(&self.env, f), soroban_sdk::Vec::from_slice(&self.env, &vals));
        let Ok(Ok(ret)) = r else { return false };
        let signers: Vec<ScAddress> = self.env.auths().iter().map(|(a, _)| sc_addr(&self.env, a)).collect();
        let post = self.snap();
        let env = &self.env;
        self.obs.push(Obs {
            entry: f.to_string(),
            me: sc_addr(env, &self.id),
            args: args.iter().map(|(n, v)| (n.to_string(), ScVal::try_from_val(env, v).unwrap())).collect(),
            signers,
            seq,
            ts,
            pre,
            post,
            ret: ScVal::try_from_val(env, &ret).unwrap(),
        });
        true
    }

    /// Deploy the contract, recording its constructor as a step (from empty
    /// contract storage; token balances as they are).
    fn construct(&mut self, wasm: &[u8], args: Vec<(&str, Val)>) {
        let vals: Vec<Val> = args.iter().map(|(_, v)| *v).collect();
        self.env.cost_estimate().budget().reset_unlimited();
        self.id = self.env.register(wasm, soroban_sdk::Vec::from_slice(&self.env, &vals));
        let signers: Vec<ScAddress> = self.env.auths().iter().map(|(a, _)| sc_addr(&self.env, a)).collect();
        let post = self.snap();
        let pre = Snap { vals: post.vals.iter().filter(|(k, _)| k.starts_with(".bal")).map(|(k, v)| (k.clone(), *v)).collect(), roots: vec![] };
        let env = &self.env;
        self.obs.push(Obs {
            entry: "__constructor".into(),
            me: sc_addr(env, &self.id),
            args: args.iter().map(|(n, v)| (n.to_string(), ScVal::try_from_val(env, v).unwrap())).collect(),
            signers,
            seq: env.ledger().sequence(),
            ts: env.ledger().timestamp(),
            pre,
            post,
            ret: ScVal::Void,
        });
        self.tried += 1;
    }

    fn v<T: IntoVal<Env, Val>>(&self, x: T) -> Val {
        x.into_val(&self.env)
    }
    fn sv(&self, x: ScVal) -> Val {
        Val::try_from_val(&self.env, &x).unwrap()
    }
}

/// A scalar Val as the model's Int (raw payload for Void/bool, the value for
/// numbers, `@A…` placeholders for addresses); None when the model has no
/// encoding for it (Vec, String, Symbol, enum…).
fn scalar(v: &ScVal) -> Option<String> {
    Some(match v {
        ScVal::Bool(b) => (*b as i32).to_string(),
        ScVal::Void => "2".into(),
        ScVal::U32(x) => x.to_string(),
        ScVal::I32(x) => x.to_string(),
        ScVal::U64(x) => x.to_string(),
        ScVal::I64(x) => x.to_string(),
        ScVal::Timepoint(x) => x.0.to_string(),
        ScVal::Duration(x) => x.0.to_string(),
        ScVal::U128(p) => (((p.hi as u128) << 64) | p.lo as u128).to_string(),
        ScVal::I128(p) => ((((p.hi as i128) << 64) as u128 | p.lo as u128) as i128).to_string(),
        ScVal::Address(a) => addr_lean(a, &BTreeMap::new()),
        _ => return None,
    })
}

fn addr_lean(a: &ScAddress, _ids: &BTreeMap<ScAddress, i128>) -> String {
    // a placeholder resolved at emission, once every address is known.
    format!("@A{}", hex(a))
}

fn hex(a: &ScAddress) -> String {
    use soroban_sdk::xdr::{Limits, WriteXdr};
    a.to_xdr(Limits::none()).unwrap().iter().map(|b| format!("{b:02x}")).collect()
}

fn sym(v: &ScVal) -> Option<String> {
    match v {
        ScVal::Symbol(s) => Some(s.to_utf8_string_lossy()),
        _ => None,
    }
}

/// A storage key as the model's `Key` (see the emitted prelude).
fn key_lean(k: &ScVal, ids: &BTreeMap<ScAddress, i128>) -> Option<String> {
    let _ = ids;
    if let Some(s) = sym(k) {
        return Some(format!(".var \"{s}\""));
    }
    let ScVal::Vec(Some(v)) = k else { return None };
    let name = sym(v.0.first()?)?;
    let rest = &v.0[1..];
    let lit = |x: &str| if x.starts_with('-') { format!("({x})") } else { x.to_string() };
    match rest {
        [] => Some(format!(".var \"{name}\"")),
        [ScVal::Map(Some(m))] => {
            let fs: Option<Vec<String>> = m.0.iter().map(|e| scalar(&e.val).map(|x| lit(&x))).collect();
            Some(format!(".tup \"{name}\" [{}]", fs?.join(", ")))
        }
        [x] => Some(format!(".entry \"{name}\" ({})", lit(&scalar(x)?))),
        xs => {
            let fs: Option<Vec<String>> = xs.iter().map(|x| scalar(x).map(|y| lit(&y))).collect();
            Some(format!(".tup \"{name}\" [{}]", fs?.join(", ")))
        }
    }
}

/// A stored value under `key`: a struct (map with Symbol keys) field by field.
fn flatten(key: &str, v: &ScVal, ids: &BTreeMap<ScAddress, i128>, out: &mut BTreeMap<String, i128>) {
    if let ScVal::Map(Some(m)) = v {
        if m.0.iter().all(|e| sym(&e.key).is_some()) {
            for e in m.0.iter() {
                flatten(&format!(".fld ({key}) \"{}\"", sym(&e.key).unwrap()), &e.val, ids, out);
            }
            return;
        }
    }
    if let Some(x) = scalar(v) {
        // addresses are numbered later: keep the placeholder in a side table.
        match x.strip_prefix("@A") {
            Some(h) => {
                out.insert(format!("{key}=@A{h}"), 0);
            }
            None => {
                out.insert(key.to_string(), x.parse().unwrap());
            }
        }
    }
}

// ---------------------------------------------------------------- scenarios

fn wasm(dir: &str, path: &str) -> std::vec::Vec<u8> {
    std::fs::read(format!("{dir}/{path}")).unwrap_or_else(|e| panic!("{dir}/{path}: {e}"))
}

fn increment(dir: &str, runs: usize) -> World {
    let mut w = World::new(1);
    w.id = w.env.register(wasm(dir, "increment/target/wasm32v1-none/release/soroban_increment_contract.wasm").as_slice(), ());
    for _ in 0..runs {
        w.call("increment", vec![]);
    }
    w
}

fn token(dir: &str, runs: usize) -> World {
    let mut w = World::new(2);
    let admin = Address::generate(&w.env);
    w.users = (0..4).map(|_| Address::generate(&w.env)).collect();
    w.users.push(admin.clone());
    let (n, s) = (SString::from_str(&w.env, "Tok"), SString::from_str(&w.env, "TOK"));
    let args = vec![("admin", w.v(&admin)), ("decimal", w.v(7u32)), ("name", w.v(n)), ("symbol", w.v(s))];
    w.construct(&wasm(dir, "token/target/wasm32v1-none/release/soroban_token_contract.wasm"), args);
    for _ in 0..runs {
        let (a, b, c, amt) = (w.user(), w.user(), w.user(), w.amount());
        let exp = w.env.ledger().sequence() + w.rand(200) as u32;
        match w.rand(11) {
            0 | 1 => w.call("mint", vec![("to", w.v(&a)), ("amount", w.v(amt.abs() * 10))]),
            2 | 3 => w.call("transfer", vec![("from", w.v(&a)), ("to_muxed", w.v(&b)), ("amount", w.v(amt))]),
            4 => w.call("approve", vec![("from", w.v(&a)), ("spender", w.v(&b)), ("amount", w.v(amt)), ("live_until_ledger", w.v(exp))]),
            5 => w.call("transfer_from", vec![("spender", w.v(&b)), ("from", w.v(&a)), ("to", w.v(&c)), ("amount", w.v(amt))]),
            6 => w.call("burn", vec![("from", w.v(&a)), ("amount", w.v(amt))]),
            7 => w.call("burn_from", vec![("spender", w.v(&b)), ("from", w.v(&a)), ("amount", w.v(amt))]),
            8 => w.call("balance", vec![("id", w.v(&a))]),
            9 => w.call("allowance", vec![("from", w.v(&a)), ("spender", w.v(&b))]),
            _ => {
                let f = ["decimals", "name", "symbol"][w.rand(3) as usize];
                w.call(f, vec![])
            }
        };
        if w.rand(5) == 0 {
            w.advance(1, 5);
        }
    }
    w
}

fn atomic_swap(dir: &str, runs: usize) -> World {
    let mut w = World::new(3);
    w.users = (0..3).map(|_| Address::generate(&w.env)).collect();
    w.id = w.env.register(wasm(dir, "atomic_swap/target/wasm32v1-none/release/soroban_atomic_swap_contract.wasm").as_slice(), ());
    let us = w.users.clone();
    let (ta, tb) = (w.token(&us, 5_000), w.token(&us, 5_000));
    for _ in 0..runs {
        let (a, b) = (w.user(), w.user());
        let (x, y) = if w.rand(2) == 0 { (ta.clone(), tb.clone()) } else { (tb.clone(), ta.clone()) };
        let (am_a, am_b) = (w.rand(800) as i128, w.rand(800) as i128);
        let (mn_a, mn_b) = (am_a - w.rand(am_a as u64 + 3) as i128 + 1, am_b - w.rand(am_b as u64 + 3) as i128 + 1);
        w.call("swap", vec![("a", w.v(&a)), ("b", w.v(&b)), ("token_a", w.v(&x)), ("token_b", w.v(&y)),
            ("amount_a", w.v(am_a)), ("min_b_for_a", w.v(mn_b)), ("amount_b", w.v(am_b)), ("min_a_for_b", w.v(mn_a))]);
    }
    w
}

fn liquidity_pool(dir: &str, runs: usize) -> World {
    let mut w = World::new(4);
    w.users = (0..3).map(|_| Address::generate(&w.env)).collect();
    let us = w.users.clone();
    let (mut ta, mut tb) = (w.token(&us, 1_000_000), w.token(&us, 1_000_000));
    if tb < ta {
        std::mem::swap(&mut ta, &mut tb);
    }
    let args = vec![("token_a", w.v(&ta)), ("token_b", w.v(&tb))];
    w.construct(&wasm(dir, "liquidity_pool/target/wasm32v1-none/release/soroban_liquidity_pool_contract.wasm"), args);
    for _ in 0..runs {
        let to = w.user();
        let (x, y) = (w.amount().abs() * 10, w.amount().abs() * 10);
        match w.rand(6) {
            0 | 1 => w.call("deposit", vec![("to", w.v(&to)), ("desired_a", w.v(x)), ("min_a", w.v(x / 2)), ("desired_b", w.v(y)), ("min_b", w.v(y / 2))]),
            2 | 3 => {
                let buy_a = w.rand(2) == 0;
                w.call("swap", vec![("to", w.v(&to)), ("buy_a", w.v(buy_a)), ("out", w.v(x / 10)), ("in_max", w.v(y * 10))])
            }
            4 => w.call("withdraw", vec![("to", w.v(&to)), ("share_amount", w.v(x / 4)), ("min_a", w.v(0i128)), ("min_b", w.v(0i128))]),
            _ => {
                if w.rand(2) == 0 { w.call("get_rsrvs", vec![]) } else { w.call("balance_shares", vec![("user", w.v(&to))]) }
            }
        };
    }
    w
}

fn single_offer(dir: &str, runs: usize) -> World {
    let mut w = World::new(5);
    w.users = (0..3).map(|_| Address::generate(&w.env)).collect();
    w.id = w.env.register(wasm(dir, "single_offer/target/wasm32v1-none/release/soroban_single_offer_contract.wasm").as_slice(), ());
    let us = w.users.clone();
    let (sell, buy) = (w.token(&us, 100_000), w.token(&us, 100_000));
    for r in 0..runs {
        if r % 25 == 24 {
            w.instances.push(w.id.clone());
            w.id = w.env.register(wasm(dir, "single_offer/target/wasm32v1-none/release/soroban_single_offer_contract.wasm").as_slice(), ());
        }
        let a = w.user();
        let (p, q) = (w.rand(4) as u32, w.rand(4) as u32);
        match w.rand(8) {
            0 => w.call("create", vec![("seller", w.v(&a)), ("sell_token", w.v(&sell)), ("buy_token", w.v(&buy)), ("sell_price", w.v(p)), ("buy_price", w.v(q))]),
            1 => {
                // the seller funds the offer (outside the contract)
                let amt = w.rand(500) as i128;
                TokenClient::new(&w.env, &sell).transfer(&a, &w.id, &amt);
                false
            }
            2 | 3 => {
                let amt = w.amount();
                let min = w.rand(3) as i128;
                w.call("trade", vec![("buyer", w.v(&a)), ("buy_token_amount", w.v(amt)), ("min_sell_token_amount", w.v(min))])
            }
            4 => {
                let t = if w.rand(2) == 0 { sell.clone() } else { buy.clone() };
                let amt = w.rand(300) as i128;
                w.call("withdraw", vec![("token", w.v(&t)), ("amount", w.v(amt))])
            }
            5 => w.call("updt_price", vec![("sell_price", w.v(p)), ("buy_price", w.v(q))]),
            _ => w.call("get_offer", vec![]),
        };
    }
    w
}

fn timelock(dir: &str, runs: usize) -> World {
    let mut w = World::new(6);
    w.users = (0..4).map(|_| Address::generate(&w.env)).collect();
    w.id = w.env.register(wasm(dir, "timelock/target/wasm32v1-none/release/soroban_timelock_contract.wasm").as_slice(), ());
    let us = w.users.clone();
    let t = w.token(&us, 10_000);
    for r in 0..runs {
        if r % 8 == 7 {
            w.instances.push(w.id.clone());
            w.id = w.env.register(wasm(dir, "timelock/target/wasm32v1-none/release/soroban_timelock_contract.wasm").as_slice(), ());
        }
        let a = w.user();
        match w.rand(4) {
            0 => {
                let n = 1 + w.rand(3) as usize;
                let cl: std::vec::Vec<ScVal> = (0..n).map(|_| { let u = w.user(); ScVal::Address(sc_addr(&w.env, &u)) }).collect();
                let kind = ScVal::Vec(Some(vec![ScVal::Symbol(if w.rand(2) == 0 { "Before" } else { "After" }.try_into().unwrap())].try_into().unwrap()));
                let tsv = w.env.ledger().timestamp() + w.rand(100);
                let tb = ScVal::Map(Some(soroban_sdk::xdr::ScMap(vec![
                    soroban_sdk::xdr::ScMapEntry { key: ScVal::Symbol("kind".try_into().unwrap()), val: kind },
                    soroban_sdk::xdr::ScMapEntry { key: ScVal::Symbol("timestamp".try_into().unwrap()), val: ScVal::U64(tsv) },
                ].try_into().unwrap())));
                let cls = ScVal::Vec(Some(cl.try_into().unwrap()));
                let amt = w.rand(1000) as i128;
                w.call("deposit", vec![("from", w.v(&a)), ("token", w.v(&t)), ("amount", w.v(amt)), ("claimants", w.sv(cls)), ("time_bound", w.sv(tb))])
            }
            1 | 2 => w.call("claim", vec![("claimant", w.v(&a))]),
            _ => {
                w.advance(1, 30);
                false
            }
        };
    }
    w
}

fn mint_lock(dir: &str, runs: usize) -> World {
    let mut w = World::new(7);
    let admin = Address::generate(&w.env);
    w.users = (0..3).map(|_| Address::generate(&w.env)).collect();
    w.users.push(admin.clone());
    let args = vec![("admin", w.v(&admin))];
    w.construct(&wasm(dir, "mint-lock/target/wasm32v1-none/release/soroban_mint_lock_contract.wasm"), args);
    let t = w.token(&[], 0);
    StellarAssetClient::new(&w.env, &t).set_admin(&w.id);
    for _ in 0..runs {
        let (m, to) = (w.user(), w.user());
        match w.rand(7) {
            6 => {
                let nb = w.user();
                if w.rand(3) == 0 { w.call("set_admin", vec![("new_admin", w.v(&nb))]) } else { w.call("admin", vec![]) }
            }
            0 => {
                let cfg = ScVal::Map(Some(soroban_sdk::xdr::ScMap(vec![
                    soroban_sdk::xdr::ScMapEntry { key: ScVal::Symbol("epoch_length".try_into().unwrap()), val: ScVal::U32(1 + w.rand(5) as u32) },
                    soroban_sdk::xdr::ScMapEntry { key: ScVal::Symbol("limit".try_into().unwrap()), val: ScVal::I128(soroban_sdk::xdr::Int128Parts { hi: 0, lo: w.rand(1000) }) },
                ].try_into().unwrap())));
                w.call("set_minter", vec![("contract", w.v(&t)), ("minter", w.v(&m)), ("config", w.sv(cfg))])
            }
            1 | 2 | 3 => {
                let amt = w.amount();
                w.call("mint", vec![("contract", w.v(&t)), ("minter", w.v(&m)), ("to", w.v(&to)), ("amount", w.v(amt))])
            }
            4 => w.call("minter", vec![("contract", w.v(&t)), ("minter", w.v(&m))]),
            _ => {
                let n = 1 + w.rand(2) as u32;
                w.advance(n, 5);
                if w.rand(4) == 0 { w.call("admin", vec![]) } else { false }
            }
        };
    }
    w
}

// ---------------------------------------------------------------- emission

/// Number every address in host order (`obj_cmp`), so `Addr` order is the host's.
fn number(w: &mut World) {
    let mut all: std::vec::Vec<Address> = w.users.clone();
    all.push(w.id.clone());
    all.extend(w.instances.iter().cloned());
    all.push(w.caller.clone());
    all.extend(w.tokens.iter().cloned());
    all.sort();
    all.dedup();
    for (k, a) in all.iter().enumerate() {
        w.ids.insert(sc_addr(&w.env, a), 100 + k as i128);
    }
    // the placeholder order must agree with the host's ordering of these objects.
    for x in &all {
        for y in &all {
            assert_eq!(x.cmp(y), sc_addr(&w.env, x).cmp(&sc_addr(&w.env, y)), "host address order ≠ ScAddress order");
        }
    }
}

fn resolve(s: &str, ids: &BTreeMap<String, i128>) -> String {
    let mut out = String::new();
    let mut rest = s;
    while let Some(i) = rest.find("@A") {
        out.push_str(&rest[..i]);
        let h: String = rest[i + 2..].chars().take_while(|c| c.is_ascii_hexdigit()).collect();
        let _ = write!(out, "{}", ids.get(&h).copied().unwrap_or(-1));
        rest = &rest[i + 2 + h.len()..];
    }
    out.push_str(rest);
    out
}

fn lit(x: i128) -> String {
    if x < 0 { format!("({x})") } else { x.to_string() }
}

/// A snapshot as Lean `(Key × Int)` pairs (address values resolved).
fn pairs(s: &Snap, ids: &BTreeMap<String, i128>) -> std::vec::Vec<(String, i128)> {
    s.vals
        .iter()
        .map(|(k, v)| match k.split_once("=@A") {
            Some((key, h)) => (resolve(key, ids), ids.get(h).copied().unwrap_or(-1)),
            None => (resolve(k, ids), *v),
        })
        .collect()
}

fn emit(name: &str, w: &mut World) -> String {
    number(w);
    let ids: BTreeMap<String, i128> = w.ids.iter().map(|(a, i)| (hex(a), *i)).collect();
    let id = |a: &ScAddress| ids.get(&hex(a)).copied().unwrap_or(-1);
    let mut out = format!("-- {} successful invocations of `{name}` (of {} tried), recorded by the conformance harness.\n\n", w.obs.len(), w.tried);
    for (k, o) in w.obs.iter().enumerate() {
        let (mut arg, mut arga) = (vec![], vec![]);
        for (n, v) in &o.args {
            match v {
                ScVal::Address(a) => arga.push(format!("(\"{n}\", {})", id(a))),
                ScVal::Map(Some(m)) => {
                    for e in m.0.iter() {
                        if let (Some(f), Some(x)) = (sym(&e.key), scalar(&e.val)) {
                            arg.push(format!("(\"{n}.{f}\", {})", resolve(&if x.starts_with('-') { format!("({x})") } else { x }, &ids)));
                        }
                    }
                }
                ScVal::Vec(Some(xs)) => arg.push(format!("(\"{n}.len\", {})", xs.0.len())),
                v => {
                    if let Some(x) = scalar(v) {
                        arg.push(format!("(\"{n}\", {})", if x.starts_with('-') { format!("({x})") } else { x }));
                    }
                }
            }
        }
        let st = |s: &Snap| pairs(s, &ids).iter().map(|(k, v)| format!("({k}, {})", lit(*v))).collect::<std::vec::Vec<_>>().join(", ");
        // what to compare after the call: every value present, every presence
        // bit (0 for keys gone), every balance.
        let mut keys = pairs(&o.post, &ids);
        for r in &o.pre.roots {
            if !o.post.roots.contains(r) {
                keys.push((format!(".has ({})", resolve(r, &ids)), 0));
            }
        }
        let (ret, ret_known) = match scalar(&o.ret) {
            Some(x) => (resolve(&if x.starts_with('-') { format!("({x})") } else { x }, &ids), true),
            None => ("0".into(), false),
        };
        let signers: std::vec::Vec<String> = o.signers.iter().map(|a| id(a).to_string()).collect();
        let call = format!("{{ fn := \"{}\", caller := {}, self := {}, arg := tbl [{}], argA := tbl [{}], signers := [{}], env := tbl [(\"sequence\", {}), (\"timestamp\", {})] }}",
            o.entry, id(&sc_addr(&w.env, &w.caller)), id(&o.me), arg.join(", "), arga.join(", "), signers.join(", "), o.seq, o.ts);
        let _ = writeln!(out, "def o{k} : Obs where");
        let _ = writeln!(out, "  entry := \"{}\"", o.entry);
        let _ = writeln!(out, "  retKnown := {ret_known}");
        let _ = writeln!(out, "  step := {{ call := {call}, pre := mkStorage [{}], post := mkStorage [{}], writes := [], ret := {ret} }}", st(&o.pre), st(&o.post));
        let _ = writeln!(out, "  keys := [{}]\n", keys.iter().map(|(k, v)| format!("({k}, {})", lit(*v))).collect::<std::vec::Vec<_>>().join(", "));
    }
    let _ = writeln!(out, "def observations : List Obs := [{}]", (0..w.obs.len()).map(|k| format!("o{k}")).collect::<std::vec::Vec<_>>().join(", "));
    out
}

fn main() {
    let a: std::vec::Vec<String> = std::env::args().collect();
    let (dir, out) = (a.get(1).expect("soroban-examples dir"), a.get(2).expect("out dir"));
    let runs: usize = a.get(3).and_then(|r| r.parse().ok()).unwrap_or(200);
    let scenarios: [(&str, fn(&str, usize) -> World); 7] = [
        ("increment", increment),
        ("token", token),
        ("atomic_swap", atomic_swap),
        ("liquidity_pool", liquidity_pool),
        ("single_offer", single_offer),
        ("timelock", timelock),
        ("mint_lock", mint_lock),
    ];
    for (name, run) in scenarios {
        let mut w = run(dir, runs);
        let text = emit(name, &mut w);
        std::fs::write(format!("{out}/{name}.obs.lean"), text).unwrap();
        println!("{name}: {} successful of {} tried", w.obs.len(), w.tried);
    }
}
