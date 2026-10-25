#![no_std]
//! Reconstructed by stellar-diver-mir --contract: the contract as soroban-sdk source.
//! An export that could not be said at this level is a `todo!()` naming why.
#![allow(unused_imports, unused_mut, unused_variables, unreachable_code, unused_parens, non_snake_case, clippy::all)]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, panic_with_error, symbol_short, token, vec, Address, Bytes, BytesN, Duration, Env,
    I256, Map, String, Symbol, Timepoint, U256, Val, Vec,
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
        let mut get_ledger_timestamp_2;
        let mut l1_0;
        get_ledger_timestamp_2 = env.ledger().timestamp();
        // not reconstructed: branch on (obj_to_u64_8 < 72057594037927936u64)
        if obj_to_u64_8 < 72057594037927936u64 {
            l1_0 = Val((obj_to_u64_8.wrapping_shl(8u64 as u32)) | 6u64); // not reconstructed: not reconstructed: (obj_to_u64_8.wrapping_shl(8u64 as u32)) | 6u64
        } else {
            l1_0 = obj_from_u64_11; // not reconstructed: not reconstructed: obj_from_u64_11.0
        }
        l1_0
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
        let mut bytes_copy_to_linear_memory_12;
        let mut lc;
        let mut bytes_copy_to_linear_memory199;
        let mut or67;
        let mut or96;
        let mut lc100;
        let mut get_contract_data_72;
        let mut to_val9;
        let mut to_val;
        to_val9 = ((slot96 as u32) as u64);
        llvm_memset_p0_i64(slot96, 0u8, 48u64, false); // not reconstructed: call to llvm_memset_p0_i64
        bytes_copy_to_linear_memory(data, Val::u32(0), to_val9, Val::u32(48)); // not reconstructed: call to bytes_copy_to_linear_memory
        or67 = llvm_bswap_i64(ld32); // not reconstructed: not reconstructed: _80[12]
        or96 = llvm_bswap_i64(v); // not reconstructed: not reconstructed: _80[13]
        lc100 = from_val(((frame.wrapping_offset(72isize) as u32) as u64)); // Vec[Symbol("DepositNonce"), u128(hot_verify::or67, hot_verify::or96)] // not reconstructed: call to from_val
        if env.storage().persistent().has(&lc100) {
            get_contract_data_72 = env.storage().persistent().get(&lc100).unwrap();
            llvm_memset_p0_i64(slot96, 0u8, 32u64, false); // not reconstructed: call to llvm_memset_p0_i64
            bytes_copy_to_linear_memory(get_contract_data_72, Val::u32(0), to_val9, Val::u32(32)); // not reconstructed: call to bytes_copy_to_linear_memory
            lc = memcmp(fp27, ((slot40 as u32) as u64)); // not reconstructed: call to memcmp
            to_val = Val((lc == 0u64) as u64); // not reconstructed: not reconstructed: (lc == 0u64) as u64
            return;
        } else {
            panic!();
        }
        panic!();
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
        let mut get_ledger_timestamp_40;
        let mut _54;
        let mut bytes_copy_to_linear_memory_57;
        let mut bytes_new_from_linear_memory_81;
        let mut recover_key_ecdsa_secp256k1_87;
        let mut obj_cmp_91;
        let mut lc349;
        let mut bytes_new_from_linear_memory134;
        let mut lc311;
        let mut l14_0;
        let mut get_contract_data_187;
        'b31: {
            // not reconstructed: branch on cmp52_not
            if cmp52_not {
                // not reconstructed: branch on and59
                match and59 {
                    279172874240 => {
                        if env.storage().persistent().has(&(Symbol::new(&env, "WithdrawNonce"), nonce)) {
                            panic!();
                        } else {
                            u128_div_rem(((frame91 as u32) as u64), l1_0, l8_0); // not reconstructed: call to u128_div_rem
                            get_ledger_timestamp_40 = env.ledger().timestamp();
                            // not reconstructed: branch on (ld5 == z_neg)
                            // not reconstructed: branch on cmp
                            if cmp {
                                lc349 = into_val(((slot144344 as u32) as u64)); // Vec[String(at Val::u32((_ as u64) as u32), Val::u32((_ as u64) as u32))] // not reconstructed: call to into_val
                                Env_contract_event(lc349, lc354); // not reconstructed: value not reconstructed: Vec[String(at Val::u32((_ as u64) as u32), Val::u32((_ as u64) as u32))]
                                panic!();
                            } else {
                                env.storage().persistent().set(&(Symbol::new(&env, "WithdrawNonce"), nonce), &true);
                                env.storage().persistent().extend_ttl(&(Symbol::new(&env, "WithdrawNonce"), nonce), 501120, 518400);
                                Bytes_to_alloc_vec(((frame92.wrapping_offset(68isize) as u32) as u64), fp51); // not reconstructed: call to Bytes_to_alloc_vec
                                Bytes_to_alloc_vec(((frame92.wrapping_offset(80isize) as u32) as u64), fp51); // not reconstructed: call to Bytes_to_alloc_vec
                                RlpStream_new_list(fp60); // not reconstructed: call to RlpStream_new_list
                                rlp_append(fp120, fp60); // not reconstructed: call to rlp_append
                                // not reconstructed: branch on ld124
                                match ld124 {
                                    0 => {
                                        RlpStream_note_appended(fp60); // not reconstructed: call to RlpStream_note_appended
                                    }
                                    _ => {}
                                }
                                rlp_append(fp120, fp60); // not reconstructed: call to rlp_append
                                // not reconstructed: branch on ld140
                                match ld140 {
                                    0 => {
                                        RlpStream_note_appended(fp60); // not reconstructed: call to RlpStream_note_appended
                                    }
                                    _ => {}
                                }
                                rlp_append(fp51, fp60); // not reconstructed: call to rlp_append
                                // not reconstructed: branch on ld158
                                match ld158 {
                                    0 => {
                                        RlpStream_note_appended(fp60); // not reconstructed: call to RlpStream_note_appended
                                    }
                                    _ => {}
                                }
                                rlp_append(fp51, fp60); // not reconstructed: call to rlp_append
                                // not reconstructed: branch on ld177
                                match ld177 {
                                    0 => {
                                        RlpStream_note_appended(fp60); // not reconstructed: call to RlpStream_note_appended
                                    }
                                    _ => {}
                                }
                                rlp_append(fp120, fp60); // not reconstructed: call to rlp_append
                                // not reconstructed: branch on ld253
                                match ld253 {
                                    0 => {
                                        RlpStream_note_appended(fp60); // not reconstructed: call to RlpStream_note_appended
                                    }
                                    _ => {}
                                }
                                RlpStream_out(fp120, fp51); // not reconstructed: call to RlpStream_out
                                'b23: {
                                    // not reconstructed: branch on ld277
                                    match ld277 {
                                        0 => {}
                                        _ => {
                                            l14_0 = __rust_alloc(zx278, 1u64); // not reconstructed: call to __rust_alloc
                                            break 'b23;
                                            panic!();
                                        }
                                    }
                                }
                                // not reconstructed: branch on (_286 & 1u32)
                                match _286 & 1u32 {
                                    0 => {}
                                    _ => {}
                                }
                                bytes_new_from_linear_memory134 = bytes_new_from_linear_memory(Val::u32(l14_0 as u32), Val::u32(zx278 as u32)); // not reconstructed: call to bytes_new_from_linear_memory
                                lc311 = vec![&env, Symbol::new(&env, "PublicKey")];
                                if env.storage().instance().has(&lc311) {
                                    get_contract_data_187 = env.storage().instance().get(&lc311).unwrap();
                                    memset(fp51, 65u64); // withdraw::fp51 // not reconstructed: call to memset
                                    bytes_copy_to_linear_memory(signature, Val::u32(0), Val::u32(fp51 as u32), Val::u32(65)); // not reconstructed: call to bytes_copy_to_linear_memory
                                    bytes_new_from_linear_memory_81 = bytes_new_from_linear_memory(Val::u32(fp120 as u32), Val::u32(64)); // not reconstructed: call to bytes_new_from_linear_memory
                                    recover_key_ecdsa_secp256k1_87 = recover_key_ecdsa_secp256k1(Val(_224[16]), bytes_new_from_linear_memory_81, Val::u32(zx388 as u32)); // not reconstructed: value not reconstructed: withdraw::zx388
                                    obj_cmp_91 = obj_cmp(recover_key_ecdsa_secp256k1_87, Val(_224[17])); // not reconstructed: value not reconstructed: withdraw::payload142
                                    token::Client::new(&env, &token.clone()).transfer(&env.current_contract_address(), &receiver.clone(), &(amount as i128));
                                    return;
                                } else {
                                    panic!();
                                }
                            }
                        }
                    }
                    _ => {
                        break 'b31;
                    }
                }
            } else {
                break 'b31;
            }
        }
        panic!();
    }

    pub fn deposit(env: Env, sender_id: Address, amount: u128, token: Address, receiver_id: BytesN<32>, client_timestamp: u128) -> u128 {
        let mut get_ledger_timestamp_54;
        let mut get_ledger_timestamp131;
        let mut bytes_copy_to_linear_memory_126;
        let mut lc330;
        let mut bytes_new_from_linear_memory_190;
        let mut obj_from_u128_pieces_205;
        let mut l3_0;
        if env.storage().instance().has(&vec![&env, Symbol::new(&env, "PublicKey")]) {
            get_ledger_timestamp_54 = env.ledger().timestamp();
            // not reconstructed: branch on (add28 == l8_0)
            get_ledger_timestamp131 = env.ledger().timestamp();
            // not reconstructed: branch on (add28156 == l8_0)
            sender_id.clone().require_auth();
            token::Client::new(&env, &token.clone()).transfer(&sender_id.clone(), &env.current_contract_address(), &(amount as i128));
            llvm_memset_p0_i64(slot152, 0u8, 32u64, false); // not reconstructed: call to llvm_memset_p0_i64
            bytes_copy_to_linear_memory(receiver_id, Val::u32(0), to_val9, Val::u32(32)); // not reconstructed: call to bytes_copy_to_linear_memory
            Bytes_to_alloc_vec(((frame112.wrapping_offset(84isize) as u32) as u64), fp57); // not reconstructed: call to Bytes_to_alloc_vec
            if env.storage().persistent().has(&(Symbol::new(&env, "DepositNonce"), client_timestamp)) {
                panic!();
            } else {
                RlpStream_new_list(fp55); // not reconstructed: call to RlpStream_new_list
                rlp_append(fp164, fp55); // not reconstructed: call to rlp_append
                // not reconstructed: branch on ld168
                match ld168 {
                    0 => {
                        RlpStream_note_appended(fp55); // not reconstructed: call to RlpStream_note_appended
                    }
                    _ => {}
                }
                rlp_append(fp164, fp55); // not reconstructed: call to rlp_append
                // not reconstructed: branch on ld184
                match ld184 {
                    0 => {
                        RlpStream_note_appended(fp55); // not reconstructed: call to RlpStream_note_appended
                    }
                    _ => {}
                }
                rlp_append(fp57, fp55); // not reconstructed: call to rlp_append
                // not reconstructed: branch on ld202
                match ld202 {
                    0 => {
                        RlpStream_note_appended(fp55); // not reconstructed: call to RlpStream_note_appended
                    }
                    _ => {}
                }
                rlp_append(fp57, fp55); // not reconstructed: call to rlp_append
                // not reconstructed: branch on ld218
                match ld218 {
                    0 => {
                        RlpStream_note_appended(fp55); // not reconstructed: call to RlpStream_note_appended
                    }
                    _ => {}
                }
                rlp_append(fp164, fp55); // not reconstructed: call to rlp_append
                // not reconstructed: branch on ld294
                match ld294 {
                    0 => {
                        RlpStream_note_appended(fp55); // not reconstructed: call to RlpStream_note_appended
                    }
                    _ => {}
                }
                RlpStream_out(fp164, fp57); // not reconstructed: call to RlpStream_out
                'b40: {
                    // not reconstructed: branch on ld320
                    match ld320 {
                        0 => {}
                        _ => {
                            lc330 = __rust_alloc(zx321, 1u64); // not reconstructed: call to __rust_alloc
                            break 'b40;
                            panic!();
                        }
                    }
                }
                // not reconstructed: branch on (_263 & 1u32)
                match _263 & 1u32 {
                    0 => {}
                    _ => {}
                }
                bytes_new_from_linear_memory_190 = bytes_new_from_linear_memory(Val::u32(lc330 as u32), Val::u32(zx321 as u32)); // not reconstructed: call to bytes_new_from_linear_memory
                env.storage().instance().extend_ttl(1728000, 2073600);
                env.storage().persistent().set(&(Symbol::new(&env, "DepositNonce"), client_timestamp), &env.crypto().sha256(&bytes_new_from_linear_memory_190));
                env.storage().persistent().extend_ttl(&(Symbol::new(&env, "DepositNonce"), client_timestamp), 501120, 518400);
                'b1: {
                    // not reconstructed: branch on (l8_0 == 0u64)
                    if l8_0 == 0u64 {
                        // not reconstructed: branch on cmp71
                        if cmp71 {
                            l3_0 = Val((l4_0.wrapping_shl(8u64 as u32)) | 10u64); // not reconstructed: not reconstructed: (l4_0.wrapping_shl(8u64 as u32)) | 10u64
                            break 'b1;
                        }
                    }
                    obj_from_u128_pieces_205 = obj_from_u128_pieces(l8_0, l4_0); // u128(hi(client_timestamp), lo(client_timestamp)) // not reconstructed: call to obj_from_u128_pieces
                    l3_0 = obj_from_u128_pieces_205; // not reconstructed: not reconstructed: obj_from_u128_pieces_205.0
                }
                return l3_0;
            }
        } else {
            panic!();
        }
        panic!();
    }

    pub fn get_public_key(env: Env) -> BytesN<65> {
        let mut lc;
        let mut bytes_len_8;
        lc = vec![&env, Symbol::new(&env, "PublicKey")];
        if env.storage().instance().has(&lc) {
            bytes_len_8 = bytes_len(get_contract_data_0); // not reconstructed: not reconstructed: get_contract_data_0
            return env.storage().instance().get(&lc).unwrap();
        } else {
            panic!();
        }
    }

    pub fn is_executed(env: Env, nonce: u128) -> bool {
        env.storage().persistent().has(&(Symbol::new(&env, "WithdrawNonce"), nonce))
    }

    // t_: exported, not in the spec.
}
