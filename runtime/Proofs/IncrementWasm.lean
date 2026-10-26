/-
The real `increment` contract at the Wasm level, for every stored counter.

`incCtx_eq` ties the instance context the host builds for the deployed bytes
(`Proofs.incrementWasm`) to the literal compiled code below, checked by the kernel.
The theorems then run that code against an arbitrary host whose four imports
(`has`, `get`, `put`, `extend_ttl` on the `COUNTER` key in instance storage) answer
as stated, with fuel unmetered.
-/
import SorobanLean.Wasm.Decode
import SorobanLean.Wasm.Instantiate
import SorobanLean.Tactic.KernelRfl
import Proofs.IncrementBytes
import SorobanLean.Proof.WasmSteps

namespace Proofs
open Wasm

def incModule : Module := (Decode.decodeModule incrementWasm).toOption.get!

open CInstr Instr in
/-- The translation of the exported `increment` (function 4). -/
def incFunc : CFunc :=
  { typeIdx := 2, params := [], results := [.i64], locals := [.i64], entryFuel := 223,
    maxStackHeight := 4,
    body := [block 0 [block 0 [
      simple (i64Const 253576579652878), simple (i64Const 2), call 0,
      simple (i64Const 1), simple (relop .w64 .eq),
      if_ 0 83 none [
        simple (i64Const 253576579652878), simple (i64Const 2), call 1,
        simple (localTee 0), simple (i64Const 255), simple (binop .w64 .and),
        simple (i64Const 4), simple (relop .w64 .ne), brIf 1,
        simple (localGet 0), simple (i64Const 32), simple (binop .w64 .shrU),
        simple (localTee 0), simple (i64Const 4294967295), simple (relop .w64 .eq), brIf 2] [],
      simple (i64Const 253576579652878), simple (localGet 0), simple (i64Const 32),
      simple (binop .w64 .shl), simple (i64Const 4294967300), simple (binop .w64 .add),
      simple (localTee 0), simple (i64Const 2), call 2, simple drop,
      simple (i64Const 214748364804), simple (i64Const 429496729604), call 3, simple drop,
      simple (localGet 0), return_], unreachable], unreachable] }

def ft2 : FuncType := { params := [.i64, .i64], results := [.i64] }
def ft3 : FuncType := { params := [.i64, .i64, .i64], results := [.i64] }
def ft0 : FuncType := { params := [], results := [.i64] }

