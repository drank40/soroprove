#![no_std]
//! A deliberately minimal single-asset vault: one token, a per-user deposited
//! balance, and the two operations that move it. Small enough to state the
//! invariants by hand and check them against the lifted IR:
//!
//!   * a user can only ever `withdraw` what they have `deposit`ed
//!     (`balance(u)` never goes negative, enforced at the `require` below);
//!   * with `overflow-checks = true`, `deposit`'s `+` and `withdraw`'s `-`
//!     trap rather than wrap;
//!   * every state-changing entry point is gated by `require_auth(from)`.
use soroban_sdk::{contract, contractimpl, contracttype, token, Address, Env};

#[contracttype]
pub enum DataKey {
    /// The asset this vault custodies (set once, at construction).
    Token,
    /// Per-user deposited balance.
    Balance(Address),
}

#[contract]
pub struct Vault;

#[contractimpl]
impl Vault {
    /// Bind the vault to the token it will hold.
    pub fn __constructor(env: Env, token: Address) {
        env.storage().instance().set(&DataKey::Token, &token);
    }

    /// Pull `amount` of the token from `from` into the vault and credit them.
    pub fn deposit(env: Env, from: Address, amount: i128) {
        from.require_auth();
        let token: Address = env.storage().instance().get(&DataKey::Token).unwrap();
        token::TokenClient::new(&env, &token).transfer(
            &from,
            &env.current_contract_address(),
            &amount,
        );
        let key = DataKey::Balance(from);
        let bal: i128 = env.storage().persistent().get(&key).unwrap_or(0);
        env.storage().persistent().set(&key, &(bal + amount));
    }

    /// Return `amount` of the token to `from`, if they have the balance.
    pub fn withdraw(env: Env, from: Address, amount: i128) {
        from.require_auth();
        let key = DataKey::Balance(from.clone());
        let bal: i128 = env.storage().persistent().get(&key).unwrap_or(0);
        // The core invariant: no one withdraws more than they deposited.
        assert!(bal >= amount);
        env.storage().persistent().set(&key, &(bal - amount));
        let token: Address = env.storage().instance().get(&DataKey::Token).unwrap();
        token::TokenClient::new(&env, &token).transfer(
            &env.current_contract_address(),
            &from,
            &amount,
        );
    }

    /// A user's current deposited balance.
    pub fn balance(env: Env, from: Address) -> i128 {
        env.storage()
            .persistent()
            .get(&DataKey::Balance(from))
            .unwrap_or(0)
    }
}
