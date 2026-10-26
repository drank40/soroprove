#![no_std]
soroban_sdk::contractimport!(file = "src/vault.wasm");

#[cfg(test)]
mod test {
    extern crate std;
    use std::println;
    use soroban_sdk::{Env, Address, IntoVal,
        testutils::{Address as _, MockAuth, MockAuthInvoke}, token};
    use super::{WASM, Client};

    fn setup() -> (Env, Client<'static>, Address, Address) {
        let env = Env::default();
        env.mock_all_auths();
        let admin = Address::generate(&env);
        let escrow = Address::generate(&env);
        let asset_admin = Address::generate(&env);
        let sac = env.register_stellar_asset_contract_v2(asset_admin.clone());
        let asset = sac.address();
        let vault = Client::new(&env, &env.register(WASM, (admin.clone(), asset.clone(), escrow.clone())));
        (env, vault, asset, admin)
    }

    // Property #1 (fork-flagged): withdraw is scoped to the caller's own record + require_auth(from).
    #[test]
    fn attacker_cannot_take_others_or_over_withdraw() {
        let (env, vault, asset, _admin) = setup();
        let alice = Address::generate(&env);
        let attacker = Address::generate(&env);
        let sac = token::StellarAssetClient::new(&env, &asset);
        sac.mint(&alice, &1_000_000_000i128);
        sac.mint(&attacker, &100_000_000i128);
        let tok = token::TokenClient::new(&env, &asset);

        // Honest deposits (all-auths mocked).
        env.mock_all_auths();
        vault.deposit(&alice, &1_000_000_000u128, &None);
        vault.deposit(&attacker, &100_000_000u128, &None);
        let vbal = tok.balance(&vault.address);
        println!("[vault] holds {} after deposits (alice 1e9 + attacker 1e8)", vbal);
        assert_eq!(vbal, 1_100_000_000i128);

        // ATTACK 1: attacker calls withdraw(from=Alice); ONLY attacker's auth is present.
        // Contract does require_auth(Alice) -> no matching mock -> must fail.
        let r1 = vault.mock_auths(&[MockAuth {
            address: &attacker,
            invoke: &MockAuthInvoke {
                contract: &vault.address, fn_name: "withdraw",
                args: (alice.clone(), 500_000_000u128).into_val(&env), sub_invokes: &[],
            },
        }]).try_withdraw(&alice, &500_000_000u128);
        println!("[attack1] attacker withdraw(from=Alice,500) -> {:?}", r1);
        assert!(r1.is_err(), "SECURITY: attacker withdrew Alice's funds");

        // ATTACK 2: attacker over-withdraws own record (deposited 1e8, asks 1e9).
        let r2 = vault.mock_auths(&[MockAuth {
            address: &attacker,
            invoke: &MockAuthInvoke {
                contract: &vault.address, fn_name: "withdraw",
                args: (attacker.clone(), 1_000_000_000u128).into_val(&env), sub_invokes: &[],
            },
        }]).try_withdraw(&attacker, &1_000_000_000u128);
        println!("[attack2] attacker over-withdraw(1e9 vs 1e8) -> {:?}", r2);
        assert!(r2.is_err(), "SECURITY: attacker over-withdrew own record");

        // CONTROL: Alice legitimately withdraws 500 with her own auth -> succeeds, exact amount.
        let before = tok.balance(&alice);
        vault.mock_auths(&[MockAuth {
            address: &alice,
            invoke: &MockAuthInvoke {
                contract: &vault.address, fn_name: "withdraw",
                args: (alice.clone(), 500_000_000u128).into_val(&env), sub_invokes: &[],
            },
        }]).withdraw(&alice, &500_000_000u128);
        let delta = tok.balance(&alice) - before;
        println!("[control] Alice legit withdraw delta = {}", delta);
        assert_eq!(delta, 500_000_000i128);

        // Vault solvency after: holds exactly remaining records (alice 5e8 + attacker 1e8).
        let vbal2 = tok.balance(&vault.address);
        println!("[vault] holds {} after Alice's 5e8 withdraw", vbal2);
        assert_eq!(vbal2, 600_000_000i128);
    }
}
