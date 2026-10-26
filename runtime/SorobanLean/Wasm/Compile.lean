/-
Transcription of wasmi 29.0.0's function translator (the parts that affect
observable behaviour): fuel charge points and amounts, and the emulated
value-stack height that determines `StackOverflow` on calls.

src: vendor/crates/soroban-wasmi-29.0.0/src/engine/func_builder/translator.rs
     (line numbers below), control_frame.rs, value_stack.rs, ../code_map.rs:74-84.

Fuel model (Eager mode, src: soroban-env-host budget/wasmi_helper.rs:144-156):
* A `ConsumeFuel(base)` charge point is created at function entry (translator.rs:146-157),
  at every `loop` header (:886-891; re-executed on each back-edge since the loop label is
  pinned before it), and at the start of the `then` (:914-918) and `else` (:972-978) arms.
* A `block` inherits its parent's charge point (:851-855).
* Every *reachable* translated instruction bumps the innermost frame's charge point by its
  cost class. `visit_if` bumps the parent (before pushing the frame, :909) and `visit_else`
  bumps the parent too, because the `if` frame has been popped at that point (:943-968).
* drop/keep fuel is `keep / 8` and only when `drop > 0` (config.rs `fuel_for_drop_keep`);
  without multi-value `keep ≤ 1`, so it is always 0 and stack heights don't matter for fuel.
* Calibrated costs: base 1, entity 3, load 2, store 1, call 67 (budget/wasmi_helper.rs:126-134),
  locals: `(params+locals) / 8` (config.rs `fuel_for_locals`, registers_per_fuel = 64/8).
-/
import SorobanLean.Wasm.Syntax

namespace Wasm

/-- src: soroban-env-host/src/budget/wasmi_helper.rs:126-134 and wasmi config.rs FuelCosts. -/
structure FuelCosts where
  base : Nat := 1
  entity : Nat := 3
  load : Nat := 2
  store : Nat := 1
  call : Nat := 67
  /-- `branch_kept_per_fuel` / `func_locals_per_fuel` = 64 bytes / 8 bytes per register. -/
  registersPerFuel : Nat := 8
  /-- `memory_bytes_per_fuel`. -/
  memoryBytesPerFuel : Nat := 64
  deriving Repr, Inhabited

/-- `FuelCosts::costs_per` (config.rs): `len / per`, 0 if `per = 0`. -/
def FuelCosts.costsPer (len per : Nat) : Nat := if per = 0 then 0 else len / per
def FuelCosts.forLocals (c : FuelCosts) (n : Nat) : Nat := FuelCosts.costsPer n c.registersPerFuel
def FuelCosts.forBytes (c : FuelCosts) (n : Nat) : Nat := FuelCosts.costsPer n c.memoryBytesPerFuel

/-- The Soroban-calibrated fuel costs. -/
def sorobanFuelCosts : FuelCosts := {}

/-- Compiled (translated) instructions: structured control flow with resolved
    arities and wasmi fuel charge amounts. -/
inductive CInstr where
  | simple (i : Instr)
  /-- `block` with result arity. -/
  | block (arity : Nat) (body : List CInstr)
  /-- `loop` with result arity and the amount its header `ConsumeFuel` charges per entry. -/
  | loop (arity : Nat) (fuel : Nat) (body : List CInstr)
  /-- `if` with result arity, the `then` arm's `ConsumeFuel` amount, the `else` arm's
      amount (`none` if there is no `else`, in which case nothing is charged). -/
  | if_ (arity : Nat) (fuelThen : Nat) (fuelElse : Option Nat) (thn els : List CInstr)
  | br (l : Nat)
  | brIf (l : Nat)
  | brTable (ls : List Nat) (dflt : Nat)
  | return_
  | call (f : Nat)
  | callIndirect (typeIdx tableIdx : Nat)
  | unreachable
  deriving Repr, Inhabited

structure CFunc where
  typeIdx : Nat
  params : List ValType
  results : List ValType
  /-- Non-parameter locals (zero-initialised). -/
  locals : List ValType
  /-- Amount charged by the function-entry `ConsumeFuel`. -/
  entryFuel : Nat
  /-- `FuncHeader::max_stack_height` = translator max height + len_locals (code_map.rs:74-84). -/
  maxStackHeight : Nat
  body : List CInstr
  deriving Repr, Inhabited

namespace Compile

/-- Environment needed to resolve block types and call signatures. -/
structure Env where
  types : Array FuncType
  /-- function index → its type (imports first). -/
  funcTypes : Array FuncType
  costs : FuelCosts

def blockArity (e : Env) : BlockType → Nat
  | .empty => 0
  | .val _ => 1
  | .typeIdx i => (e.types[i]?.map (·.results.length)).getD 0

