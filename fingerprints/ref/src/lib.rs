//! The reference contract. It does nothing useful; it uses the SDK: storage
//! in every durability, keyed by unit, tuple, struct and tuple-of-values
//! cases; every scalar and container converted both ways, each from several
//! places so the inliner leaves the conversion out of line as real contracts
//! do; symbols and strings from text; auth, events, a token client, a
//! cross-contract call, ledger and prng reads, hashes; i128/u128 arithmetic
//! that reaches compiler-builtins; struct copies that reach memcpy. Built
//! with symbol names kept, each SDK/core function it pulls in is
//! fingerprinted under its real name (../gen.sh). Types are named to collide
//! with nothing real: a function whose name mentions this crate is left out
//! of the table. APIs are the ones every SDK since 20 has.
#![no_std]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, panic_with_error, symbol_short, token, unwrap::UnwrapOptimized, Address, Bytes,
    BytesN, Env, IntoVal, Map, String, Symbol, Val, Vec,
};

#[contracttype]
#[derive(Clone)]
pub struct RefPair {
    pub a: Address,
    pub b: Address,
}

#[contracttype]
#[derive(Clone)]
pub struct RefBalance {
    pub q4w: i128,
    pub shares: i128,
    pub tokens: i128,
}

#[contracttype]
#[derive(Clone)]
pub enum RefKey {
    Admin,
    Balance(Address),
    Pair(RefPair),
    Nonce(u32),
    Both(Address, u32),
}

#[contracttype]
#[derive(Clone, Copy)]
pub enum RefFlag {
    Off = 0,
    On = 1,
}

#[contracterror]
#[derive(Clone, Copy)]
#[repr(u32)]
pub enum RefError {
    Missing = 1,
    Overflow = 2,
    Bad = 3,
}

#[derive(Clone, Copy)]
pub struct RefWide {
    pub w: [u64; 16],
}

#[contract]
pub struct Ref;

#[contractimpl]
impl Ref {
    pub fn init(env: Env, admin: Address, token: Address) {
        admin.require_auth();
        env.storage().instance().set(&RefKey::Admin, &admin);
        env.storage().instance().set(&symbol_short!("Token"), &token);
        env.storage().instance().extend_ttl(100, 200);
    }

    pub fn deposit(env: Env, from: Address, amount: i128) -> i128 {
        from.require_auth();
        let token: Address = env.storage().instance().get(&symbol_short!("Token")).unwrap();
        token::Client::new(&env, &token).transfer(&from, &env.current_contract_address(), &amount);
        let key = RefKey::Balance(from.clone());
        let mut bal: RefBalance = env.storage().persistent().get(&key).unwrap_or(RefBalance { q4w: 0, shares: 0, tokens: 0 });
        bal.tokens = bal.tokens.checked_add(amount).unwrap_or_else(|| panic_with_error!(&env, RefError::Overflow));
        bal.shares = mul_div(&env, amount, 1_000_000, bal.tokens.max(1));
        env.storage().persistent().set(&key, &bal);
        env.storage().persistent().extend_ttl(&key, 100, 200);
        env.events().publish((symbol_short!("deposit"), from), amount);
        bal.shares
    }

    pub fn pair(env: Env, a: Address, b: Address, n: u32) -> Option<RefBalance> {
        let key = RefKey::Pair(RefPair { a: a.clone(), b: b.clone() });
        if env.storage().persistent().has(&key) {
            env.storage().persistent().extend_ttl(&key, 100, 200);
        }
        env.storage().temporary().set(&RefKey::Nonce(n), &(n as u64 * 3));
        env.storage().temporary().set(&RefKey::Both(a, n), &b);
        env.storage().persistent().get(&key)
    }

    pub fn remove(env: Env, who: Address) -> bool {
        let key = RefKey::Balance(who);
        let had = env.storage().persistent().has(&key);
        env.storage().persistent().remove(&key);
        had
    }

