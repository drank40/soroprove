/-
Conformance of an emitted `--lean model` against real executions.

Input: the `<tag> model ...` lines of an oracle run (soroban-lean
`difftest/src/bin/e2e_*_oracle`): each successful call's function, caller, signers,
arguments, ledger info, and the contract's storage plus token balances before and after,
in the model's key format. For each call, every field of the entry point's `Spec`
structure is evaluated on the concrete step:
* a condition (guard, auth, transfer acceptance) must hold;
* `post` must give the observed storage at every key either side mentions or the model
  writes;
* `writes` and `ret` are not checked (the oracle doesn't record them).
Fields that depend on the open values `u : Unk` are evaluated at two different `u`;
whatever changes between the two is open (counted, not checked).

The model over-approximates the contract iff no call fails these checks.
-/
import Lean
import Gen.Model

open Lean Meta Contract

namespace Conform

/-- One observed call. -/
structure Obs where
  tag : String
  fn : String := ""
  caller : Int := 0
  self : Int := 0
  signers : List Int := []
  args : List (String × Int) := []
  argsA : List (String × Int) := []
  env : List (String × Int) := []
  pre : List (Key × Int) := []
  post : List (Key × Int) := []

def lookup (xs : List (String × Int)) (n : String) : Int := ((xs.find? (·.1 == n)).map (·.2)).getD 0
def tbl (xs : List (Key × Int)) : Storage := fun k => ((xs.find? (·.1 == k)).map (·.2)).getD 0

def Obs.step (o : Obs) : Step :=
  { call := { fn := o.fn, caller := o.caller, self := o.self, arg := lookup o.args, argA := lookup o.argsA,
              signers := o.signers, env := lookup o.env },
    pre := tbl o.pre, post := tbl o.post, writes := [], ret := 0 }

def u0 : Unk := { i := fun _ => 0, g := fun _ => 0, b := fun _ => false, k := fun _ => default, s := fun _ _ => 0 }
def u1 : Unk := { i := fun n => 7919 * n + 13, g := fun n => 7919 * n + 13, b := fun _ => true,
                  k := fun n => .var s!"open{n}", s := fun _ _ => 1 }

/-- `var X`, `entry M A`, `bal T A`, `has <key>`. -/
partial def parseKey : List String → Option (Key × List String)
  | "var" :: n :: r => some (.var n, r)
  | "entry" :: m :: a :: r => a.toInt?.map fun a => (.entry m a, r)
  | "bal" :: t :: a :: r => do pure (.bal (← t.toInt?) (← a.toInt?), r)
  | "has" :: r => do let (k, r) ← parseKey r; pure (.has k, r)
  | _ => none

def parse (lines : Array String) : Array Obs := Id.run do
  let mut order : Array String := #[]
  let mut m : Std.HashMap String Obs := {}
  for l in lines do
    match l.splitOn " " with
    | tag :: "model" :: rest =>
      if !m.contains tag then order := order.push tag
      let o := m.getD tag { tag }
      let num (s : String) : Int := s.toInt?.getD 0
      let o := match rest with
        | ["fn", f] => { o with fn := f }
        | ["caller", a] => { o with caller := num a }
        | ["self", a] => { o with self := num a }
        | ["signer", a] => { o with signers := o.signers ++ [num a] }
        | ["arg", n, v] => { o with args := o.args ++ [(n, num v)] }
        | ["argA", n, v] => { o with argsA := o.argsA ++ [(n, num v)] }
        | ["env", n, v] => { o with env := o.env ++ [(n, num v)] }
        | "pre" :: r => match parseKey r with
          | some (k, [v]) => { o with pre := o.pre ++ [(k, num v)] } | _ => o
        | "post" :: r => match parseKey r with
          | some (k, [v]) => { o with post := o.post ++ [(k, num v)] } | _ => o
        | _ => o
      m := m.insert tag o
    | _ => pure ()
  return order.filterMap m.get?

/-- An entry point's `Spec`, compiled. -/
structure Compiled where
  conds : Array (String × Bool × (Step → Unk → Bool))   -- name, depends on `u`, value
  post : Option (Step → Unk → Storage)
  writes : Option (Step → Unk → List Key)

unsafe def compile (fn : String) : MetaM Compiled := do
  let spec := (Name.mkStr `Contract fn).str "Spec"
  let some (.inductInfo ci) := (← getEnv).find? spec | throwError "no {spec} in the model"
  let ctorTy := (← getConstInfo ci.ctors[0]!).type
  let stepT := mkConst ``Contract.Step
  let unkT := mkConst ``Contract.Unk
  forallTelescope ctorTy fun xs _ => do
    let st := xs[0]!
    let go (u : Expr) : MetaM Compiled := do
      let mut conds := #[]
      let mut post := none
      let mut writes := none
      for f in xs[ci.numParams:] do
        let name := (← f.fvarId!.getUserName).toString
        let ty ← inferType f
        let lam (b : Expr) := mkLambdaFVars #[st, u] b
        match name with
        | "ret" => pure ()
        | "post" =>
          let some (_, _, rhs) := ty.eq? | throwError "{spec}.post is not an equation"
          post := some (← evalExpr (Step → Unk → Storage) (← mkArrow stepT (← mkArrow unkT (mkConst ``Contract.Storage))) (← lam rhs))
        | "writes" =>
          let some (_, _, rhs) := ty.eq? | throwError "{spec}.writes is not an equation"
          writes := some (← evalExpr (Step → Unk → List Key) (← mkArrow stepT (← mkArrow unkT (← mkAppM ``List #[mkConst ``Contract.Key]))) (← lam rhs))
        | _ =>
          let d ← mkDecide ty
          let v ← evalExpr (Step → Unk → Bool) (← mkArrow stepT (← mkArrow unkT (mkConst ``Bool))) (← lam d)
          conds := conds.push (name, ty.containsFVar u.fvarId!, v)
      pure { conds, post, writes }
    if ci.numParams == 2 then go xs[1]!
    else withLocalDeclD `u unkT go

def showKey : Key → String
  | .var n => s!"var {n}" | .entry m a => s!"entry {m} {a}" | .bal t a => s!"bal {t} {a}"
  | .has k => s!"has {showKey k}" | k => reprStr k

unsafe def run (path : String) : MetaM UInt32 := do
  let obs := parse (← IO.FS.lines path)
  let mut cache : Std.HashMap String Compiled := {}
  let mut fails := 0
  let mut stats : Std.HashMap String (Nat × Nat × Nat) := {}   -- calls, checks, open
  for o in obs do
    let c ← match cache.get? o.fn with
      | some c => pure c
      | none => do let c ← compile o.fn; cache := cache.insert o.fn c; pure c
    let st := o.step
    let mut checks := 0
    let mut opens := 0
    let mut bad : Array String := #[]
    for (n, depU, v) in c.conds do
      if depU && v st u0 != v st u1 then opens := opens + 1
      else
        checks := checks + 1
        if !v st u0 then bad := bad.push s!"{n} is false"
    if let some p := c.post then
      let p0 := p st u0
      let p1 := p st u1
      let ws := (c.writes.map (· st u0)).getD []
      let keys := (o.pre.map (·.1) ++ o.post.map (·.1) ++ ws).eraseDups
      for k in keys do
        if p0 k != p1 k then opens := opens + 1
        else
          checks := checks + 1
          if p0 k != st.post k then bad := bad.push s!"post at `{showKey k}`: model {p0 k}, real {st.post k}"
    let (a, b, d) := stats.getD o.fn (0, 0, 0)
    stats := stats.insert o.fn (a + 1, b + checks, d + opens)
    if !bad.isEmpty then
      fails := fails + 1
      IO.println s!"MISMATCH {o.tag} {o.fn}: {String.intercalate "; " bad.toList}"
  for (fn, (calls, checks, opens)) in stats.toList do
    IO.println s!"{fn}: {calls} calls, {checks} checks, {opens} open"
  IO.println s!"{obs.size} calls, {fails} not admitted by the model"
  return if fails == 0 then 0 else 1

end Conform

@[implemented_by Conform.run] opaque runImpl : String → MetaM UInt32

unsafe def main (args : List String) : IO UInt32 := do
  let [path] := args | IO.eprintln "usage: conform ORACLE_OUTPUT"; return 2
  initSearchPath (← findSysroot)
  enableInitializersExecution
  let env ← importModules #[{ module := `Gen.Model }, { module := `Init }] {} (loadExts := true)
  let ctx : Core.Context := { fileName := "<conform>", fileMap := default, maxHeartbeats := 0 }
  let (r, _) ← ((runImpl path).run' {} {}).toIO ctx { env }
  return r
