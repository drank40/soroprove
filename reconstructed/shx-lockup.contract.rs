#![no_std]
//! Reconstructed by stellar-diver-mir --contract: the contract as soroban-sdk source.
//! An export that could not be said at this level is a `todo!()` naming why.
#![allow(unused_imports, unused_mut, unused_variables, unreachable_code, unused_parens, non_snake_case, clippy::all)]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, panic_with_error, symbol_short, vec, Address, Bytes, BytesN, Duration, Env, I256,
    Map, MuxedAddress, String, Symbol, Timepoint, U256, Val, Vec,
};

#[contracttype]
#[derive(Clone)]
pub enum DataKey {
    Token,
    MaxLockupDuration,
    Escrows,
    Escrow(Address),
}

#[contracttype]
#[derive(Clone)]
pub struct EscrowedBalance {
    pub account: Address,
    pub amount: i128,
    pub claim_after: u64,
}

#[contracterror]
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Error {
    ClaimAfterInPast = 1,
    LockupTooLong = 2,
    TooEarlyToUnlock = 3,
    EscrowNotFound = 4,
    EscrowAlreadyExists = 5,
}

#[contracttype]
#[derive(Clone)]
pub struct EscrowLockEvent {
    pub amount: i128,
    pub claim_after: u64,
}

#[contracttype]
#[derive(Clone)]
pub struct EscrowUnlockEvent {
    pub amount: i128,
}

#[contract]
pub struct Contract;

#[contractimpl]
impl Contract {
    pub fn __constructor(env: Env, token: Address, max_lockup_duration: u64) {
        // not reconstructed: call to obj_to_u64
        todo!()
    }

    pub fn lock(env: Env, account: Address, amount: i128, claim_after: u64) -> Result<(), Error> {
        // not reconstructed: call to obj_to_i128_hi64
        todo!()
    }

    pub fn unlock(env: Env, account: Address) -> Result<(), Error> {
        // not reconstructed: call to f29
        todo!()
    }

    pub fn extend_ttl(env: Env, ttl: u32) -> Result<(), Error> {
        // not reconstructed: not reconstructed: arg_payload & 18446744069414584324u64
        todo!()
    }

    // t_: exported, not in the spec.
}