    /// Every scalar through temporary storage, both directions, three times.
    pub fn nums(env: Env, a: i64, b: u64, c: u32, d: i32, e: bool, f: u128, g: i128) -> (i64, u64, u32, i32, bool, u128, i128) {
        let s = env.storage().temporary();
        s.set(&RefKey::Nonce(1), &a);
        s.set(&RefKey::Nonce(2), &b);
        s.set(&RefKey::Nonce(3), &c);
        s.set(&RefKey::Nonce(4), &d);
        s.set(&RefKey::Nonce(5), &e);
        s.set(&RefKey::Nonce(6), &f);
        s.set(&RefKey::Nonce(7), &g);
        let p = env.storage().persistent();
        p.set(&symbol_short!("a"), &a);
        p.set(&symbol_short!("b"), &b);
        p.set(&symbol_short!("f"), &f);
        p.set(&symbol_short!("g"), &g);
        (
            s.get(&RefKey::Nonce(1)).unwrap_or(a) + p.get(&symbol_short!("a")).unwrap_or(0),
            s.get(&RefKey::Nonce(2)).unwrap_or(b) ^ p.get(&symbol_short!("b")).unwrap_or(0),
            s.get(&RefKey::Nonce(3)).unwrap_or(c),
            s.get(&RefKey::Nonce(4)).unwrap_or(d),
            s.get(&RefKey::Nonce(5)).unwrap_or(e),
            s.get(&RefKey::Nonce(6)).unwrap_or(f) | p.get(&symbol_short!("f")).unwrap_or(0),
            s.get(&RefKey::Nonce(7)).unwrap_or(g) - p.get(&symbol_short!("g")).unwrap_or(0),
        )
    }

    pub fn sym(env: Env, s: String, long: bool) -> Symbol {
        let mut buf = [0u8; 32];
        let n = (s.len() as usize).min(32);
        s.copy_into_slice(&mut buf[..n]);
        let text = core::str::from_utf8(&buf[..n]).unwrap_or("bad");
        if long {
            Symbol::new(&env, "LongerThanNineChars")
        } else {
            Symbol::new(&env, text)
        }
    }

    pub fn text(env: Env, s: String) -> String {
        let t = String::from_str(&env, "hello, world");
        if s.len() > t.len() {
            s
        } else {
            t
        }
    }

    pub fn math(env: Env, a: i128, b: i128, c: i128, u: u128) -> (i128, u128, u64) {
        let m = mul_div(&env, a, b, c);
        let q = u / (c as u128).max(1);
        let r = u % 7;
        let p = a.pow(3);
        (m.checked_sub(p).unwrap_or_else(|| panic_with_error!(&env, RefError::Overflow)), q + r, (m as u64).wrapping_mul(3))
    }

    pub fn checks(env: Env, a: Address, b: Address, x: i128, y: u128) -> Result<(bool, i128), RefError> {
        if a == b {
            return Err(RefError::Bad);
        }
        let ord = a < b;
        let z = x.checked_mul(x).ok_or(RefError::Overflow)?;
        let w = (y >> 3).checked_add(y << 2).ok_or(RefError::Overflow)? as i128;
        let q = if z != 0 { w.checked_rem(z).ok_or(RefError::Bad)? } else { w };
        env.storage().persistent().set(&(symbol_short!("q"), a), &q);
        Ok((ord, q.abs().min(i128::MAX / 2)))
    }

    pub fn vecs(env: Env, xs: Vec<Address>, ys: Vec<i128>) -> (u32, i128, Map<Address, i128>) {
        let mut m: Map<Address, i128> = Map::new(&env);
        let mut sum = 0i128;
        for (i, a) in xs.iter().enumerate() {
            let y = ys.get(i as u32).unwrap_or(0);
            sum += y;
            m.set(a, y);
        }
        let mut out: Vec<Address> = Vec::new(&env);
        out.push_back(env.current_contract_address());
        if let Some(a) = xs.first() {
            out.push_back(a);
        }
        (out.len() + m.len(), sum, m)
    }

    pub fn vec2(env: Env, xs: Vec<i128>, ys: Vec<u32>, zs: Vec<Symbol>, bs: Vec<Bytes>) -> (i128, u32, Symbol, Bytes) {
        let mut acc = 0i128;
        for x in xs.iter() {
            acc = acc.checked_add(x).unwrap_optimized();
        }
        let last = xs.last().unwrap_or(0);
        let y = ys.get(0).unwrap_or(0) + ys.last().unwrap_or(0) + ys.len();
        let mut zs2 = zs.clone();
        zs2.push_back(symbol_short!("end"));
        let z = zs2.pop_back().unwrap_or(symbol_short!("none"));
        let b = bs.first().unwrap_or(Bytes::new(&env));
        (acc + last, y, z, b)
    }

    pub fn map2(env: Env, m: Map<Symbol, i128>, n: Map<u32, Address>, k: Symbol, i: u32) -> (i128, Option<Address>, Vec<Symbol>, Vec<Address>) {
        let mut m2 = m.clone();
        m2.set(k.clone(), m.get(k.clone()).unwrap_or(0) + 1);
        if n.contains_key(i) {
            m2.remove(k.clone());
        }
        env.storage().instance().set(&k, &m2);
        (m2.get(k).unwrap_or(-1), n.get(i), m2.keys(), n.values())
    }