def incCtx {H E : Type} (host : HostIface H E) : Ctx H E :=
  { host, funcs := #[incFunc], nImports := 4, funcTypes := #[ft2, ft2, ft3, ft2, ft0],
    types := #[ft2, ft3, ft0] }

set_option maxRecDepth 100000 in
kernel_rfl incCtx_eq : ∀ {H E : Type} (host : HostIface H E),
  Instantiate.mkCtx host incModule = incCtx host

kernel_rfl incExport : Instantiate.exportedFunc? incModule "increment" = some 4

open Wasm.Exec

/-- The `U32Val` payload of `c` (tag 4 in the low byte, the value in the high half). -/
def u32Val (c : UInt32) : UInt64 := c.toUInt64 <<< 32 ||| 4

theorem u32Val_toNat (c : UInt32) : (u32Val c).toNat = c.toNat * 2^32 + 4 := by
  have hc := c.toNat_lt
  have h1 : (c.toUInt64 <<< 32).toNat = c.toNat * 2^32 := by
    rw [UInt64.toNat_shiftLeft]; simp only [UInt32.toNat_toUInt64]
    rw [Nat.shiftLeft_eq]; show c.toNat * 2^32 % 2^64 = _; omega
  have : (c.toNat * 2^32) ||| 4 = c.toNat * 2^32 + 4 := by
    rw [← Nat.shiftLeft_eq, ← Nat.shiftLeft_add_eq_or_of_lt (by decide)]
  simp only [u32Val, UInt64.toNat_or, h1]; exact this

theorem u32Val_and (c : UInt32) : u32Val c &&& 255 = 4 := by
  apply UInt64.toNat_inj.mp
  rw [UInt64.toNat_and, u32Val_toNat]
  show _ &&& (2^8 - 1) = 4
  rw [Nat.and_two_pow_sub_one_eq_mod]; omega

theorem u32Val_shr (c : UInt32) : u32Val c >>> 32 = c.toUInt64 := by
  apply UInt64.toNat_inj.mp
  rw [UInt64.toNat_shiftRight, u32Val_toNat]
  simp only [UInt32.toNat_toUInt64]
  show _ >>> 32 = _
  rw [Nat.shiftRight_eq_div_pow]; omega

theorem u32Val_succ (c : UInt32) (hc : c ≠ 4294967295) :
    (c.toUInt64 <<< 32) + 4294967300 = u32Val (c + 1) := by
  have hn : c.toNat ≠ 4294967295 := fun h => hc (UInt32.toNat_inj.mp h)
  have hlt := c.toNat_lt
  apply UInt64.toNat_inj.mp
  rw [u32Val_toNat, UInt64.toNat_add, UInt64.toNat_shiftLeft, UInt32.toNat_add]
  simp only [UInt32.toNat_toUInt64, Nat.shiftLeft_eq]
  show (c.toNat * 2^32 % 2^64 + 4294967300) % 2^64 = (c.toNat + 1) % 2^32 * 2^32 + 4
  omega

theorem toU64_ne_max (c : UInt32) (hc : c ≠ 4294967295) : (c.toUInt64 == 4294967295) = false := by
  have hn : c.toNat ≠ 4294967295 := fun h => hc (UInt32.toNat_inj.mp h)
  simp only [beq_eq_false_iff_ne, ne_eq]
  intro h; apply hn; have := congrArg UInt64.toNat h; simpa using this


@[simp] theorem Res.bindM {E S α β} (x : Res E S α) (f : α → Res E S β) : (x >>= f) = x.bind f := rfl
@[simp] theorem Res.pureM {E S α} (a : α) : (pure a : Res E S α) = .ok a := rfl
theorem Store.eta' (s : Store) :
    Store.mk s.mem s.memMax s.globals s.table s.datas s.elems s.fuel = s := rfl
theorem arr1_set (a b : Value) : #[a].setIfInBounds 0 b = #[b] := rfl
theorem arr1_get (b : Value) : #[b][0]? = some b := rfl
theorem and63 : (32 : UInt64) &&& 63 = 32 := by decide
theorem toU64_ne_max' (c : UInt32) (hc : c ≠ 4294967295) : c.toUInt64 ≠ 4294967295 := by
  have := toU64_ne_max c hc; simpa using this

macro "wsimple" : tactic => `(tactic| (refine (execList_next _ _ (execInstr_simple _ _ (by rfl))).trans ?_))
macro "wcall " hc:term : tactic => `(tactic|
  (refine (execList_next _ _ (execInstr_callHost _ _ (by simp [incCtx]) rfl (by decide) (by simp [sp, MAX_VALUE_STACK]) $hc)).trans ?_))
macro "wbrnot " t:tacticSeq : tactic => `(tactic|
  (refine (execList_next _ _ (execInstr_brIf_not _ _ rfl (by $t))).trans ?_))

/-- Symbolic execution: definitional unfolding (no proof term), and rewriting only where
    execution depends on a hypothesis (host calls, fuel mode, value facts). -/
macro "wasm_run" "[" ls:Lean.Parser.Tactic.simpLemma,* "]" : tactic => `(tactic|
  (simp only [Exec.invoke, incCtx, incFunc, ft0, ft2, ft3]
   repeat (first
     | dsimp [execList, execInstr, callFunc, simple, push, popI32, popI64, pop1, chargeFuel, Fuel.consume, trapAt, sp, restore, Res.bind, lift, Res.ofExcept, binop64, Num.i64rel, relIdx, Num.b32, Num.i64shl, Num.i64shrU, Value.zero, MAX_VALUE_STACK, MAX_RECURSION_DEPTH, Store.eta', Res.bindM, Res.pureM, List.reverse, List.reverseAux, List.take, List.drop, List.nil_append, List.cons_append, arr1_set, arr1_get]
     | simp (config := { decide := true }) only [and63, $ls,*])))

theorem incr_wasm {H E : Type} (host : HostIface H E) (c : UInt32) (hc : c ≠ 4294967295)
    (st0 st1 st2 st3 st4 : Store) (h0 h1 h2 h3 h4 : H) (r2 r3 : UInt64) (k : Nat)
    (m0 : st0.fuel.metered = false) (m1 : st1.fuel.metered = false)
    (H0 : ∀ g, host.call g 0 [.i64 253576579652878, .i64 2] st0 h0 = .ok ([.i64 1], st1, h1))
    (H1 : ∀ g, host.call g 1 [.i64 253576579652878, .i64 2] st1 h1 = .ok ([.i64 (u32Val c)], st2, h2))
    (H2 : ∀ g, host.call g 2 [.i64 253576579652878, .i64 (u32Val (c+1)), .i64 2] st2 h2
            = .ok ([.i64 r2], st3, h3))
    (H3 : ∀ g, host.call g 3 [.i64 214748364804, .i64 429496729604] st3 h3 = .ok ([.i64 r3], st4, h4)) :
    Exec.invoke (incCtx host) (k + 100) 4 [] st0 h0 = .ok ([.i64 (u32Val (c+1))], st4, h4) := by
  wasm_run [m0, m1, H0, H1, H2, H3, u32Val_and, u32Val_shr, u32Val_succ c hc, toU64_ne_max' c hc, toU64_ne_max c hc]
  done

theorem u32Val_max : u32Val 4294967295 = 18446744069414584324 := by decide
theorem u32Val_one : u32Val 1 = 4294967300 := by decide
theorem zero_succ_val : (0 : UInt64) <<< 32 + 4294967300 = 4294967300 := by decide

/-- Overflow: the stored counter is `u32::MAX`, so the contract traps (`unwrap` of the
    checked add), after `has` and `get` and before any write. -/
theorem incr_wasm_overflow {H E : Type} (host : HostIface H E)
    (st0 st1 st2 : Store) (h0 h1 h2 : H) (k : Nat)
    (m0 : st0.fuel.metered = false) (m1 : st1.fuel.metered = false)
    (H0 : ∀ g, host.call g 0 [.i64 253576579652878, .i64 2] st0 h0 = .ok ([.i64 1], st1, h1))
    (H1 : ∀ g, host.call g 1 [.i64 253576579652878, .i64 2] st1 h1 = .ok ([.i64 (u32Val 4294967295)], st2, h2)) :
    Exec.invoke (incCtx host) (k + 100) 4 [] st0 h0 = .trap (.code .UnreachableCodeReached) (st2, h2) := by
  rw [u32Val_max] at H1
  wasm_run [m0, m1, H0, H1]

/-- No counter stored yet: the contract stores and returns `U32(1)`. -/
theorem incr_wasm_absent {H E : Type} (host : HostIface H E)
    (st0 st1 st2 st3 : Store) (h0 h1 h2 h3 : H) (r2 r3 : UInt64) (k : Nat)
    (m0 : st0.fuel.metered = false)
    (H0 : ∀ g, host.call g 0 [.i64 253576579652878, .i64 2] st0 h0 = .ok ([.i64 0], st1, h1))
    (H2 : ∀ g, host.call g 2 [.i64 253576579652878, .i64 (u32Val 1), .i64 2] st1 h1
            = .ok ([.i64 r2], st2, h2))
    (H3 : ∀ g, host.call g 3 [.i64 214748364804, .i64 429496729604] st2 h2 = .ok ([.i64 r3], st3, h3)) :
    Exec.invoke (incCtx host) (k + 100) 4 [] st0 h0 = .ok ([.i64 (u32Val 1)], st3, h3) := by
  rw [u32Val_one] at H2 ⊢
  wasm_run [m0, H0, H2, H3, zero_succ_val]

end Proofs
