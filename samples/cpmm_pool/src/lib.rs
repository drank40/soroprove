#![no_std]
//! A minimal constant-product AMM pool: reserve X and reserve Y, and a `swap`
//! that takes `dx` of X in and returns the constant-product amount of Y out.
//! The anti-drain property proved against the lifted bytecode:
//!
//!   the product x*y never decreases across a swap -- the pool cannot be drained
//!
//! which holds because `out = y*dx/(x+dx)` is a floor division, so
//! `out*(x+dx) <= y*dx`, hence `(x+dx)*(y-out) >= x*y`.
//!
//! (X is kept in instance storage and Y in persistent storage purely so the
//! decompiler tells the two reserves apart by their storage durability; it does
//! not change the arithmetic.)
use soroban_sdk::{contract, contractimpl, Env, Symbol, symbol_short};

const RX: Symbol = symbol_short!("x");
const RY: Symbol = symbol_short!("y");

#[contract]
pub struct Pool;

#[contractimpl]
impl Pool {
    pub fn __constructor(env: Env, x0: i64, y0: i64) {
        env.storage().instance().set(&RX, &x0);
        env.storage().persistent().set(&RY, &y0);
    }

    /// Swap `dx` of X in for the constant-product amount of Y out.
    pub fn swap(env: Env, dx: i64) -> i64 {
        let x: i64 = env.storage().instance().get(&RX).unwrap();
        let y: i64 = env.storage().persistent().get(&RY).unwrap();
        let out: i64 = y * dx / (x + dx);
        env.storage().instance().set(&RX, &(x + dx));
        env.storage().persistent().set(&RY, &(y - out));
        out
    }
}