    pub fn strs(env: Env, s: String, b: Bytes) -> (String, Bytes, BytesN<32>, u32) {
        let mut sb = Bytes::new(&env);
        sb.append(&b);
        sb.push_back(7);
        sb.extend_from_slice(b"tail");
        let hash: BytesN<32> = env.crypto().sha256(&sb).into();
        let k: BytesN<32> = env.crypto().keccak256(&b).into();
        let t = if s.len() == 0 {
            String::from_str(&env, "empty")
        } else if s == String::from_str(&env, "x") {
            String::from_bytes(&env, b"y")
        } else {
            s
        };
        env.storage().persistent().set(&hash, &t);
        (t, sb.slice(1..), k, hash.len() + Bytes::from_array(&env, &[1u8, 2, 3]).len())
    }

    pub fn bytes(env: Env, b: Bytes, h: BytesN<32>) -> (Bytes, bool, u32) {
        let mut buf = [0u8; 64];
        let n = (b.len() as usize).min(64);
        b.copy_into_slice(&mut buf[..n]);
        let copy = Bytes::from_slice(&env, &buf[..n]);
        let eq = copy == b && h.to_array()[0] == buf[0];
        (copy.slice(0..(n as u32 / 2)), eq, env.ledger().sequence().wrapping_add(env.ledger().timestamp() as u32))
    }

    pub fn ledger(env: Env, who: Address) -> (u64, u32, BytesN<32>, Address, u64) {
        let l = env.ledger();
        let r = env.prng().u64_in_range(1..=1000);
        (l.timestamp(), l.sequence(), l.network_id(), env.current_contract_address(), r ^ (who.to_string().len() as u64))
    }

    pub fn invoke(env: Env, target: Address, fname: Symbol, amount: i128, to: Address) -> Val {
        let mut args: Vec<Val> = Vec::new(&env);
        args.push_back(amount.into_val(&env));
        args.push_back(to.into_val(&env));
        let c = token::Client::new(&env, &target);
        let bal = c.balance(&to);
        c.approve(&env.current_contract_address(), &to, &bal, &(env.ledger().sequence() + 100));
        let name: String = c.name();
        if name.len() > 3 {
            c.transfer_from(&env.current_contract_address(), &to, &target, &amount);
        }
        env.invoke_contract::<Val>(&target, &fname, args)
    }

    pub fn opt(env: Env, a: Option<Address>, n: Option<u32>, key: Symbol) -> Option<(Address, u32)> {
        let a = a?;
        let n = n.unwrap_or_else(|| env.storage().instance().get(&key).unwrap_or(0));
        env.storage().instance().set(&key, &(n + 1));
        env.storage().persistent().set(&(key.clone(), a.clone()), &n);
        env.storage().persistent().extend_ttl(&(key, a.clone()), 50, 100);
        Some((a, n))
    }

    pub fn events(env: Env, a: Address, x: i128, s: Symbol) {
        env.events().publish((symbol_short!("one"), a.clone()), x);
        env.events().publish((symbol_short!("two"), s, a), (x, 1u32));
        env.events().publish((symbol_short!("three"),), ());
    }

    pub fn flag(_env: Env, f: RefFlag, w: u64) -> Result<RefFlag, RefError> {
        let mut wide = RefWide { w: [w; 16] };
        let mut other = wide;
        other.w[3] = w.wrapping_add(1);
        wide = other;
        if wide.w[15] == 0 {
            return Err(RefError::Bad);
        }
        match f {
            RefFlag::Off => Ok(RefFlag::On),
            RefFlag::On => Err(RefError::Missing),
        }
    }

    pub fn addr(env: Env, s: String) -> String {
        let a = Address::from_string(&s);
        let mut args: Vec<Val> = Vec::new(&env);
        args.push_back(1u32.into_val(&env));
        args.push_back(symbol_short!("x").into_val(&env));
        a.require_auth_for_args(args);
        a.to_string()
    }
}

fn mul_div(env: &Env, a: i128, b: i128, c: i128) -> i128 {
    if c == 0 {
        panic_with_error!(env, RefError::Bad);
    }
    a.checked_mul(b).unwrap_or_else(|| panic_with_error!(env, RefError::Overflow)) / c
}
