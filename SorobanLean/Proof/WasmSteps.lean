/-
Small-step rewriting lemmas for `Wasm.Exec`: symbolic execution of concrete compiled
code proceeds one instruction at a time, each step justified by a small proof, so
proof terms stay linear in the executed path (a single `simp` over a whole function
builds terms the kernel cannot check).
-/
import SorobanLean.Wasm.Exec

namespace Wasm.Exec
variable {H E : Type} (cx : Ctx H E) (fi : FrameInfo)

theorem execList_nil (g : Nat) (c : Cfg H) : execList cx fi (g + 1) [] c = .ok (.next, c) := by
  simp [execList]

theorem execList_next {g : Nat} {i : CInstr} {is : List CInstr} {c c' : Cfg H}
    (h : execInstr cx fi g i c = .ok (.next, c')) :
    execList cx fi (g + 1) (i :: is) c = execList cx fi g is c' := by
  simp [execList, h]

theorem execList_flow {g : Nat} {i : CInstr} {is : List CInstr} {c c' : Cfg H} {fl : Flow}
    (h : execInstr cx fi g i c = .ok (fl, c')) (hfl : fl ≠ .next) :
    execList cx fi (g + 1) (i :: is) c = .ok (fl, c') := by
  cases fl <;> simp_all [execList]

theorem execList_trap {g : Nat} {i : CInstr} {is : List CInstr} {c : Cfg H} {t s}
    (h : execInstr cx fi g i c = .trap t s) :
    execList cx fi (g + 1) (i :: is) c = .trap t s := by
  simp [execList, h]

theorem execInstr_simple {g : Nat} {i : Instr} {c c' : Cfg H} (h : simple cx i c = .ok c') :
    execInstr cx fi (g + 1) (.simple i) c = .ok (.next, c') := by
  simp [execInstr, h, Res.bind]

theorem execInstr_unreachable (g : Nat) (c : Cfg H) :
    execInstr cx fi (g + 1) .unreachable c = trapAt c .UnreachableCodeReached := by
  simp [execInstr]

theorem execInstr_block_next {g k : Nat} {body : List CInstr} {c c' : Cfg H}
    (h : execList cx fi g body c = .ok (.next, c')) :
    execInstr cx fi (g + 1) (.block k body) c = .ok (.next, { c' with stk := restore k c'.stk c.stk }) := by
  simp [execInstr, h]

theorem execInstr_block_br0 {g k : Nat} {body : List CInstr} {c c' : Cfg H}
    (h : execList cx fi g body c = .ok (.br 0, c')) :
    execInstr cx fi (g + 1) (.block k body) c = .ok (.next, { c' with stk := restore k c'.stk c.stk }) := by
  simp [execInstr, h]

theorem execInstr_block_brSucc {g k n : Nat} {body : List CInstr} {c c' : Cfg H}
    (h : execList cx fi g body c = .ok (.br (n + 1), c')) :
    execInstr cx fi (g + 1) (.block k body) c = .ok (.br n, c') := by
  simp [execInstr, h]

theorem execInstr_block_ret {g k : Nat} {body : List CInstr} {c c' : Cfg H}
    (h : execList cx fi g body c = .ok (.ret, c')) :
    execInstr cx fi (g + 1) (.block k body) c = .ok (.ret, c') := by
  simp [execInstr, h]

theorem execInstr_block_trap {g k : Nat} {body : List CInstr} {c : Cfg H} {t s}
    (h : execList cx fi g body c = .trap t s) :
    execInstr cx fi (g + 1) (.block k body) c = .trap t s := by
  simp [execInstr, h]

theorem execInstr_brIf {g l : Nat} {c : Cfg H} {v : UInt32} {s : List Value} (hs : c.stk = .i32 v :: s) :
    execInstr cx fi (g + 1) (.brIf l) c = .ok (if v != 0 then .br l else .next, { c with stk := s }) := by
  simp [execInstr, popI32, hs]

theorem execInstr_return (g : Nat) (c : Cfg H) : execInstr cx fi (g + 1) .return_ c = .ok (.ret, c) := by
  simp [execInstr]

theorem execInstr_ifFalse {g k fT : Nat} {fE : Option Nat} {thn els : List CInstr} {c : Cfg H}
    {s : List Value} (hs : c.stk = .i32 0 :: s) (hE : fE = none) :
    execInstr cx fi (g + 1) (.if_ k fT fE thn els) c = .ok (.next, { c with stk := s }) := by
  subst hE; simp [execInstr, popI32, hs]

theorem execInstr_ifTrue_next {g k fT : Nat} {fE : Option Nat} {thn els : List CInstr} {c cf c' : Cfg H}
    {v : UInt32} {s : List Value} (hs : c.stk = .i32 v :: s) (hv : v ≠ 0)
    (hf : chargeFuel (E := E) { c with stk := s } fT = .ok cf) (h : execList cx fi g thn cf = .ok (.next, c')) :
    execInstr cx fi (g + 1) (.if_ k fT fE thn els) c = .ok (.next, { c' with stk := restore k c'.stk s }) := by
  simp [execInstr, popI32, hs, hv, hf, h]

theorem execInstr_ifTrue_brSucc {g k fT n : Nat} {fE : Option Nat} {thn els : List CInstr} {c cf c' : Cfg H}
    {v : UInt32} {s : List Value} (hs : c.stk = .i32 v :: s) (hv : v ≠ 0)
    (hf : chargeFuel (E := E) { c with stk := s } fT = .ok cf) (h : execList cx fi g thn cf = .ok (.br (n + 1), c')) :
    execInstr cx fi (g + 1) (.if_ k fT fE thn els) c = .ok (.br n, c') := by
  simp [execInstr, popI32, hs, hv, hf, h]

theorem execInstr_ifTrue_trap {g k fT : Nat} {fE : Option Nat} {thn els : List CInstr} {c cf : Cfg H}
    {v : UInt32} {s : List Value} {t st} (hs : c.stk = .i32 v :: s) (hv : v ≠ 0)
    (hf : chargeFuel (E := E) { c with stk := s } fT = .ok cf) (h : execList cx fi g thn cf = .trap t st) :
    execInstr cx fi (g + 1) (.if_ k fT fE thn els) c = .trap t st := by
  simp [execInstr, popI32, hs, hv, hf, h]

/-- A call to an imported (host) function that returns normally. -/
theorem execInstr_callHost {g f : Nat} {ft : FuncType} {c : Cfg H} {res : List Value} {st : Store} {h : H}
    (hf : f < cx.nImports) (hft : cx.funcTypes[f]? = some ft) (hd : fi.depth ≠ MAX_RECURSION_DEPTH)
    (hsp : sp fi c + max ft.params.length ft.results.length ≤ MAX_VALUE_STACK)
    (hcall : cx.host.call g f (c.stk.take ft.params.length).reverse c.st c.h = .ok (res, st, h)) :
    execInstr cx fi (g + 2) (.call f) c =
      .ok (.next, { c with stk := res.reverse ++ c.stk.drop ft.params.length, st, h }) := by
  simp only [execInstr, callFunc, hft, Option.getD_some, hd, if_false, hf, if_true, Nat.not_lt.mpr hsp, hcall]

/-- Invoking a defined function whose body finishes normally. -/
theorem invoke_ok {g f : Nat} {cf : CFunc} {args : List Value} {st : Store} {h : H} {c1 c' : Cfg H} {fl : Flow}
    (hf : ¬ f < cx.nImports) (hcf : cx.funcs[f - cx.nImports]? = some cf)
    (ha : args.length + cf.maxStackHeight ≤ MAX_VALUE_STACK)
    (hfuel : chargeFuel (E := E) ({ stk := [], locals := (args ++ cf.locals.map Value.zero).toArray, st, h } : Cfg H)
      cf.entryFuel = .ok c1)
    (hb : execList cx { base := 0, nLocals := (args ++ cf.locals.map Value.zero).length, depth := 1 } g cf.body c1
      = .ok (fl, c')) :
    invoke cx g f args st h =
      .ok ((c'.stk.take (cx.funcTypes[f]?.getD default).results.length).reverse, c'.st, c'.h) := by
  have ha' : ¬ args.length > MAX_VALUE_STACK := by omega
  have ha'' : ¬ args.length + cf.maxStackHeight > MAX_VALUE_STACK := by omega
  simp only [invoke, hf, if_false, hcf, ha', ha'', hfuel, List.size_toArray, hb]

theorem chargeFuel_unmetered {c : Cfg H} (n : Nat) (h : c.st.fuel.metered = false) :
    chargeFuel (E := E) c n = .ok c := by
  simp [chargeFuel, Fuel.consume, h]

theorem execInstr_brIf_not {g l : Nat} {c : Cfg H} {v : UInt32} {s : List Value}
    (hs : c.stk = .i32 v :: s) (hv : v = 0) :
    execInstr cx fi (g + 1) (.brIf l) c = .ok (.next, { c with stk := s }) := by
  simp [execInstr, popI32, hs, hv]

end Wasm.Exec
