//! HOT bridge (cc74acb5) — the three security-critical exports, decompiled.
//!
//! Grounded in stellar-diver-mir output: the control flow, auth, nonce, storage,
//! signature and transfer calls are the tool's reconstruction (see
//! hot-bridge.partial.rs / hot-bridge.rust.rs). The RLP + SHA256 message
//! construction is shown as `bridge_message(...)` — the tool recovers it as
//! calls into the `rlp` crate + host sha256; the exact byte layout is in the
//! --rust output. Comments marked AUDIT are review notes, not tool output.

use soroban_sdk::{contract, contractimpl, token, Address, Bytes, BytesN, Env, String, Symbol, vec};

#[contract]
pub struct Contract;

#[contractimpl]
impl Contract {
    /// Withdraw `amount` of `token` to `receiver`, authorised by an off-chain
    /// secp256k1 signature over the withdrawal parameters.
    pub fn withdraw(env: Env, amount: u128, nonce: u128, token: Address, receiver: Address, signature: BytesN<65>) {
        // signature must be 65 bytes (64 r||s + 1 recovery id).  [tool: and59==65<<32]

        // AUDIT replay protection: reject a nonce already spent, and ...
        if env.storage().persistent().has(&(Symbol::new(&env, "WithdrawNonce"), nonce)) {
            panic!();
        }

        // A validity window on a deadline carried in the signed message
        // (tool: u128_div_rem + `now - deadline > 2_160_000s` ~= 25 days).
        let now = env.ledger().timestamp();
        if /* deadline outside the window */ false {
            // emits an event, then reverts
            // env.events().publish(...);
            panic!();
        }

        // AUDIT ... mark it spent BEFORE paying out (no reentrancy-replay).
        env.storage().persistent().set(&(Symbol::new(&env, "WithdrawNonce"), nonce), &true);
        env.storage().persistent().extend_ttl(&(Symbol::new(&env, "WithdrawNonce"), nonce), 501_120, 518_400);

        // The signed message: RLP([receiver, token, amount, nonce, ...]) then SHA256.
        let message: Bytes = bridge_message(&env, &receiver, &token, amount, nonce);
        let hash = env.crypto().sha256(&message);

        // AUDIT the signature check IS enforced: recover the signer and require
        // it equals the stored public key; transfer only on match.
        let public_key: BytesN<65> = env.storage().instance().get(&vec![&env, Symbol::new(&env, "PublicKey")]).unwrap();
        let r_s: BytesN<64> = /* signature[0..64] */ unimplemented!();
        let recovery_id: u32 = /* signature[64] */ unimplemented!();
        let recovered = env.crypto().secp256k1_recover(&hash, &r_s, recovery_id);
        if recovered == public_key {                         // tool: obj_cmp(..)==0
            token::Client::new(&env, &token).transfer(&env.current_contract_address(), &receiver, &(amount as i128));
        } else {
            panic!();
        }
    }

    /// Lock `amount` of `token` from `sender_id`, recording a deposit commitment
    /// keyed by a client-chosen timestamp; returns the nonce/id.
    pub fn deposit(env: Env, sender_id: Address, amount: u128, token: Address, receiver_id: BytesN<32>, client_timestamp: u128) -> u128 {
        // PublicKey must be configured (contract initialised).
        if !env.storage().instance().has(&vec![&env, Symbol::new(&env, "PublicKey")]) {
            panic!();
        }
        // client_timestamp must sit within a window of ledger time
        // (tool: two get_ledger_timestamp reads + `now - 120s .. now` bounds).
        let now = env.ledger().timestamp();
        // if client_timestamp too old / too far ahead { panic!() }

        sender_id.require_auth();
        token::Client::new(&env, &token).transfer(&sender_id, &env.current_contract_address(), &(amount as i128));

        // AUDIT the duplicate check is AFTER the transfer; safe only because the
        // panic reverts the whole tx atomically. Keyed by the caller-chosen
        // client_timestamp, so two deposits in the same instant collide (the
        // second reverts) — availability nit, not loss.
        if env.storage().persistent().has(&(Symbol::new(&env, "DepositNonce"), client_timestamp)) {
            panic!();
        }
        let commitment = env.crypto().sha256(&bridge_deposit_message(&env, &receiver_id, &token, amount, client_timestamp));
        env.storage().persistent().set(&(Symbol::new(&env, "DepositNonce"), client_timestamp), &commitment);
        env.storage().instance().extend_ttl(1_728_000, 2_073_600);
        client_timestamp
    }

