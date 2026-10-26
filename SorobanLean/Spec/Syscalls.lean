/-
Soroprove's runtime model: only the syscalls that matter for loss of funds, simplified.

Every entry cites its env.json signature (rs-soroban-env v30.0.0, `module.export`) and the
host implementation it abstracts (soroban-env-host/src/host.rs unless noted).

The vocabulary of the model: the transaction environment, the syscalls and their
decoded arguments. The state machine over them is SorobanLean/Spec/Machine.lean.

Simplifications (each sound for "can funds be lost / can the contract be bricked"):
* No metering, no Wasm memory: syscalls take and return abstract values (`AV`).
* Signatures, auth entries and existing Wasm are facts of the transaction (`Env`), not
  computed: `require_auth`, the `verify_sig_*` family and upgrades succeed exactly when
  the corresponding `Env` predicate holds.
* Cross-contract calls: calls to a SEP-41 token (`Env.isToken`) apply the abstract SEP-41
  step (SorobanLean/Spec/Sep41.lean); any other call returns ⊤ and may change token
  state only within `Unknown` below. Re-entry is prohibited by the host, so no call
  changes this contract's own storage.
* Any failure ends the invocation and rolls everything back (`Out.fail`); `try_call`
  instead turns recoverable failures into an error value.
-/
import SorobanLean.Spec.Host
import SorobanLean.Spec.Sep41

namespace Soroban.Prove
open SHost (CVal Addr SType)
open Soroban.Spec

/-- Abstract values: a known value, or ⊤ (any value). -/
inductive AV where
  | known (v : CVal)
  | top
  deriving Inhabited

/-- A host error (`ScError`): type and code; contract errors carry their own code. -/
inductive Err where
  | contract (code : Nat)
  | host (t : ScErrorType) (c : ScErrorCode)

inductive SigScheme
  | ed25519 | secp256r1 | mlDsa44 | mlDsa65 | mlDsa87

