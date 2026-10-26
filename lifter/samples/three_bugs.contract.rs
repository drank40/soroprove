#![no_std]
//! Reconstructed by stellar-diver-mir --contract: the contract as soroban-sdk source.
//! An export that could not be said at this level is a `todo!()` naming why.
#![allow(unused_imports, unused_mut, unused_variables, unreachable_code, unused_parens, non_snake_case, clippy::all)]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, panic_with_error, symbol_short, token, vec, Address, Bytes, BytesN, Duration, Env,
    I256, IntoVal, Map, String, Symbol, Timepoint, TryFromVal, U256, Val, Vec,
};

#[contracttype]
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Flag {
    A = 0,
    B = 1,
    C = 2,
    D = 3,
    E = 4,
}

#[contracterror]
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Error {
    AnError = 1,
}

#[contracttype]
#[derive(Clone)]
pub enum DataKey {
    Pair(PairKey),
    Single(Address),
}

#[contracttype]
#[derive(Clone)]
pub struct PairKey {
    pub a: Address,
    pub b: Address,
}

#[contract]
pub struct Contract;

#[contractimpl]
impl Contract {
    pub fn pick(env: Env, f: Flag) -> Result<Symbol, Error> {
        let mut brif_not;
        match f {
            Flag::A => {
                brif_not = Ok(symbol_short!("a"));
            }
            Flag::B => {
                brif_not = Err(Error::AnError);
            }
            Flag::C => {
                panic_with_error!(&env, Error::AnError);
            }
            Flag::D => {
                panic!();
            }
            Flag::E => {
                brif_not = Ok(symbol_short!("e"));
            }
        }
        brif_not
    }

    pub fn read(env: Env, a: Address, b: Address) -> bool {
        env.storage().persistent().has(&DataKey::Pair(PairKey { a: a.clone(), b: b.clone() }))
    }

    pub fn set_flag(env: Env) {
        env.storage().persistent().set(&symbol_short!("f"), &true);
    }
}
