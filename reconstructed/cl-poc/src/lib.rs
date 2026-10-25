#![no_std]
pub type SqrtPriceX96 = soroban_sdk::U256;
soroban_sdk::contractimport!(file = "cl.wasm");

#[cfg(test)]
mod test {
    extern crate std;
    use std::println;
    use soroban_sdk::{contract, contractimpl, Env, Address, Bytes, U256, testutils::{Address as _, Ledger as _}, token};
    use super::{WASM, Client};

    #[contract] pub struct MockFactory;
    #[contractimpl] impl MockFactory {
        pub fn get_protocol_fee_0(_e: Env) -> u32 { 0 }
        pub fn get_protocol_fee_1(_e: Env) -> u32 { 0 }
        pub fn get_owner(e: Env) -> Address { e.current_contract_address() }
    }

    const MIN1: [u8;32] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,2,118,164];
    const MAXm1: [u8;32] = [0,0,0,0,0,0,0,0,0,0,0,0,255,253,137,99,239,209,252,106,80,100,136,73,93,149,29,82,99,152,141,37];
    const Q96: [u8;32] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0];

    fn u256(e:&Env,b:&[u8;32])->U256 { U256::from_be_bytes(e,&Bytes::from_array(e,b)) }

    fn setup() -> (Env, Client<'static>, Address, Address, super::OracleHints) {
        let env = Env::default();
        env.mock_all_auths();
        env.cost_estimate().budget().reset_unlimited();
        env.ledger().set_timestamp(1_000_000);
        let admin=Address::generate(&env); let factory=env.register(MockFactory,()); let flash=Address::generate(&env);
        let ta=env.register_stellar_asset_contract_v2(admin.clone());
        let tb=env.register_stellar_asset_contract_v2(admin.clone());
        let (t0,t1)= if ta.address()<tb.address() {(ta.address(),tb.address())} else {(tb.address(),ta.address())};
        let pool=Client::new(&env,&env.register(WASM,(factory,t0.clone(),t1.clone(),3000u32,60i32,flash,admin)));
        pool.initialize(&u256(&env,&Q96));
        let hints=pool.get_oracle_hints();
        // seed liquidity around tick 0 (range [-600,600], multiples of tick_spacing 60)
        let lp=Address::generate(&env);
        token::StellarAssetClient::new(&env,&t0).mint(&lp,&1_000_000_000_000_000i128);
        token::StellarAssetClient::new(&env,&t1).mint(&lp,&1_000_000_000_000_000i128);
        pool.mint(&lp,&lp,&-600i32,&600i32,&100_000_000_000u128,&hints);
        (env, pool, t0, t1, hints)
    }

    #[test]
    fn roundtrip_swap_cannot_profit() {
        let (env, pool, t0, t1, hints) = setup();
        let t0c=token::TokenClient::new(&env,&t0); let t1c=token::TokenClient::new(&env,&t1);
        let atk=Address::generate(&env);
        let x:i128=1_000_000_000; // input token0
        token::StellarAssetClient::new(&env,&t0).mint(&atk,&x);
        let b0=t0c.balance(&atk);
        // 0 -> 1 (price down): limit just above MIN
        pool.swap(&atk,&atk,&true,&x,&u256(&env,&MIN1),&hints);
        let g1=t1c.balance(&atk);
        // 1 -> 0 (price up): limit just below MAX
        pool.swap(&atk,&atk,&false,&(g1 as i128),&u256(&env,&MAXm1),&hints);
        let b0f=t0c.balance(&atk);
        println!("[cl-rt] start_t0={} got_t1={} end_t0={} (delta {})", b0, g1, b0f, b0f-b0);
        assert!(b0f < b0, "ROUND-TRIP SWAP PROFITED -> value extraction/drain bug: end {} >= start {}", b0f, b0);
    }

    #[test]
    fn out_of_range_position_earns_no_fees() {
        let (env, pool, t0, t1, hints) = setup();
        let t0c=token::TokenClient::new(&env,&t0); let t1c=token::TokenClient::new(&env,&t1);
        // attacker mints a position FAR above current price (tick 0) -> out of range, single-sided token0
        let atk=Address::generate(&env);
        token::StellarAssetClient::new(&env,&t0).mint(&atk,&1_000_000_000_000i128);
        token::StellarAssetClient::new(&env,&t1).mint(&atk,&1_000_000_000_000i128);
        let p0=t0c.balance(&atk); let p1=t1c.balance(&atk);
        let (a0,a1)=pool.mint(&atk,&atk,&6000i32,&6060i32,&50_000_000_000u128,&hints);
        // generate real fees with in-range swaps (price stays near tick 0, never reaches 6000)
        let tr=Address::generate(&env);
        token::StellarAssetClient::new(&env,&t0).mint(&tr,&100_000_000_000i128);
        token::StellarAssetClient::new(&env,&t1).mint(&tr,&100_000_000_000i128);
        let tick_before = pool.slot0().tick;
        for _ in 0..3 {
            let b=t1c.balance(&tr);
            pool.swap(&tr,&tr,&true,&1_000_000i128,&u256(&env,&MIN1),&hints);   // 0->1 exact-in 1M
            let recv=t1c.balance(&tr)-b;                                        // token1 actually received
            pool.swap(&tr,&tr,&false,&(recv as i128),&u256(&env,&MAXm1),&hints);// swap back ONLY the delta
        }
        let tick_after = pool.slot0().tick;
        println!("[cl-fee] tick before={} after={} (attacker range [6000,6060] crossed? {})",
                 tick_before, tick_after, tick_after>=6000);
        // attacker exits: burn + collect. Out-of-range => zero fees; should get back <= deposited.
        pool.burn(&atk,&6000i32,&6060i32,&50_000_000_000u128,&hints);
        let (c0,c1)=pool.collect(&atk,&atk,&6000i32,&6060i32,&u128::MAX,&u128::MAX);
        let q0=t0c.balance(&atk); let q1=t1c.balance(&atk);
        println!("[cl-fee] deposited=({},{}) collected=({},{}) net=({},{})", a0,a1,c0,c1, q0-p0, q1-p1);
        assert!(q0<=p0 && q1<=p1, "OUT-OF-RANGE POSITION EARNED FEES -> fee-theft/drain: net ({},{})", q0-p0, q1-p1);
    }

    #[test]
    fn mint_burn_roundtrip_cannot_profit() {
        let (env, pool, t0, t1, hints) = setup();
        let t0c=token::TokenClient::new(&env,&t0); let t1c=token::TokenClient::new(&env,&t1);
        let lp2=Address::generate(&env);
        token::StellarAssetClient::new(&env,&t0).mint(&lp2,&1_000_000_000_000i128);
        token::StellarAssetClient::new(&env,&t1).mint(&lp2,&1_000_000_000_000i128);
        let p0=t0c.balance(&lp2); let p1=t1c.balance(&lp2);
        let (a0,a1)=pool.mint(&lp2,&lp2,&-600i32,&600i32,&50_000_000_000u128,&hints);
        pool.burn(&lp2,&-600i32,&600i32,&50_000_000_000u128,&hints);
        let (c0,c1)=pool.collect(&lp2,&lp2,&-600i32,&600i32,&u128::MAX,&u128::MAX);
        let q0=t0c.balance(&lp2); let q1=t1c.balance(&lp2);
        println!("[cl-mb] deposited=({},{}) collected=({},{}) net=({},{})", a0,a1,c0,c1, q0-p0, q1-p1);
        assert!(q0<=p0 && q1<=p1, "MINT-BURN ROUND-TRIP PROFITED -> drain bug: net ({},{})", q0-p0, q1-p1);
    }
}
