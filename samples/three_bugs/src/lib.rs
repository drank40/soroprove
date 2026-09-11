#![no_std]
//! One contract that exercises all three bug classes stellar-diver exists to
//! prevent, so a single build is the whole regression corpus.
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, panic_with_error, symbol_short, Address,
    Env, Symbol,
};

#[contracttype]
#[derive(Copy, Clone, PartialEq)]
pub enum Flag {
    A = 0,
    B = 1,
    C = 2,
    D = 3,
    E = 4,
}

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum Error {
    AnError = 1,
}

#[contracttype]
#[derive(Clone)]
pub struct PairKey {
    pub a: Address,
    pub b: Address,
}

#[contracttype]
#[derive(Clone)]
pub enum DataKey {
    Pair(PairKey),
    Single(Address),
}

#[contract]
pub struct Contract;

#[contractimpl]
impl Contract {
    /// Bug 2: `true` is Val payload 1 (Tag::True). Anything that renders this
    /// as the integer 1 writes ScVal::U32(1) instead of ScVal::Bool(true).
    pub fn set_flag(e: Env) {
        e.storage().persistent().set(&symbol_short!("f"), &true);
    }

    /// Bug 1: a five-way dispatch where one arm is a bare `Err` return, i.e.
    /// a branch straight to the function epilogue rather than to a block tail.
    pub fn pick(e: Env, f: Flag) -> Result<Symbol, Error> {
        if f == Flag::A {
            Ok(symbol_short!("a"))
        } else if f == Flag::B {
            Err(Error::AnError)
        } else if f == Flag::C {
            panic_with_error!(&e, Error::AnError)
        } else if f == Flag::D {
            panic!()
        } else {
            Ok(symbol_short!("e"))
        }
    }

    /// Bug 3: a storage key whose payload is a nested struct built from two
    /// params. Recovering the shape but not the values must stay a hole.
    pub fn read(e: Env, a: Address, b: Address) -> bool {
        e.storage().persistent().has(&DataKey::Pair(PairKey { a, b }))
    }
}
