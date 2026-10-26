/-
`increment` against the proof host (SorobanLean/Spec/Host.lean): no assumptions on host
behaviour remain. The import table is the one the deployed bytes resolve to (`incImports_eq`).
-/
import Proofs.IncrementWasm
import SorobanLean.Spec.Host
open Wasm Soroban Soroban.SHost
namespace Proofs

theorem u32Val_tag (c : UInt32) : (Val.mk (u32Val c)).getTagU8 = 4 := by
  simp only [Val.getTagU8, Val.TAG_MASK, u32Val_and]; rfl

theorem u32Val_minor (c : UInt32) : (Val.mk (u32Val c)).getMinor = 0 := by
  have hc := c.toNat_lt
  simp only [Val.getMinor, Val.getBody, Val.TAG_BITS, Val.MINOR_MASK]
  have : (u32Val c >>> 8) &&& 0x00ff_ffff = 0 := by
    apply UInt64.toNat_inj.mp
    rw [UInt64.toNat_and, UInt64.toNat_shiftRight, u32Val_toNat]
    show (c.toNat * 2^32 + 4) >>> (8 % 64) &&& (2^24 - 1) = 0
    rw [Nat.and_two_pow_sub_one_eq_mod, Nat.shiftRight_eq_div_pow]
    show (c.toNat * 4294967296 + 4) / 256 % 16777216 = 0
    omega
  rw [this]; rfl

theorem u32Val_getTag (c : UInt32) : (Val.mk (u32Val c)).getTag = .U32Val := by
  simp only [Val.getTag, u32Val_tag]; rfl

theorem u32Val_isGood (c : UInt32) : (Val.mk (u32Val c)).isGood = true := by
  simp only [Val.isGood, u32Val_getTag, Val.hasMinor, u32Val_minor]; rfl

theorem u32Val_isObject (c : UInt32) : (Val.mk (u32Val c)).isObject = false := by
  simp only [Val.isObject, u32Val_tag]; rfl

end Proofs

namespace Proofs
open Wasm Soroban Soroban.SHost

def incImports : Array Env.HostFn :=
  #[.has_contract_data, .get_contract_data, .put_contract_data, .extend_current_contract_instance_and_code_ttl]

kernel_rfl incImports_eq :
  incModule.imports.map (fun i => Env.HostFn.resolve i.module i.name) = incImports.map some

/-- `Symbol("COUNTER")`. -/
def counterKey : CVal := .sym "COUNTER".toUTF8.toList

kernel_rfl decode_key : ∀ s : SH, decode s ⟨253576579652878⟩ = some counterKey
kernel_rfl key_isGood : (Val.mk 253576579652878).isGood = true

theorem decode_u32 (s : SH) (c : UInt32) : decode s ⟨u32Val c⟩ = some (.small (u32Val c)) := by
  simp only [decode, u32Val_isGood, u32Val_isObject, u32Val_getTag]; rfl

theorem has_call (s : SH) (st : Store) (g : Nat) (v : CVal) (hs : lookup s.inst counterKey = some v) :
    (iface incImports).call g 0 [.i64 253576579652878, .i64 2] st s = .ok ([.i64 1], st, s) := by
  simp [iface, incImports, Env.HostFn.args, Env.ValTy.tryMarshal, Env.ValTy.isValType, impl, decode_key, key_isGood, SType.ofRaw, SH.store, hs, ofOpt, ok]
  rfl

theorem get_call (s : SH) (st : Store) (g : Nat) (c : UInt32)
    (hs : lookup s.inst counterKey = some (.small (u32Val c))) :
    (iface incImports).call g 1 [.i64 253576579652878, .i64 2] st s = .ok ([.i64 (u32Val c)], st, s) := by
  simp [iface, incImports, Env.HostFn.args, Env.ValTy.tryMarshal, Env.ValTy.isValType, impl, decode_key, key_isGood, SType.ofRaw, SH.store, hs, ofOpt, ok, materialize]

theorem put_call (s : SH) (st : Store) (g : Nat) (c : UInt32) :
    (iface incImports).call g 2 [.i64 253576579652878, .i64 (u32Val c), .i64 2] st s
      = .ok ([.i64 Val.VOID.payload], st, { s with inst := insert s.inst counterKey (.small (u32Val c)) }) := by
  simp [iface, incImports, Env.HostFn.args, Env.ValTy.tryMarshal, Env.ValTy.isValType, impl, decode_key, key_isGood, decode_u32, SType.ofRaw, SH.store, SH.setStore, ofOpt, ok, u32Val_isGood]

theorem extend_call (s : SH) (st : Store) (g : Nat) :
    (iface incImports).call g 3 [.i64 214748364804, .i64 429496729604] st s = .ok ([.i64 Val.VOID.payload], st, s) := by
  have h1 : (Val.mk 214748364804).isGood = true := by decide
  have h2 : (Val.mk 429496729604).isGood = true := by decide
  have h3 : Env.ValTy.isValType .U32Val ⟨214748364804⟩ = true := by decide
  have h4 : Env.ValTy.isValType .U32Val ⟨429496729604⟩ = true := by decide
  have h5 : ¬ (u32Of 429496729604 < u32Of 214748364804) := by decide
  simp [iface, incImports, Env.HostFn.args, Env.ValTy.tryMarshal, impl, h1, h2, h3, h4, h5, ofOpt, ok]

/-- `increment` on the real bytes against the proof host: for every stored counter
    `c < u32::MAX` it returns `c + 1` and stores `c + 1`; nothing else changes. -/
theorem increment_spec (c : UInt32) (hc : c ≠ 4294967295) (s : SH) (st : Store) (k : Nat)
    (m : st.fuel.metered = false) (hs : lookup s.inst counterKey = some (.small (u32Val c))) :
    Exec.invoke (incCtx (iface incImports)) (k + 100) 4 [] st s
      = .ok ([.i64 (u32Val (c+1))], st, { s with inst := insert s.inst counterKey (.small (u32Val (c+1))) }) :=
  incr_wasm _ c hc st st st st st s s s _ _ _ _ k m m
    (fun g => has_call s st g _ hs) (fun g => get_call s st g c hs) (fun g => put_call s st g (c+1))
    (fun g => extend_call _ st g)

end Proofs
