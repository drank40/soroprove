//! Oracle for SorobanLean/Val.lean: for each payload, print
//! `payload is_good tag_u8 marshal_bits` where marshal_bits has one bit per
//! env.json ValTy (in the Lean `ValTy` constructor order, alphabetical),
//! set iff `<T as WasmiMarshal>::try_marshal_from_value(Value::I64(x))` is Some.
use rand::{Rng, SeedableRng};
use soroban_env_common::*;
use wasmi::Value;

fn m<T: WasmiMarshal>(x: u64) -> bool {
    T::try_marshal_from_value(Value::I64(x as i64)).is_some()
}

fn main() {
    let n: usize = std::env::args().nth(1).map(|s| s.parse().unwrap()).unwrap_or(200000);
    let mut rng = rand_chacha::ChaCha8Rng::seed_from_u64(42);
    let mut xs: Vec<u64> = Vec::new();
    // Structured cases: every tag byte with a few bodies, plus random bodies.
    for tag in 0u64..=255 {
        for body in [0u64, 1, 0x00ff_ffff, 0x0100_0000, 0xffff_ffff_000000, 0x003f_ffff_ffff_ffff, 0x0040_0000_0000_0000, 0x00ff_ffff_ffff_ffff, 9 << 24 | 8, 10 << 24 | 8, 7 << 24] {
            xs.push((body << 8) | tag);
        }
        for _ in 0..50 { xs.push((rng.gen::<u64>() & !0xff) | tag); }
    }
    for _ in 0..n { xs.push(rng.gen()); }
    for x in xs {
        let v = Val::from_payload(x);
        let bits: [bool; 29] = [
            m::<AddressObject>(x), m::<Bool>(x), m::<BytesObject>(x), m::<ContractTtlExtension>(x),
            m::<DurationObject>(x), m::<Error>(x), m::<ExecutableTagObject>(x), m::<I128Object>(x),
            m::<I256Object>(x), m::<I256Val>(x), m::<I64Object>(x), m::<MapObject>(x),
            m::<MuxedAddressObject>(x), m::<StorageType>(x), m::<StringObject>(x), m::<Symbol>(x),
            m::<SymbolObject>(x), m::<TimepointObject>(x), m::<U128Object>(x), m::<U256Object>(x),
            m::<U256Val>(x), m::<U32Val>(x), m::<U64Object>(x), m::<U64Val>(x), m::<Val>(x),
            m::<VecObject>(x), m::<Void>(x), m::<i64>(x), m::<u64>(x),
        ];
        let s: String = bits.iter().map(|b| if *b { '1' } else { '0' }).collect();
        println!("{} {} {} {}", x, v.is_good() as u8, v.get_tag() as u8, s);
    }
}