/-- Emulated value stack height (value_stack.rs). -/
structure H where
  h : Nat
  maxH : Nat
  deriving Repr, Inhabited

def H.pushN (s : H) (n : Nat) : H := let h := s.h + n; { h, maxH := max s.maxH h }
def H.push (s : H) : H := s.pushN 1
def H.popN (s : H) (n : Nat) : H := { s with h := s.h - n }
def H.shrinkTo (s : H) (n : Nat) : H := { s with h := n }

/-- Static effect of a non-control instruction: (fuel cost class amount, pops, pushes).
    src: translator.rs translate_load/store (:495-540), consts (:1753-1780), cmp/unary/binary/
    conversion (:575-705), drop/select (:1331-1347), locals (:1383-1418), globals (:1421-1446),
    memory ops (:1550-1630), table/elem ops (:1662-1750). `nop` costs nothing (:833). -/
def simpleEffect (c : FuelCosts) : Instr → Nat × Nat × Nat
  | .nop => (0, 0, 0)
  | .drop => (c.base, 1, 0)
  | .select => (c.base, 3, 1)
  | .localGet _ => (c.base, 0, 1)
  | .localSet _ => (c.base, 1, 0)
  | .localTee _ => (c.base, 0, 0)
  | .globalGet _ => (c.entity, 0, 1)
  | .globalSet _ => (c.entity, 1, 0)
  | .load _ _ => (c.load, 1, 1)
  | .store _ _ => (c.store, 2, 0)
  | .memorySize => (c.entity, 0, 1)
  | .memoryGrow => (c.entity, 0, 0)   -- no stack-height change (:1569-1580)
  | .memoryInit _ => (c.entity, 3, 0)
  | .dataDrop _ => (c.entity, 0, 0)
  | .memoryCopy => (c.entity, 3, 0)
  | .memoryFill => (c.entity, 3, 0)
  | .tableInit _ _ => (c.entity, 3, 0)
  | .elemDrop _ => (c.entity, 0, 0)
  | .tableCopy _ _ => (c.entity, 3, 0)
  | .i32Const _ => (c.base, 0, 1)
  | .i64Const _ => (c.base, 0, 1)
  | .eqz _ => (c.base, 0, 0)          -- translate_unary_cmp: no height change
  | .relop _ _ => (c.base, 2, 1)
  | .unop _ _ => (c.base, 0, 0)
  | .binop _ _ => (c.base, 2, 1)
  | .i32WrapI64 | .i64ExtendI32S | .i64ExtendI32U => (c.base, 0, 0)
  | .extend8S _ | .extend16S _ | .i64Extend32S => (c.base, 0, 0)
  | _ => (0, 0, 0)  -- control instructions are handled by `instr`

/-- Translation state: emulated height, reachability. -/
structure S where
  hs : H
  reachable : Bool
  deriving Repr, Inhabited

/-- Result of translating a sequence: compiled code, fuel added to the current
    (innermost) charge point, and the final state. -/
abbrev R := List CInstr × Nat × S

mutual
/-- Translate an instruction list. `frames` is the number of enclosing control
    frames (the function body block counts as one), used to detect branches to
    the root frame (which wasmi translates as `return`, translator.rs:787-804). -/
def instrs (e : Env) (frames : Nat) : List Instr → S → R
  | [], s => ([], 0, s)
  | i :: is, s =>
    let (c, f1, s1) := instr e frames i s
    let (cs, f2, s2) := instrs e frames is s1
    (c ++ cs, f1 + f2, s2)