/-- What the transaction provides; the contract cannot change these. -/
structure Env where
  /-- `get_current_contract_address`. -/
  self : Addr
  /-- `require_auth(a)` (with the frame's arguments) or `require_auth_for_args(a, args)`
      succeeds through signed auth entries / `__check_auth` (auth.rs, enforcing mode). The
      direct-invoker rule (auth.rs:1164-1225) is applied separately, see `Env.authorizes`. -/
  signed : Addr → List CVal → Prop
  /-- Signature verification succeeds (`verify_sig_*`, host/crypto). -/
  sigOk : SigScheme → (pk msg sig ctx : List UInt8) → Prop
  /-- `recover_key_ecdsa_secp256k1`: the recovered 65-byte key, or failure. -/
  recover : (digest sig : List UInt8) → Nat → Option (List UInt8)
  /-- `verify_wasm_exists` / `verify_executable_ref_entry_exists` (data_helper.rs:168-180). -/
  wasmExists : List UInt8 → Prop
  /-- Addresses traced as SEP-41 tokens. -/
  isToken : Addr → Prop
  /-- Ledger sequence (allowance expiry). -/
  seq : Nat

/-- An executable the contract can upgrade to. -/
inductive Exe where
  | wasm (hash : List UInt8)
  | externalRef (owner : Addr) (tag : List UInt8)

/-- The syscalls, with arguments already decoded from `Val`s. -/
inductive Sys where
  /-- `d._` `call(contract: AddressObject, func: Symbol, args: VecObject) -> Val` (host.rs:2479-2512). -/
  | call (contract : Addr) (func : List UInt8) (args : List AV)
  /-- `d.0` `try_call(contract, func, args) -> Val` (host.rs:2515-2568). -/
  | tryCall (contract : Addr) (func : List UInt8) (args : List AV)
  /-- `a.0` `require_auth(address: AddressObject) -> Void` (host.rs:3566-3593): the
      current frame's arguments are the authorized arguments. -/
  | requireAuth (a : Addr) (frameArgs : List CVal)
  /-- `a._` `require_auth_for_args(address: AddressObject, args: VecObject) -> Void` (host.rs:3554-3564). -/
  | requireAuthForArgs (a : Addr) (args : List CVal)
  /-- `c.0` `verify_sig_ed25519(k, x, s: BytesObject) -> Void`; `c.3`
      `verify_sig_ecdsa_secp256r1(public_key, msg_digest, signature) -> Void`;
      `c.A/B/C` `verify_sig_ml_dsa_{44,65,87}(public_key, msg, signature, context) -> Void`
      (host.rs:3035-3075, 3495-3550). -/
  | verifySig (sch : SigScheme) (pk msg sig ctx : List UInt8)
  /-- `c.2` `recover_key_ecdsa_secp256k1(msg_digest, signature: BytesObject, recovery_id: U32Val) -> BytesObject`. -/
  | recoverSecp256k1 (digest sig : List UInt8) (rid : Nat)
  /-- `a.3` `authorize_as_curr_contract(auth_entires: VecObject) -> Void` (host.rs:3617-3626). -/
  | authorizeAsCurrContract (entries : CVal)
  /-- `l.6` `update_current_contract_wasm(hash: BytesObject) -> Void` (host.rs:2452-2461). -/
  | updateWasm (hash : List UInt8)
  /-- `l.j` `update_current_contract_executable_ref(executable_owner: AddressObject, tag: ExecutableTagObject) -> Void` (host.rs:2463-2474). -/
  | updateExecutableRef (owner : Addr) (tag : List UInt8)
  /-- `l._` `put_contract_data(k: Val, v: Val, t: StorageType) -> Void`. -/
  | put (k v : CVal) (t : SType)
  /-- `l.1` `get_contract_data(k: Val, t: StorageType) -> Val`. -/
  | get (k : CVal) (t : SType)
  /-- `l.0` `has_contract_data(k: Val, t: StorageType) -> Bool`. -/
  | has (k : CVal) (t : SType)
  /-- `l.2` `del_contract_data(k: Val, t: StorageType) -> Void`. -/
  | del (k : CVal) (t : SType)
  /-- `x.7` `get_current_contract_address() -> AddressObject` (host.rs:1306-1314). -/
  | currentAddress
  /-- `x.5` `fail_with_error(error: Error) -> Void` (host.rs:1274-1293). -/
  | failWithError (e : Err)
  /-- `x.0` `obj_cmp(a: Val, b: Val) -> i64` (host.rs:1192-1248). -/
  | objCmp (a b : AV)

def voidV : AV := .known SHost.VOIDc
def boolV (b : Bool) : AV := .known (.small (Val.fromBool b).payload)

/-! ## Auth -/

/-- `require_auth*(a)` passes: `a` is the direct invoker contract (auth.rs:1164-1225), or the
    transaction authorizes it. For calls made by this contract, the direct invoker is `self`. -/
def Env.authorizes (env : Env) (invoker : Option Addr) (a : Addr) (args : List CVal) : Prop :=
  invoker = some a ∨ env.signed a args

/-! ## SEP-41 calls -/

def sym (s : String) : List UInt8 := s.toUTF8.toList

/-- Decode a SEP-41 mutating call from `(func, args)`; `none` if it is not one. A `to`
    given as a muxed address transfers to its base address (contract.rs `transfer`). -/
def sep41Call (func : List UInt8) : List AV → Option (Sep41.Call Addr)
  | [.known (.addr f), .known t, .known (.i128 a)] =>
    let to? : Option Addr := match t with | .addr x => some x | .muxed x _ => some x | _ => none
    if func = sym "transfer" then to?.map (Sep41.Call.transfer f · a)
    else if func = sym "burn_from" then match t with
      | .addr x => some (.burnFrom f x a)
      | _ => none
    else none
  | [.known (.addr sp), .known (.addr f), .known (.addr t), .known (.i128 a)] =>
    if func = sym "transfer_from" then some (.transferFrom sp f t a) else none
  | [.known (.addr f), .known (.addr sp), .known (.i128 a), .known (.small lu)] =>
    if func = sym "approve" then some (.approve f sp a (Val.getMajor ⟨lu⟩).toNat) else none
  | [.known (.addr f), .known (.i128 a)] =>
    if func = sym "burn" then some (.burn f a) else none
  | _ => none

end Soroban.Prove