    /// HOT-wallet auth callback: true iff `data`'s stored record for `wallet_id`
    /// matches (tool: copy data[0..48], look up the 32-byte stored value by
    /// wallet_id, compare; returns `cmp == 0`).
    pub fn hot_verify(env: Env, wallet_id: String, data: BytesN<48>) -> bool {
        let key = /* derived from wallet_id */ (Symbol::new(&env, "?"), wallet_id);
        if !env.storage().persistent().has(&key) {
            panic!();
        }
        let stored: BytesN<32> = env.storage().persistent().get(&key).unwrap();
        // AUDIT returns true only when the stored 32 bytes equal data[..32]
        // (tool: obj_cmp / memcmp == 0). Confirm what `data`'s remaining bytes
        // and wallet_id binding are against the HOT protocol spec.
        stored.as_ref() == &data.to_array()[..32]
    }
}

// The message the signature is checked against, reverse-engineered from the
// complete reconstruction (hot-bridge.rust.rs). Both entry points build the
// same 5-element RLP list, then SHA256 it. Field order and encoding:
//
//   RLP([
//     key,                 // withdraw: nonce; deposit: client_timestamp
//                          //   -- u128, big-endian, 16 bytes (llvm_bswap of lo/hi)
//     DOMAIN,              // fixed 0x4c04_0000_0000_0000 (bytes 4C 04 ..) --
//                          //   a code-level constant, IDENTICAL in withdraw and
//                          //   deposit; NOT the contract address or a per-instance value
//     recipient,           // withdraw: receiver.to_xdr()  (Address, XDR bytes)
//                          // deposit:  receiver_id         (raw 32 bytes, the far-chain address)
//     token,               // token.to_xdr()               (Address, XDR bytes)
//     amount,              // u128, big-endian, 16 bytes
//   ])  then  env.crypto().sha256(rlp_bytes)
//
// SECURITY NOTE: the signed message binds key(nonce/ts), amount, recipient,
// token, and the fixed DOMAIN -- but NOT the contract's own address. Two
// deployments of this exact code that shared a signing public key would accept
// each other's withdrawal signatures (cross-instance replay). Per instance
// (its own key via set_public_key) this is safe; flag it only if key reuse
// across deployments is possible. DOMAIN is constant, so it is a version tag,
// not a chain/instance separator.
fn bridge_message(env: &Env, receiver: &Address, token: &Address, amount: u128, nonce: u128) -> Bytes {
    const DOMAIN: u64 = 0x4c04_0000_0000_0000;
    let mut s = rlp::RlpStream::new_list(5);
    s.append(&nonce.to_be_bytes().as_slice());
    s.append(&DOMAIN.to_be_bytes().as_slice());   // width per the lifted length word (~4 bytes of 4C 04 ..)
    s.append(&receiver.to_xdr(env).to_alloc_vec());
    s.append(&token.to_xdr(env).to_alloc_vec());
    s.append(&amount.to_be_bytes().as_slice());
    Bytes::from_slice(env, &s.out())              // -> env.crypto().sha256(..) at the call site
}
fn bridge_deposit_message(env: &Env, receiver_id: &BytesN<32>, token: &Address, amount: u128, ts: u128) -> Bytes {
    const DOMAIN: u64 = 0x4c04_0000_0000_0000;
    let mut s = rlp::RlpStream::new_list(5);
    s.append(&ts.to_be_bytes().as_slice());
    s.append(&DOMAIN.to_be_bytes().as_slice());
    s.append(&receiver_id.to_array().as_slice()); // raw 32 bytes, not XDR
    s.append(&token.to_xdr(env).to_alloc_vec());
    s.append(&amount.to_be_bytes().as_slice());
    Bytes::from_slice(env, &s.out())
}
