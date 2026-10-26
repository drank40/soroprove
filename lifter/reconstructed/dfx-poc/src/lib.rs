#![no_std]
soroban_sdk::contractimport!(file = "dfx.wasm");

#[cfg(test)]
mod test {
    extern crate std;
    use std::println;
    use soroban_sdk::{Env, Address, Vec, Map, String, testutils::Address as _, token};
    use super::{WASM, Client, AssetStrategySet, Strategy};

    fn setup() -> (Env, Client<'static>, Address, Address) {
        let env = Env::default();
        env.mock_all_auths();
        env.cost_estimate().budget().reset_unlimited();
        let admin = Address::generate(&env);
        let tok = env.register_stellar_asset_contract_v2(admin.clone());
        let token = tok.address();
        let mgr = Address::generate(&env);
        let proto = Address::generate(&env);
        let router = Address::generate(&env);
        let mut assets = Vec::new(&env);
        assets.push_back(AssetStrategySet { address: token.clone(), strategies: Vec::<Strategy>::new(&env) });
        let mut roles = Map::new(&env);
        roles.set(0u32, mgr.clone()); roles.set(1u32, mgr.clone()); roles.set(2u32, mgr.clone()); roles.set(3u32, mgr.clone());
        let mut ns = Map::new(&env);
        ns.set(String::from_str(&env,"name"), String::from_str(&env,"V"));
        ns.set(String::from_str(&env,"symbol"), String::from_str(&env,"V"));
        let pool = Client::new(&env, &env.register(WASM,
            (assets, roles, 0u32, proto, 0u32, router, ns, false)));
        (env, pool, token, admin)
    }

    #[test]
    fn deposit_withdraw_roundtrip_no_profit() {
        let (env, pool, token, admin) = setup();
        let tc = token::TokenClient::new(&env,&token);
        let sac = token::StellarAssetClient::new(&env,&token);
        let v = Address::generate(&env);
        let d: i128 = 1_000_000_000;
        sac.mint(&v, &d);
        let before = tc.balance(&v);
        let mut ad = Vec::new(&env); ad.push_back(d);
        let mut amin = Vec::new(&env); amin.push_back(0i128);
        let (_a, shares, _o) = pool.deposit(&ad, &amin, &v, &false);
        let mut mout = Vec::new(&env); mout.push_back(0i128);
        let bal = pool.balance(&v); pool.withdraw(&bal, &mout, &v);
        let after = tc.balance(&v);
        println!("[dfx-rt] deposited={} shares={} end_balance={} (net {})", d, shares, after, after-before);
        assert!(after <= before, "deposit/withdraw round-trip must not profit: end {} > start {}", after, before);
    }

    #[test]
    fn first_deposit_inflation_unprofitable() {
        let (env, pool, token, admin) = setup();
        let tc = token::TokenClient::new(&env,&token);
        let sac = token::StellarAssetClient::new(&env,&token);
        let atk = Address::generate(&env);
        let donate: i128 = 100_000_000;
        sac.mint(&atk, &(2000 + donate));
        let atk_cost = tc.balance(&atk);
        // attacker first deposit (must be > 1000 dead shares)
        let mut ad = Vec::new(&env); ad.push_back(2000i128);
        let mut amin = Vec::new(&env); amin.push_back(0i128);
        let (_a, shares_atk, _o) = pool.deposit(&ad, &amin, &atk, &false);
        // donate directly to the vault to inflate share price
        tc.transfer(&atk, &pool.address, &donate);
        // victim deposits
        let vic = Address::generate(&env);
        let dv: i128 = 200_000_000;
        sac.mint(&vic, &dv);
        let mut adv = Vec::new(&env); adv.push_back(dv);
        let (_a2, shares_vic, _o2) = pool.deposit(&adv, &amin, &vic, &false);
        // attacker withdraws everything they can
        let mut mout = Vec::new(&env); mout.push_back(0i128);
        let ba=pool.balance(&atk); pool.withdraw(&ba, &mout, &atk);
        let atk_final = tc.balance(&atk);
        println!("[dfx-inf] atk_cost={} shares_atk={} victim_dep={} shares_vic={} atk_final={} (profit {})",
                 atk_cost, shares_atk, dv, shares_vic, atk_final, atk_final - atk_cost);
        assert!(atk_final <= atk_cost, "INFLATION PROFITABLE -> drain: attacker final {} > cost {}", atk_final, atk_cost);
    }
}
