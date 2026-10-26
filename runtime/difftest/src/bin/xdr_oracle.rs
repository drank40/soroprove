//! For random values of every XDR type: encode, then also mutate the bytes, and print
//! `<RustTypeName> <hex> <ok hex | err Kind>` where the result is stellar-xdr 30.0.0's
//! read_xdr_to_end + write_xdr with the host's limits (depth 500, len 32 MiB).
use rand::{Rng, RngCore, SeedableRng};
use stellar_xdr::{Limited, Limits, ReadXdr, Type, TypeVariant, WriteXdr};

fn lim() -> Limits { Limits { depth: 500, len: 32 * 1024 * 1024 } }
fn hex(b: &[u8]) -> String { b.iter().map(|x| format!("{x:02x}")).collect() }
fn kind(e: &stellar_xdr::Error) -> &'static str {
    use stellar_xdr::Error::*;
    match e { Invalid => "invalid", LengthExceedsMax => "lengthExceedsMax", NonZeroPadding => "nonZeroPadding",
        DepthLimitExceeded => "depthLimitExceeded", LengthLimitExceeded => "lengthLimitExceeded", Io(_) => "io", _ => "other" }
}
fn rt(v: TypeVariant, b: &[u8]) -> String {
    let mut r = Limited::new(std::io::Cursor::new(b), lim());
    match Type::read_xdr_to_end(v, &mut r) {
        Ok(t) => { let mut out = Vec::new(); let mut w = Limited::new(&mut out, lim());
            match t.write_xdr(&mut w) { Ok(()) => format!("ok {}", hex(&out)), Err(e) => format!("err {}", kind(&e)) } }
        Err(e) => format!("err {}", kind(&e)),
    }
}
fn main() {
    let per: usize = std::env::args().nth(1).map(|s| s.parse().unwrap()).unwrap_or(30);
    let mut rng = rand_chacha::ChaCha8Rng::seed_from_u64(7);
    for v in TypeVariant::VARIANTS {
        for i in 0..per {
            let mut seed = vec![0u8; 64 + (i * 37) % 4000];
            rng.fill_bytes(&mut seed);
            let mut u = arbitrary::Unstructured::new(&seed);
            let Ok(t) = Type::arbitrary(v, &mut u) else { continue };
            let mut b = Vec::new();
            { let mut w = Limited::new(&mut b, lim()); if t.write_xdr(&mut w).is_err() { continue; } }
            println!("{} {} {}", v.name(), hex(&b), rt(v, &b));
            // mutations: flip a byte, truncate, extend
            if !b.is_empty() {
                let mut m = b.clone(); let k = rng.gen_range(0..m.len()); m[k] ^= 1 << rng.gen_range(0..8);
                println!("{} {} {}", v.name(), hex(&m), rt(v, &m));
                let t2 = &b[..rng.gen_range(0..b.len())]; println!("{} {} {}", v.name(), hex(t2), rt(v, t2));
            }
            let mut e = b.clone(); e.push(0); println!("{} {} {}", v.name(), hex(&e), rt(v, &e));
        }
    }
}
