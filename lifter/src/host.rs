//! The host ABI: which arguments are Vals, which raw integers; the table is generated from env.json.


#[derive(Clone, Copy, PartialEq, Debug)]
pub enum VT {
    /// A tagged 64-bit Soroban value. Lowers to `%Val`.
    Val,
    /// A raw machine integer crossing the host boundary. Lowers to `i64`.
    Raw64,
    /// `StorageType`: a direct-marshalled enum, 0/1/2. Lowers to `i64`.
    Storage,
}

pub struct HostFn {
    pub module: &'static str,
    pub code: &'static str,
    pub name: &'static str,
    pub args: &'static [VT],
    pub arg_tys: &'static [&'static str],
    pub ret: VT,
    pub ret_ty: &'static str,
}

include!(concat!(env!("OUT_DIR"), "/hostfns.rs"));
