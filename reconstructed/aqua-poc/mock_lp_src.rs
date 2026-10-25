#![no_std]
use soroban_sdk::{contract, contractimpl, Address, Env, String, symbol_short};

#[contract]
pub struct LpToken;

#[contractimpl]
impl LpToken {
    pub fn initialize(_e: Env, _admin: Address, _decimal: u32, _name: String, _symbol: String) {}
    pub fn mint(e: Env, to: Address, amount: i128) {
        let k = (symbol_short!("bal"), to);
        let cur: i128 = e.storage().persistent().get(&k).unwrap_or(0);
        e.storage().persistent().set(&k, &(cur + amount));
        let ts: i128 = e.storage().instance().get(&symbol_short!("ts")).unwrap_or(0);
        e.storage().instance().set(&symbol_short!("ts"), &(ts + amount));
    }
    pub fn balance(e: Env, id: Address) -> i128 {
        e.storage().persistent().get(&(symbol_short!("bal"), id)).unwrap_or(0)
    }
    pub fn total_supply(e: Env) -> i128 {
        e.storage().instance().get(&symbol_short!("ts")).unwrap_or(0)
    }
}
