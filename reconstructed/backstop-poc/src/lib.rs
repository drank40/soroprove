#![no_std]
soroban_sdk::contractimport!(file = "src/backstop.wasm");

#[cfg(test)]
mod test {
    extern crate std;
    use std::println;
    use soroban_sdk::{contract, contractimpl, symbol_short, Env, Address, Vec, Map,
                      testutils::{Address as _, Ledger as _}, token};
    use super::{WASM, Client, Positions};

    // ---- Mocks ----
    #[contract] pub struct MockFactory;
    #[contractimpl] impl MockFactory {
        pub fn is_pool(_e: Env, _addr: Address) -> bool { true }
    }

    #[contract] pub struct MockPool;
    #[contractimpl] impl MockPool {
        pub fn get_positions(e: Env, _addr: Address) -> Positions {
            Positions { collateral: Map::new(&e), liabilities: Map::new(&e), supply: Map::new(&e) }
        }
    }

    #[contract] pub struct MockEmitter;
    #[contractimpl] impl MockEmitter {
        pub fn set_last(e: Env, t: u64) { e.storage().instance().set(&symbol_short!("t"), &t); }
        pub fn get_last_distro(e: Env, _addr: Address) -> u64 {
            e.storage().instance().get(&symbol_short!("t")).unwrap_or(0)
        }
    }

    // Comet-style LP token = the backstop_token. Standard token + get_total_supply/get_balance +
    // dep_tokn_amt_in_get_lp_tokns_out (auto-compound target used by claim).
    #[contract] pub struct MockComet;
    #[contractimpl] impl MockComet {
        pub fn cinit(e: Env, blnd: Address, usdc: Address, blnd_res: i128, usdc_res: i128, ts: i128) {
            e.storage().instance().set(&symbol_short!("ts"), &ts);
            let mut r: Map<Address, i128> = Map::new(&e);
            r.set(blnd, blnd_res);
            r.set(usdc, usdc_res);
            e.storage().instance().set(&symbol_short!("res"), &r);
        }
        pub fn mint(e: Env, to: Address, amount: i128) {
            let k = (symbol_short!("bal"), to);
            let cur: i128 = e.storage().persistent().get(&k).unwrap_or(0);
            e.storage().persistent().set(&k, &(cur + amount));
        }
        pub fn balance(e: Env, id: Address) -> i128 {
            e.storage().persistent().get(&(symbol_short!("bal"), id)).unwrap_or(0)
        }
        pub fn transfer(e: Env, from: Address, to: Address, amount: i128) {
            from.require_auth();
            let kf = (symbol_short!("bal"), from);
            let cf: i128 = e.storage().persistent().get(&kf).unwrap_or(0);
            e.storage().persistent().set(&kf, &(cf - amount));
            let kt = (symbol_short!("bal"), to);
            let ct: i128 = e.storage().persistent().get(&kt).unwrap_or(0);
            e.storage().persistent().set(&kt, &(ct + amount));
        }
        pub fn transfer_from(e: Env, spender: Address, from: Address, to: Address, amount: i128) {
            spender.require_auth();
            let kf = (symbol_short!("bal"), from);
            let cf: i128 = e.storage().persistent().get(&kf).unwrap_or(0);
            e.storage().persistent().set(&kf, &(cf - amount));
            let kt = (symbol_short!("bal"), to);
            let ct: i128 = e.storage().persistent().get(&kt).unwrap_or(0);
            e.storage().persistent().set(&kt, &(ct + amount));
        }
        pub fn get_total_supply(e: Env) -> i128 {
            e.storage().instance().get(&symbol_short!("ts")).unwrap_or(0)
        }
        pub fn get_balance(e: Env, token: Address) -> i128 {
            let r: Map<Address, i128> = e.storage().instance().get(&symbol_short!("res")).unwrap_or(Map::new(&e));
            r.get(token).unwrap_or(0)
        }
        // Auto-compound: claimed BLND in -> LP out. 1:1 for measurement clarity (pure accounting).
        pub fn dep_tokn_amt_in_get_lp_tokns_out(_e: Env, _token_in: Address, amount_in: i128, min_out: i128, _to: Address) -> i128 {
            assert!(amount_in >= min_out, "slippage");
            amount_in
        }
    }

    // ---------------- shared vector 1/4 setup (SAC backstop token) ----------------
    fn setup(env: &Env) -> (Client<'static>, Address, token::StellarAssetClient<'static>, token::TokenClient<'static>) {
        env.mock_all_auths();
        env.cost_estimate().budget().reset_unlimited();
        env.ledger().set_timestamp(1_000);
        let admin = Address::generate(env);
        let lp = env.register_stellar_asset_contract_v2(admin.clone());
        let blnd = env.register_stellar_asset_contract_v2(admin.clone());
        let usdc = env.register_stellar_asset_contract_v2(admin.clone());
        let emitter = Address::generate(env);
        let factory = env.register(MockFactory, ());
        let drop_list = Vec::<(Address, i128)>::new(env);
        let bs_addr = env.register(WASM, (lp.address(), emitter, blnd.address(), usdc.address(), factory, drop_list));
        let bs = Client::new(env, &bs_addr);
        let lp_sac = token::StellarAssetClient::new(env, &lp.address());
        let lp_tok = token::TokenClient::new(env, &lp.address());
        (bs, lp.address(), lp_sac, lp_tok)
    }

    #[test]
    fn vector1_deposit_withdraw_roundtrip() {
        let env = Env::default();
        let (bs, _lp, lp_sac, lp_tok) = setup(&env);
        let pool = env.register(MockPool, ());
        let user = Address::generate(&env);
        lp_sac.mint(&user, &10_000_000i128);
        let deposit_amt = 1_000_000i128;
        let shares = bs.deposit(&user, &pool, &deposit_amt);
        println!("V1: deposited {} -> shares {}", deposit_amt, shares);
        let q = bs.queue_withdrawal(&user, &pool, &shares);
        println!("V1: queued {} shares, exp {}", shares, q.exp);
        let imm = bs.try_withdraw(&user, &pool, &shares);
        println!("V1: immediate withdraw = {:?}", imm);
        assert!(imm.is_err(), "immediate withdraw should fail (NotExpired)");
        env.ledger().set_timestamp(1_000 + 1_468_800 + 1);
        let out = bs.withdraw(&user, &pool, &shares);
        println!("V1: after 17d withdrew -> {} (user LP bal {})", out, lp_tok.balance(&user));
        assert!(out <= deposit_amt, "round-trip profit!");
        assert_eq!(out, deposit_amt);
        println!("V1 VERDICT: SAFE (out == deposit, no rounding profit).");
    }

    // rounding: deposit into a share-price-inflated pool, confirm withdraw <= deposit
    #[test]
    fn vector1b_rounding_no_profit() {
        let env = Env::default();
        let (bs, _lp, lp_sac, lp_tok) = setup(&env);
        let pool = env.register(MockPool, ());
        let seed = Address::generate(&env);
        let attacker = Address::generate(&env);
        lp_sac.mint(&seed, &1_000_000_000i128);
        lp_sac.mint(&attacker, &1_000_000_000i128);
        bs.deposit(&seed, &pool, &1_000_000i128);         // shares 1_000_000
        lp_tok.approve(&seed, &bs.address, &333_333i128, &1_000_000u32);
        bs.donate(&seed, &pool, &333_333i128);            // tokens=1_333_333, shares=1_000_000 (price 1.333)
        // attacker deposits an awkward amount
        let amt = 777_777i128;
        let sh = bs.deposit(&attacker, &pool, &amt);
        bs.queue_withdrawal(&attacker, &pool, &sh);
        env.ledger().set_timestamp(1_000 + 1_468_800 + 1);
        let out = bs.withdraw(&attacker, &pool, &sh);
        println!("V1b: deposit {} -> shares {} -> withdraw {}", amt, sh, out);
        assert!(out <= amt, "rounding profit! out {} > deposit {}", out, amt);
        println!("V1b VERDICT: SAFE (share rounding floors against the depositor).");
    }

    #[test]
    fn vector4a_donate_is_a_gift() {
        let env = Env::default();
        let (bs, _lp, lp_sac, lp_tok) = setup(&env);
        let pool = env.register(MockPool, ());
        let victim = Address::generate(&env);
        let attacker = Address::generate(&env);
        lp_sac.mint(&victim, &10_000_000i128);
        lp_sac.mint(&attacker, &10_000_000i128);
        let vshares = bs.deposit(&victim, &pool, &1_000_000i128);
        let att_before = lp_tok.balance(&attacker);
        lp_tok.approve(&attacker, &bs.address, &1_000_000i128, &1_000_000u32);
        bs.donate(&attacker, &pool, &1_000_000i128);
        let att_ub = bs.user_balance(&pool, &attacker);
        println!("V4a: attacker LP {} -> {}, attacker shares {}", att_before, lp_tok.balance(&attacker), att_ub.shares);
        assert_eq!(att_ub.shares, 0);
        assert_eq!(lp_tok.balance(&attacker), att_before - 1_000_000);
        bs.queue_withdrawal(&victim, &pool, &vshares);
        env.ledger().set_timestamp(1_000 + 1_468_800 + 1);
        let vout = bs.withdraw(&victim, &pool, &vshares);
        println!("V4a: victim deposited 1_000_000 withdrew {}", vout);
        assert!(vout > 1_000_000);
        println!("V4a VERDICT: SAFE (donor gets 0 shares & -1_000_000 LP; donate() bytecode = require_auth(from)+require_auth(pool)).");
    }

    #[test]
    fn vector4b_draw_isolated() {
        let env = Env::default();
        let (bs, _lp, lp_sac, lp_tok) = setup(&env);
        let pool_a = env.register(MockPool, ());
        let pool_b = env.register(MockPool, ());
        let victim = Address::generate(&env);
        let attacker = Address::generate(&env);
        lp_sac.mint(&victim, &10_000_000i128);
        bs.deposit(&victim, &pool_a, &1_000_000i128);
        println!("V4b: backstop holds {} LP", lp_tok.balance(&bs.address));
        let steal = bs.try_draw(&pool_b, &1_000_000i128, &attacker);
        println!("V4b: draw via empty fake pool B = {:?}", steal);
        assert!(steal.is_err());
        assert_eq!(lp_tok.balance(&attacker), 0);
        bs.draw(&pool_a, &400_000i128, &attacker);
        println!("V4b: pool A legit draw 400_000 -> attacker LP {}", lp_tok.balance(&attacker));
        let over = bs.try_draw(&pool_a, &10_000_000i128, &attacker);
        println!("V4b: pool A over-draw = {:?}", over);
        assert!(over.is_err());
        println!("V4b VERDICT: SAFE (draw require_auth(pool) + subtracts that pool's own tokens; fake pool can't reach another pool).");
    }

    // ================= EMISSIONS SETUP (Comet backstop token) =================
    struct Emis {
        bs: Client<'static>,
        pool: Address,
        blnd: token::TokenClient<'static>,
        comet: Address,
    }

    fn mint_lp(env: &Env, comet: &Address, to: &Address, amt: i128) {
        MockCometClient::new(env, comet).mint(to, &amt);
    }

    // Drive distribute+gulp so a BackstopEmissionData window opens for `pool`.
    // distribute #1 records the baseline (returns 0 when LastDist==0); #2 allocates.
    // gulp_emissions requires now >= 86400 and RzEmissions older than ~86400s, so it runs at tg.
    const T0: u64 = 5_000;
    const T1: u64 = 10_000;
    const TG: u64 = 100_000;          // gulp time (>= 86400)
    const WEND: u64 = TG + 604_800;   // emission window end
    const WMID: u64 = TG + 302_400;
    fn open_emissions(env: &Env, e: &Emis, emitter: &Address) {
        let em = MockEmitterClient::new(env, emitter);
        env.ledger().set_timestamp(T0);
        em.set_last(&T0);
        let d0 = e.bs.distribute();
        env.ledger().set_timestamp(T1);
        em.set_last(&T1);
        let d1 = e.bs.distribute();
        env.ledger().set_timestamp(TG);
        let g = e.bs.gulp_emissions(&e.pool);
        println!("  distribute#1={} distribute#2(allocated)={} gulp(backstop share)={}", d0, d1, g);
    }

    fn pools_vec(env: &Env, p: &Address) -> Vec<Address> {
        let mut v = Vec::new(env);
        v.push_back(p.clone());
        v
    }

    // Full emissions test with emitter handle available.
    fn setup_emis2(env: &Env) -> (Emis, Address) {
        env.mock_all_auths_allowing_non_root_auth();
        env.cost_estimate().budget().reset_unlimited();
        env.ledger().set_timestamp(5_000);
        let admin = Address::generate(env);
        let blnd = env.register_stellar_asset_contract_v2(admin.clone());
        let usdc = env.register_stellar_asset_contract_v2(admin.clone());
        let comet = env.register(MockComet, ());
        MockCometClient::new(env, &comet).cinit(&blnd.address(), &usdc.address(),
            &(80_000_000_0000000i128), &(20_000_000_0000000i128), &(100_000_000_0000000i128));
        let emitter = env.register(MockEmitter, ());
        let factory = env.register(MockFactory, ());
        let drop_list = Vec::<(Address, i128)>::new(env);
        let bs_addr = env.register(WASM, (comet.clone(), emitter.clone(), blnd.address(), usdc.address(), factory, drop_list));
        let bs = Client::new(env, &bs_addr);
        token::StellarAssetClient::new(env, &blnd.address()).mint(&bs_addr, &(1_000_000_000_0000000i128));
        let pool = env.register(MockPool, ());
        (Emis { bs, pool, blnd: token::TokenClient::new(env, &blnd.address()), comet }, emitter)
    }

    #[test]
    fn vector2_late_depositor_no_steal() {
        let env = Env::default();
        let (e, emitter) = setup_emis2(&env);
        let honest = Address::generate(&env);
        let attacker = Address::generate(&env);
        mint_lp(&env, &e.comet, &honest, 50_000_000_0000000i128);
        mint_lp(&env, &e.comet, &attacker, 50_000_000_0000000i128);

        // T0=5000: honest deposits, pool enters reward zone, emissions window opens
        e.bs.deposit(&honest, &e.pool, &(10_000_000_0000000i128));
        e.bs.add_reward(&e.pool, &None);
        open_emissions(&env, &e, &emitter);

        // Advance to the very end of the 7-day window
        env.ledger().set_timestamp(WEND);

        // ATTACKER deposits a HUGE stake at the last instant, then claims immediately.
        e.bs.deposit(&attacker, &e.pool, &(40_000_000_0000000i128));
        let attacker_claim = e.bs.claim(&attacker, &pools_vec(&env, &e.pool), &0i128);
        let honest_claim = e.bs.claim(&honest, &pools_vec(&env, &e.pool), &0i128);
        println!("V2: attacker (deposited huge at window end, held 0s) claimed BLND = {}", attacker_claim);
        println!("V2: honest   (held full 7d window)               claimed BLND = {}", honest_claim);
        assert_eq!(attacker_claim, 0, "EXPLOIT: late depositor accrued past emissions!");
        assert!(honest_claim > 0, "honest long-term depositor should earn");
        println!("V2 VERDICT: SAFE. Deposit snapshots the emission index (f88) so a just-deposited position accrues 0 for the elapsed window. Attacker profit = 0.");
    }

    // Mid-window deposit: attacker should get only time-weighted share of the remaining window
    #[test]
    fn vector2b_midwindow_timeweighted() {
        let env = Env::default();
        let (e, emitter) = setup_emis2(&env);
        let honest = Address::generate(&env);
        let attacker = Address::generate(&env);
        mint_lp(&env, &e.comet, &honest, 50_000_000_0000000i128);
        mint_lp(&env, &e.comet, &attacker, 50_000_000_0000000i128);

        e.bs.deposit(&honest, &e.pool, &(10_000_000_0000000i128));
        e.bs.add_reward(&e.pool, &None);
        open_emissions(&env, &e, &emitter);

        // halfway through
        env.ledger().set_timestamp(WMID);
        e.bs.deposit(&attacker, &e.pool, &(10_000_000_0000000i128)); // equal stake, but joins at half
        // end of window
        env.ledger().set_timestamp(WEND);
        let attacker_claim = e.bs.claim(&attacker, &pools_vec(&env, &e.pool), &0i128);
        let honest_claim = e.bs.claim(&honest, &pools_vec(&env, &e.pool), &0i128);
        println!("V2b: attacker (equal stake, joined at 50%) claimed = {}", attacker_claim);
        println!("V2b: honest   (equal stake, whole window)  claimed = {}", honest_claim);
        assert!(attacker_claim < honest_claim, "late equal-stake depositor must earn strictly less");
        println!("V2b VERDICT: SAFE (emissions are time-weighted; late equal stake earns less).");
    }

    // ===== VECTOR 3: double claim yields ~0 on the second call =====
    #[test]
    fn vector3_double_claim() {
        let env = Env::default();
        let (e, emitter) = setup_emis2(&env);
        let user = Address::generate(&env);
        mint_lp(&env, &e.comet, &user, 50_000_000_0000000i128);
        e.bs.deposit(&user, &e.pool, &(10_000_000_0000000i128));
        e.bs.add_reward(&e.pool, &None);
        open_emissions(&env, &e, &emitter);
        env.ledger().set_timestamp(WEND);
        let first = e.bs.claim(&user, &pools_vec(&env, &e.pool), &0i128);
        let second = e.bs.claim(&user, &pools_vec(&env, &e.pool), &0i128);
        println!("V3: first claim = {}, immediate second claim = {}", first, second);
        assert!(first > 0);
        assert_eq!(second, 0, "double-spend of the same accrual!");
        println!("V3 VERDICT: SAFE (second claim yields 0; accrual reset on claim).");
    }
}
