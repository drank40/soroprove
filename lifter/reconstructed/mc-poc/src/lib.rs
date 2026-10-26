#![no_std]
soroban_sdk::contractimport!(file = "src/market.wasm");

#[cfg(test)]
mod test {
    extern crate std;
    use std::println;
    use soroban_sdk::{Env, Address, String, Val, contract, contractimpl, contracttype,
        testutils::{Address as _, Ledger as _}, token};
    use super::*; // Client, WASM, and all generated contracttypes

    #[contracttype] #[derive(Clone)] pub struct PriceData { pub price: i128, pub timestamp: u64 }
    #[contracttype] #[derive(Clone)] pub enum OracleAsset { Stellar(Address), Other(soroban_sdk::Symbol) }
    #[contract] pub struct MockOracle;
    #[contractimpl] impl MockOracle {
        pub fn set_price(e: Env, asset: Address, price: i128) { e.storage().instance().set(&asset, &price); }
        pub fn lastprice(e: Env, asset: OracleAsset) -> Option<PriceData> {
            let price = match asset {
                OracleAsset::Stellar(a) => e.storage().instance().get(&a).unwrap_or(100_000_000i128),
                OracleAsset::Other(_) => 100_000_000i128,
            };
            Some(PriceData { price, timestamp: e.ledger().timestamp() })
        }
        pub fn decimals(_e: Env) -> u32 { 8 }
    }

    fn okey(user: &Address) -> ObligationKey { ObligationKey { seed: None, user: user.clone() } }

    fn pool_config() -> PoolConfig {
        PoolConfig {
            accrual_model: AccrualModel::Compounded,
            fee_config: PoolFeeConfig {
                add_collateral_fee_bps: 0, borrow_fee_bps: 0, deposit_fee_bps: 0,
                flash_loan_fee_bps: 0, operation_fee_beneficiaries: None, referrers: None,
                remove_collateral_fee_bps: 0, repay_fee_bps: 0, take_rate_beneficiaries: None,
                take_rate_bps: 0, withdraw_fee_bps: 0, withdraw_max_scarcity_fee_bps: 0,
            },
            health_config: PoolHealthConfig {
                close_ltv_bps: 9000, liability_factor_bps: 10000, liquidation_close_factor_bps: 5000,
                max_liquidation_incentive_bps: 1000, open_ltv_bps: 8000,
                supply_limit: 1_000_000_000_000_000i128, utilization_ratio_limit_bps: 9500,
                withdraw_scarcity_cooldown_s: 0, withdraw_scarcity_limit_bps: 10000,
            },
            interest_rate_model: InterestRateModel::Kinked(KinkedIRConfig {
                base_apr_bps: 0, kink1_apr_bps: 0, kink1_ur_bps: 8000,
                kink2_apr_bps: 0, kink2_ur_bps: 9000, max_apr_bps: 0,
            }),
            ir_reactivity_constant: 0,
            status: PoolStatus { flags: 0xFF },
            target_utilization_ratio_bps: 8000,
        }
    }

    fn setup() -> (Env, Client<'static>, Address) {
        let env = Env::default();
        env.mock_all_auths();
        env.cost_estimate().budget().reset_unlimited();
        env.ledger().set_timestamp(1_000_000);
        let admin = Address::generate(&env);
        let oracle = env.register(MockOracle, ());
        let params = MarketInitParams {
            bad_debt_lock_d: 0, insolvency_ltv_bps: 9500, is_owned: true,
            max_positions: 10, min_collateral_value_cents: 0, update_in_queue_period: 0,
        };
        let market = Client::new(&env, &env.register(WASM,
            (String::from_str(&env, "mkt"), admin.clone(),
             oracle.clone(), Address::generate(&env), Address::generate(&env), params)));
        market.update_market_status(&0u32);
        (env, market, oracle)
    }
    fn oracle_set(env: &Env, oracle: &Address, asset: &Address, price: i128) {
        MockOracleClient::new(env, oracle).set_price(asset, &price);
    }

    fn new_pool(env: &Env, market: &Client) -> (Address, token::TokenClient<'static>, token::StellarAssetClient<'static>) {
        let sac = env.register_stellar_asset_contract_v2(Address::generate(env));
        let addr = sac.address();
        market.queue_in_pool_set(&addr, &pool_config());
        market.apply_pool_set(&addr);
        (addr.clone(), token::TokenClient::new(env, &addr), token::StellarAssetClient::new(env, &addr))
    }

    // Fork A claim: remove_collateral has no health check -> remove all collateral while owing debt -> walk.
    // Result: remove_collateral CAPS the release at the health-safe max (collateral - debt/open_ltv). REFUTED.
    #[test]
    fn remove_collateral_is_capped_by_debt() {
        let (env, market, _oracle) = setup();
        let (tc, tc_tok, tc_mint) = new_pool(&env, &market);
        let (tb, tb_tok, tb_mint) = new_pool(&env, &market);

        let lp = Address::generate(&env);
        tb_mint.mint(&lp, &10_000_000_000i128);
        market.deposit(&okey(&lp), &tb, &10_000_000_000i128, &None);

        // helper: fresh attacker deposits 1e9 collateral, borrows `debt`, then tries to remove ALL collateral.
        let run = |debt: i128| -> i128 {
            let atk = Address::generate(&env);
            tc_mint.mint(&atk, &1_000_000_000i128);
            market.add_collateral(&okey(&atk), &tc, &1_000_000_000i128, &None);
            market.borrow(&okey(&atk), &tb, &debt, &None);
            let b0 = tc_tok.balance(&atk);
            // request to remove everything; measure what actually comes back
            let _ = market.try_remove_collateral(&okey(&atk), &tc, &1_000_000_000i128, &None);
            let released = tc_tok.balance(&atk) - b0;
            // a SECOND attempt must release ~nothing more (cap recomputed each call)
            let b1 = tc_tok.balance(&atk);
            let _ = market.try_remove_collateral(&okey(&atk), &tc, &1_000_000_000i128, &None);
            let extra = tc_tok.balance(&atk) - b1;
            let remaining = 1_000_000_000i128 - released - extra;
            println!("[cap] debt={:>10}  released={:>10} extra={:>3}  remaining_collateral={:>10}  need>=debt/0.8={:>10}",
                     debt, released, extra, remaining, debt * 10000 / 8000);
            // SAFETY INVARIANT: remaining collateral must still cover the debt at open_ltv (0.8) -> solvent.
            assert!(remaining as i128 * 8000 / 10000 >= debt,
                "INSOLVENT: remaining collateral {} * 0.8 < debt {}", remaining, debt);
            released
        };

        let r5 = run(500_000_000);   // expect released 375M, remaining 625M (=5e8/0.8)
        let r2 = run(200_000_000);   // expect released 750M, remaining 250M (=2e8/0.8)
        // cap tracks debt: less debt -> more releasable. If it were a fixed/unbounded bug these wouldn't differ this way.
        assert!(r2 > r5, "cap does not track debt (r2={} r5={})", r2, r5);
        println!("[cap] remove_collateral is debt-aware capped -> Fork A finding is a FALSE POSITIVE");
    }

    // Secondary claim (Fork A): withdraw (f184) skips the health check. Supply (j_tokens) DOES grant
    // borrowing power, so this is the real test: deposit supply, borrow against it, then try to withdraw
    // the collateralizing supply to insolvency. If withdraw releases more than the health-safe max -> CRITICAL.
    #[test]
    fn withdraw_of_collateralizing_supply_is_capped() {
        let (env, market, _oracle) = setup();
        let (tc, tc_tok, tc_mint) = new_pool(&env, &market);
        let (tb, _tb_tok, tb_mint) = new_pool(&env, &market);
        let lp = Address::generate(&env);
        tb_mint.mint(&lp, &10_000_000_000i128);
        market.deposit(&okey(&lp), &tb, &10_000_000_000i128, &None);

        // Attacker supplies 1e9 TC (as borrowing power), borrows 5e8 TB against it.
        let atk = Address::generate(&env);
        tc_mint.mint(&atk, &1_000_000_000i128);
        market.deposit(&okey(&atk), &tc, &1_000_000_000i128, &None);
        let big = market.try_borrow(&okey(&atk), &tb, &500_000_000i128, &None);
        println!("[wd] borrow(5e8) against 1e9 pure supply -> ok={:?} (confirms supply = borrowing power)", big.is_ok());
        assert!(big.is_ok(), "supply did not grant borrowing power; scenario N/A");

        // Try to withdraw ALL supply while owing 5e8. Measure what actually comes back.
        let b0 = tc_tok.balance(&atk);
        let _ = market.try_withdraw(&okey(&atk), &tc, &1_000_000_000i128, &None);
        let released = tc_tok.balance(&atk) - b0;
        let b1 = tc_tok.balance(&atk);
        let _ = market.try_withdraw(&okey(&atk), &tc, &1_000_000_000i128, &None); // 2nd attempt
        let extra = tc_tok.balance(&atk) - b1;
        let remaining = 1_000_000_000i128 - released - extra;
        println!("[wd] withdraw(ALL) with 5e8 debt: released={} extra={} remaining_supply={} need>=debt/0.8={}",
                 released, extra, remaining, 500_000_000i128 * 10000 / 8000);
        // SAFETY: remaining collateralizing supply must still cover the debt at open_ltv -> solvent.
        assert!(remaining * 8000 / 10000 >= 500_000_000i128,
            "*** CRITICAL: withdrew collateralizing supply to INSOLVENCY: remaining {} *0.8 < debt 5e8; attacker keeps 5e8 TB free ***",
            remaining);
        println!("[wd] withdraw is debt-aware capped too -> secondary claim also FALSE POSITIVE");
    }

    // Liquidation: (a) a HEALTHY position can't be liquidated; (b) seized collateral is bounded by the
    // configured max_liquidation_incentive (1000 bps). A liquidator seizing MORE than repay-value*(1+incentive)
    // would be extracting value from the borrower/protocol beyond design = attacker-reachable loss.
    #[test]
    fn liquidation_seize_is_bounded_by_incentive() {
        let (env, market, oracle) = setup();
        let (tc, tc_tok, tc_mint) = new_pool(&env, &market);
        let (tb, tb_tok, tb_mint) = new_pool(&env, &market);
        let lp = Address::generate(&env);
        tb_mint.mint(&lp, &10_000_000_000i128);
        market.deposit(&okey(&lp), &tb, &10_000_000_000i128, &None);

        let borrower = Address::generate(&env);
        tc_mint.mint(&borrower, &1_000_000_000i128);
        market.add_collateral(&okey(&borrower), &tc, &1_000_000_000i128, &None);
        market.borrow(&okey(&borrower), &tb, &500_000_000i128, &None); // healthy at 1:1

        let liq = Address::generate(&env);
        tb_mint.mint(&liq, &10_000_000_000i128);

        // (a) HEALTHY liquidation must fail.
        let healthy = market.try_liquidate(&liq, &okey(&borrower), &tb, &tc, &200_000_000i128, &0i128);
        println!("[liq] liquidate HEALTHY -> err={:?} (expect true / ObligationIsHealthy 601)", healthy.is_err());
        assert!(healthy.is_err(), "*** CRITICAL: liquidated a HEALTHY position ***");

        // Drop TC price to $0.40 -> borrower underwater (collateral 1e9*0.4=4e8*val vs debt 5e8*val).
        oracle_set(&env, &oracle, &tc, 40_000_000i128);
        env.ledger().set_timestamp(2_000_000); // advance so any per-ledger cached price is refetched
        let _ = market.try_refresh_pool(&tc);
        let _ = market.try_refresh_pool(&tb);
        let _ = market.try_refresh_obligation(&okey(&borrower));
        println!("[liq] market sees TC oracle price = {:?}", market.try_get_pool_asset_oracle_price(&tc));

        let repay = 200_000_000i128; // 40% of the 5e8 debt (< 50% close factor)
        let liq_tc0 = tc_tok.balance(&liq);
        let liq_tb0 = tb_tok.balance(&liq);
        let r = market.try_liquidate(&liq, &okey(&borrower), &tb, &tc, &repay, &0i128);
        println!("[liq] liquidate underwater repay={} -> ok={:?}", repay, r.is_ok());
        assert!(r.is_ok(), "liquidation of underwater position failed: {:?}", r);

        let seized_tc = tc_tok.balance(&liq) - liq_tc0;
        let spent_tb = liq_tb0 - tb_tok.balance(&liq);
        // fair max = repay * (price_TB/price_TC) * (1 + max_incentive 10%)
        let cap = repay * 100_000_000 / 40_000_000 * 11000 / 10000;
        let profit_val_tb = seized_tc * 40_000_000 / 100_000_000 - spent_tb; // liquidator net value in TB units
        println!("[liq] repaid_TB={} seized_TC={} incentive_cap_TC={} liq_profit(TBval)={}",
                 spent_tb, seized_tc, cap, profit_val_tb);
        assert!(spent_tb <= repay + 1, "liquidator paid more than repay ({} > {})", spent_tb, repay);
        assert!(seized_tc <= cap + cap / 100,
            "*** SEIZED BEYOND INCENTIVE CAP: seized {} > cap {} -> extractable value ***", seized_tc, cap);
        // borrower must retain the un-seized collateral (no full-collateral grab for a partial repay).
        let borrower_left = 1_000_000_000i128 - seized_tc;
        println!("[liq] borrower retains {} TC after partial liquidation", borrower_left);
        assert!(borrower_left > 0, "*** partial liquidation seized ALL collateral ***");
        println!("[liq] liquidation seize bounded by configured incentive -> SAFE");
    }

    // Self-liquidation: liquidator == borrower. Should not yield a profit path.
    #[test]
    fn self_liquidation_no_free_money() {
        let (env, market, oracle) = setup();
        let (tc, tc_tok, tc_mint) = new_pool(&env, &market);
        let (tb, tb_tok, tb_mint) = new_pool(&env, &market);
        let lp = Address::generate(&env);
        tb_mint.mint(&lp, &10_000_000_000i128);
        market.deposit(&okey(&lp), &tb, &10_000_000_000i128, &None);

        let u = Address::generate(&env);
        tc_mint.mint(&u, &1_000_000_000i128);
        tb_mint.mint(&u, &1_000_000_000i128);
        market.add_collateral(&okey(&u), &tc, &1_000_000_000i128, &None);
        market.borrow(&okey(&u), &tb, &500_000_000i128, &None);
        oracle_set(&env, &oracle, &tc, 40_000_000i128);
        env.ledger().set_timestamp(2_000_000);
        let _ = market.try_refresh_pool(&tc);
        let _ = market.try_refresh_obligation(&okey(&u));

        let tc0 = tc_tok.balance(&u); let tb0 = tb_tok.balance(&u);
        let r = market.try_liquidate(&u, &okey(&u), &tb, &tc, &200_000_000i128, &0i128);
        println!("[selfliq] self-liquidate -> ok={:?}", r.is_ok());
        // whether allowed or not, the user's total value must not increase (no free money).
        let dtc = tc_tok.balance(&u) - tc0; let dtb = tb_tok.balance(&u) - tb0;
        let net_val = dtc * 40_000_000 / 100_000_000 + dtb; // in TB value units
        println!("[selfliq] net token value delta (TBval) = {} (tc {} tb {})", net_val, dtc, dtb);
        assert!(net_val <= 1, "*** SELF-LIQUIDATION NET PROFIT {} -> free money ***", net_val);
        println!("[selfliq] no self-liquidation profit -> SAFE");
    }
}