def instr (e : Env) (frames : Nat) (i : Instr) (s : S) : R :=
  let c := e.costs
  match i with
  | .unreachable =>
      if s.reachable then ([.unreachable], c.base, { s with reachable := false }) else ([.unreachable], 0, s)
  | .block bt body =>
      let k := blockArity e bt
      if s.reachable then
        let entryH := s.hs.h
        let (cb, fb, sb) := instrs e (frames + 1) body s
        -- visit_end: pin label, reachable := frame was reachable (true), shrink, push results
        let s' : S := { hs := (sb.hs.shrinkTo entryH).pushN k, reachable := true }
        ([.block k cb], fb, s')   -- block shares parent's charge point
      else
        let (cb, _, sb) := instrs e (frames + 1) body s
        -- unreachable frame: no shrink (stack_height None), results pushed, reachability stays
        ([.block k cb], 0, { sb with hs := sb.hs.pushN k, reachable := s.reachable })
  | .loop bt body =>
      let k := blockArity e bt
      if s.reachable then
        let entryH := s.hs.h
        let (cb, fb, sb) := instrs e (frames + 1) body s
        let s' : S := { hs := (sb.hs.shrinkTo entryH).pushN k, reachable := true }
        ([.loop k (c.base + fb) cb], 0, s')
      else
        let (cb, _, sb) := instrs e (frames + 1) body s
        ([.loop k 0 cb], 0, { sb with hs := sb.hs.pushN k, reachable := s.reachable })
  | .if_ bt thn els hasElse =>
      let k := blockArity e bt
      if s.reachable then
        let s0 : S := { s with hs := s.hs.popN 1 }   -- condition
        let entryH := s0.hs.h
        -- parent pays for BrIfEqz (:909)
        let (ct, ft, st) := instrs e (frames + 1) thn s0
        if hasElse then
          -- visit_else: parent pays `base` for the Br if end-of-then is reachable (:961-968)
          let fBr := if st.reachable then c.base else 0
          let sE : S := { hs := st.hs.shrinkTo entryH, reachable := true }
          let (ce, fe, se) := instrs e (frames + 1) els sE
          let s' : S := { hs := (se.hs.shrinkTo entryH).pushN k, reachable := true }
          ([.if_ k (c.base + ft) (some (c.base + fe)) ct ce], c.base + fBr, s')
        else
          let s' : S := { hs := (st.hs.shrinkTo entryH).pushN k, reachable := true }
          ([.if_ k (c.base + ft) none ct []], c.base, s')
      else
        let (ct, _, st) := instrs e (frames + 1) thn s
        -- else of an unreachable if is ignored entirely (:928-936)
        let (ce, _, _) := instrs e (frames + 1) els st
        ([.if_ k 0 (if hasElse then some 0 else none) ct ce], 0, { st with hs := st.hs.pushN k, reachable := s.reachable })
  | .br l =>
      if s.reachable then ([.br l], c.base, { s with reachable := false }) else ([.br l], 0, s)
  | .brIf l =>
      if s.reachable then
        let s' : S := { s with hs := s.hs.popN 1 }
        -- branch to the root frame becomes ReturnIfNez with no fuel bump (:1081-1086)
        let f := if l + 1 = frames then 0 else c.base
        ([.brIf l], f, s')
      else ([.brIf l], 0, s)
  | .brTable ls d =>
      if s.reachable then ([.brTable ls d], c.base, { hs := s.hs.popN 1, reachable := false })
      else ([.brTable ls d], 0, s)
  | .return_ =>
      if s.reachable then ([.return_], c.base, { s with reachable := false }) else ([.return_], 0, s)
  | .call f =>
      if s.reachable then
        let ft := e.funcTypes[f]?.getD default
        ([.call f], c.call, { s with hs := (s.hs.popN ft.params.length).pushN ft.results.length })
      else ([.call f], 0, s)
  | .callIndirect t tb =>
      if s.reachable then
        let ft := e.types[t]?.getD default
        ([.callIndirect t tb], c.call, { s with hs := ((s.hs.popN 1).popN ft.params.length).pushN ft.results.length })
      else ([.callIndirect t tb], 0, s)
  | other =>
      if s.reachable then
        let (f, pops, pushes) := simpleEffect c other
        ([.simple other], f, { s with hs := (s.hs.popN pops).pushN pushes })
      else ([.simple other], 0, s)
end

/-- Translate one function (translator.rs:111-198): the body block's charge point
    starts at `base`, `finish_translate_locals` adds `fuel_for_locals(params+locals)`,
    and the final `end` of the body is translated as `return` if reachable (:1005-1010). -/
def func (e : Env) (f : Func) : CFunc :=
  let ft := e.types[f.typeIdx]?.getD default
  let nLocals := ft.params.length + f.locals.length
  let s0 : S := { hs := { h := 0, maxH := 0 }, reachable := true }
  let (cb, fb, sb) := instrs e 1 f.body s0
  let fEnd := if sb.reachable then e.costs.base else 0
  { typeIdx := f.typeIdx, params := ft.params, results := ft.results, locals := f.locals,
    entryFuel := e.costs.base + e.costs.forLocals nLocals + fb + fEnd,
    maxStackHeight := sb.hs.maxH + f.locals.length,
    body := cb }

def mkEnv (m : Module) (costs : FuelCosts := sorobanFuelCosts) : Env :=
  let imported := m.importedFuncTypes.map fun t => m.types[t]?.getD default
  let defined := m.funcs.map fun f => m.types[f.typeIdx]?.getD default
  { types := m.types, funcTypes := imported ++ defined, costs }

def module (m : Module) (costs : FuelCosts := sorobanFuelCosts) : Array CFunc :=
  let e := mkEnv m costs
  m.funcs.map (func e)

end Compile
end Wasm
