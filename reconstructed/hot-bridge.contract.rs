#![no_std]
//! Reconstructed by stellar-diver-mir --contract: the contract as soroban-sdk source.
//! An export that could not be said at this level is a `todo!()` naming why.
#![allow(unused_imports, unused_mut, unused_variables, unreachable_code, unused_parens, non_snake_case, clippy::all)]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, panic_with_error, symbol_short, token, vec, Address, Bytes, BytesN, Duration, Env,
    I256, IntoVal, Map, String, Symbol, Timepoint, TryFromVal, U256, Val, Vec,
};

// Inferred dependencies (add to Cargo.toml): bytes, rlp.
// These crates ran in the binary; the exports below call into them.

#[contract]
pub struct Contract;

#[contractimpl]
impl Contract {
    pub fn set_owner(env: Env, owner: Address) {
        let mut lc;
        let mut to_val: Address;
        lc = vec![&env, Symbol::new(&env, "Owner")];
        if env.storage().instance().has(&lc) {
            to_val = env.storage().instance().get(&lc).unwrap();
            to_val.require_auth();
            env.storage().instance().set(&vec![&env, Symbol::new(&env, "Owner")], &owner.clone());
            return;
        } else {
            panic!();
        }
        panic!();
    }

    pub fn owner_withdraw(env: Env, amount: u128, token: Address) {
        let mut lc21;
        let mut to_val: Address;
        lc21 = vec![&env, Symbol::new(&env, "Owner")];
        if env.storage().instance().has(&lc21) {
            to_val = env.storage().instance().get(&lc21).unwrap();
            to_val.require_auth();
            token::Client::new(&env, &token.clone()).transfer(&env.current_contract_address(), &to_val, &(amount as i128));
            return;
        } else {
            panic!();
        }
        panic!();
    }

    pub fn increase_instant_ttl(env: Env) {
        let mut lc;
        let mut to_val18: Address;
        lc = vec![&env, Symbol::new(&env, "Owner")];
        if env.storage().instance().has(&lc) {
            to_val18 = env.storage().instance().get(&lc).unwrap();
            to_val18.require_auth();
            env.storage().instance().extend_ttl(2073600, 1728000);
            return;
        } else {
            panic!();
        }
    }

    pub fn clear_deposit(env: Env, nonce: u128) {
        let mut lc15;
        let mut to_val: Address;
        lc15 = vec![&env, Symbol::new(&env, "Owner")];
        if env.storage().instance().has(&lc15) {
            to_val = env.storage().instance().get(&lc15).unwrap();
            to_val.require_auth();
            env.storage().persistent().remove(&(Symbol::new(&env, "DepositNonce"), nonce));
            return;
        } else {
            panic!();
        }
        panic!();
    }

    pub fn set_public_key(env: Env, public_key: BytesN<65>) {
        let mut lc8;
        let mut to_val: Address;
        lc8 = vec![&env, Symbol::new(&env, "Owner")];
        if env.storage().instance().has(&lc8) {
            to_val = env.storage().instance().get(&lc8).unwrap();
            to_val.require_auth();
            env.storage().instance().set(&vec![&env, Symbol::new(&env, "PublicKey")], &public_key.clone());
            return;
        } else {
            panic!();
        }
        panic!();
    }

    pub fn get_deposit(env: Env, nonce: u128) -> Bytes {
        let mut lc18;
        lc18 = (Symbol::new(&env, "DepositNonce"), nonce);
        if env.storage().persistent().has(&lc18) {
            return env.storage().persistent().get(&lc18).unwrap();
        } else {
            panic!();
        }
        panic!();
    }

    pub fn get_timestmp(env: Env) -> u64 {
        // not reconstructed: branch on (obj_to_u64_8 < 72057594037927936u64)
        todo!()
    }

    pub fn get_owner(env: Env) -> Address {
        let mut lc;
        lc = vec![&env, Symbol::new(&env, "Owner")];
        if env.storage().instance().has(&lc) {
            return env.storage().instance().get(&lc).unwrap();
        } else {
            panic!();
        }
    }

    pub fn hot_verify(env: Env, wallet_id: String, data: BytesN<48>) -> bool {
        // not reconstructed: call to llvm_memset_p0_i64
        todo!()
    }

    pub fn constructor(env: Env, public_key: BytesN<65>, owner: Address) {
        if env.storage().instance().has(&vec![&env, Symbol::new(&env, "PublicKey")]) {
            panic!();
        } else {
            env.storage().instance().set(&vec![&env, Symbol::new(&env, "PublicKey")], &public_key.clone());
            env.storage().instance().set(&vec![&env, Symbol::new(&env, "Owner")], &owner.clone());
            return;
        }
        panic!();
    }

    pub fn withdraw(env: Env, amount: u128, nonce: u128, token: Address, receiver: Address, signature: BytesN<65>) {
        // not reconstructed: branch on cmp52_not
        todo!()
    }

    pub fn deposit(env: Env, sender_id: Address, amount: u128, token: Address, receiver_id: BytesN<32>, client_timestamp: u128) -> u128 {
        // not reconstructed: branch on (add28 == l8_0)
        todo!()
    }

    pub fn get_public_key(env: Env) -> BytesN<65> {
        // not reconstructed: 
        todo!()
    }

    pub fn is_executed(env: Env, nonce: u128) -> bool {
        env.storage().persistent().has(&(Symbol::new(&env, "WithdrawNonce"), nonce))
    }

    // t_: exported, not in the spec.
}
