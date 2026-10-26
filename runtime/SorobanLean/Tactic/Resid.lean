/-
A residualizing evaluator for symbolic execution of the model.

`Resid.whnfR e` computes a weak head normal form of `e` that is definitionally equal
to `e`, like `Meta.whnf`, but

* every closed subterm (no free variables) is handed to the kernel (`Kernel.whnf`),
  which is orders of magnitude faster than Meta-level reduction, and the resulting
  constructor values are normalised once and cached;
* constructor values are normalised field by field, so data that merely *mentions*
  the symbolic state but evaluates to closed values becomes closed (and kernel-fast);
* *atoms* (machine-integer / bit-vector / `Nat` arithmetic) whose arguments stay
  symbolic are never unfolded, so a computation stuck on symbolic data remains in a
  user-level form that lemmas can match;
* recursive definitions are unfolded through smart unfolding or their unfold equation
  (never through `brecOn`);
* when reduction is stuck because a major premise / discriminant is symbolic, the stuck
  term is returned (with its reduced discriminant) so the caller can resolve it.

Nothing here is trusted: every step is a definitional unfolding, and the final proof is
checked by the kernel as usual.
-/
import Lean

open Lean Meta

namespace Resid

structure Stats where
  steps : Nat := 0
  kernelCalls : Nat := 0
  kernelMs : Nat := 0
  cacheHits : Nat := 0

/-- Large caches live in their own references so that updating them never copies. -/
structure Caches where
  closed : IO.Ref (Std.HashMap Expr Expr)
  open_ : IO.Ref (Std.HashMap Expr Expr)
  /-- data-field mask of each constructor (`true` = data, not a parameter/type/proof) -/
  fields : IO.Ref (Std.HashMap Name (Array Bool))
  /-- kernel calls per head constant: (count, ms) -/
  hist : IO.Ref (Std.HashMap Name (Nat × Nat))
  /-- terms known to be values (memo for `isSynValue`) -/
  values : IO.Ref (Std.HashSet Expr)

def Caches.new : IO Caches := do
  pure { closed := ← IO.mkRef {}, open_ := ← IO.mkRef {}, fields := ← IO.mkRef {}, hist := ← IO.mkRef {}, values := ← IO.mkRef {} }

structure St where
  stats : Stats := {}
  maxSteps : Nat := 1000000000
  /-- print progress every `progress` steps (0 = never) -/
  progress : Nat := 0
  /-- log every kernel call to the progress file (debugging) -/
  traceKernel : Bool := false
  trail : List Name := []

abbrev M := ReaderT Caches (StateRefT St MetaM)

/-- Run an evaluator computation with fresh caches. -/
def M.run' {α} (x : M α) (st : St := {}) : MetaM (α × St × Caches) := do
  let c ← Caches.new
  let (a, st) ← (x c).run st
  pure (a, st, c)

def isClosed (e : Expr) : Bool := !e.hasFVar && !e.hasMVar

/-- Machine arithmetic that must stay folded when applied to symbolic arguments. -/
def atomPrefixes : List Name :=
  [`UInt8, `UInt16, `UInt32, `UInt64, `USize, `Int8, `Int16, `Int32, `Int64, `BitVec, `Fin]

def atomNames : List Name :=
  [``Nat.add, ``Nat.sub, ``Nat.mul, ``Nat.div, ``Nat.mod, ``Nat.pow, ``Nat.land, ``Nat.lor,
   ``Nat.xor, ``Nat.shiftLeft, ``Nat.shiftRight, ``Nat.beq, ``Nat.ble, ``Nat.decEq, ``Nat.decLt,
   ``Nat.decLe, ``Nat.log2, ``Nat.testBit, ``Int.add, ``Int.sub, ``Int.mul,
   ``Int.emod, ``Int.ediv, ``Int.ofNat, ``Int.toNat, ``Int.decEq, ``Int.neg,
   ``HAdd.hAdd, ``HSub.hSub, ``HMul.hMul, ``HDiv.hDiv, ``HMod.hMod, ``HPow.hPow,
   ``HAnd.hAnd, ``HOr.hOr, ``HXor.hXor, ``HShiftLeft.hShiftLeft, ``HShiftRight.hShiftRight,
   ``Complement.complement, ``Neg.neg, ``LT.lt, ``LE.le, ``GT.gt, ``GE.ge,
   ``instDecidableEqNat]

/-- Combinators whose arguments must not be evaluated eagerly. -/
def lazyNames : List Name :=
  [``ite, ``dite, ``cond, ``and, ``or, ``Bool.and, ``Bool.or, ``Decidable.decide, ``Decidable.casesOn,
   ``Decidable.rec, ``Bool.casesOn, ``Option.elim, ``Except.tryCatch, ``tryCatch,
   ``MonadExcept.tryCatch, ``bind, ``Bind.bind, ``ExceptT.bind, ``StateT.bind, ``ExceptT.bindCont,
   ``Option.bind, ``Except.bind, ``HOrElse.hOrElse, ``OrElse.orElse]

def isLazy (n : Name) : Bool :=
  lazyNames.contains n || n.isInternal ||
    (match n with | .str _ s => s.startsWith "match_" | _ => false)

/-- Data-structure functions tried with the kernel on open terms. -/
def isContainerOp (n : Name) : Bool :=
  -- only operations that never call back into user code (no folds, maps, loops)
  [``List.take, ``List.drop, ``List.length, ``List.append, ``List.reverse, ``List.reverseAux,
   ``List.toArray, ``List.isEmpty, ``List.head?, ``List.tail, ``List.getD,
   ``List.set, ``List.replicate, ``List.range,
   ``Array.size, ``Array.toList, ``Array.extract, ``Array.push, ``Array.set!,
   ``Array.pop, ``Array.back?, ``Array.getD, ``Array.append, ``Array.mkEmpty,
   ``Array.replicate,
   ``ByteArray.size, ``ByteArray.data, ``ByteArray.extract, ``ByteArray.append,
   ``ByteArray.push, ``ByteArray.get!].contains n

/-- Pure data-processing functions that branch only on concrete structure (XDR readers
    and writers): evaluated by the kernel even when their input holds symbolic values. -/
def isKernelFirst (n : Name) : Bool := (`Xdr).isPrefixOf n

def isAtom (n : Name) : Bool :=
  atomNames.contains n || atomPrefixes.any (·.isPrefixOf n)

/-- Data-field mask of a constructor. -/
def fieldMask (n : Name) : M (Array Bool) := do
  if let some m := (← (← read).fields.get)[n]? then return m
  let some (.ctorInfo ci) := (← getEnv).find? n | return #[]
  let m ← forallTelescopeReducing ci.type fun xs _ => do
    let mut m := #[]
    for h : i in [0:xs.size] do
      if i < ci.numParams then m := m.push false
      else
        let t ← inferType xs[i]
        let isData := !(← isProp t) && !(← isType xs[i])
        m := m.push isData
    pure m
  (← read).fields.modify (·.insert n m)
  pure m

def ctorName? (e : Expr) : MetaM (Option Name) := do
  let .const n _ := e.getAppFn | return none
  if (← getEnv).isConstructor n then return some n else return none

mutual
/-- Is `e` already a value (literal, lambda, constructor application with value data
    fields, neutral term)? Purely syntactic; memoized. -/
partial def isSynValue (e : Expr) : M Bool := do
  if e.isLit || e.isSort || e.isForall || e.isLambda || e.isFVar then return true
  if (← (← read).values.get).contains e then return true
  let r ← isSynValueCore e
  if r then (← read).values.modify (·.insert e)
  pure r

partial def isSynValueCore (e : Expr) : M Bool := do
  -- neutral terms: an atom applied to values, at least one of them symbolic (closed atom
  -- applications are not values: the kernel computes them)
  if e.hasFVar then
    if let .const n _ := e.getAppFn then
      if isAtom n then
        for a in e.getAppArgs do
          if isClosed a then continue   -- types, instances, constants
          unless ← isSynValue a do return false
        return true
  let some n ← ctorName? e | return false
  let mask ← fieldMask n
  let args := e.getAppArgs
  for h : i in [0:args.size] do
    if mask.getD i false then
      unless ← isSynValue args[i] do return false
  return true

end

def kernelWhnf (e : Expr) : M Expr := do
  if (← get).traceKernel then
    let h ← IO.FS.Handle.mk "/tmp/resid-progress.log" .append
    h.putStrLn s!"  kernel: head {e.getAppFn.constName?} depth {e.approxDepth} consts {(e.getUsedConstants.toList.take 8)}"
    h.flush
  let t0 ← IO.monoMsNow
  let r := match Kernel.whnf (← getEnv) (← getLCtx) e with
    | .ok r => r
    | .error _ => e
  let t1 ← IO.monoMsNow
  if t1 - t0 > 500 then
    IO.eprintln s!"[resid] slow kernel call {t1 - t0} ms: head {e.getAppFn.constName?} args {e.getAppNumArgs} consts {(e.getUsedConstants.toList.take 12)}"
  let hn := e.getAppFn.constName?.getD `_
  (← read).hist.modify fun h => h.insert hn (let (c, t) := h.getD hn (0, 0); (c + 1, t + (t1 - t0)))
  modify fun s => { s with stats.kernelCalls := s.stats.kernelCalls + 1,
                           stats.kernelMs := s.stats.kernelMs + (t1 - t0) }
  pure r

/-- If `e` is a recursor application: the recursor and its major premise index. -/
def recMajor? (e : Expr) : MetaM (Option (RecursorVal × Nat)) := do
  let .const n _ := e.getAppFn | return none
  match (← getEnv).find? n with
  | some (.recInfo r) => return some (r, r.getMajorIdx)
  | _ => return none

def setArg (e : Expr) (i : Nat) (a : Expr) : Expr :=
  mkAppN e.getAppFn (e.getAppArgs.set! i a)

/-- Unfold `f a₁ … aₙ` through `f.eq_def` (definitionally equal; direct recursive
    calls instead of `brecOn`). -/
def unfoldViaEqn? (n : Name) (e : Expr) : MetaM (Option Expr) := do
  let some eqn ← getUnfoldEqnFor? n (nonRec := true) | return none
  let info ← getConstInfo eqn
  let .const _ lvls := e.getAppFn | return none
  let ty := info.type.instantiateLevelParams info.levelParams lvls
  let args := e.getAppArgs
  let k := ty.getForallArity
  if k > args.size then return none
  let ty ← instantiateForall ty (args.extract 0 k)
  let some (_, _, rhs) := ty.eq? | return none
  return some (mkAppN rhs (args.extract k args.size))

/-- One delta step of a non-atom, non-constructor constant application. -/
def unfoldStep? (n : Name) (e : Expr) : MetaM (Option Expr) := do
  -- The unfold equation is a pure instantiation. `unfoldDefinition?` (smart unfolding)
  -- runs Meta-level `whnf` on match discriminants, which can reach into the whole
  -- symbolic state, so it is the last resort.
  if let some e' ← unfoldViaEqn? n e then return some e'
  if let some e' ← delta? e then return some e'
  let h ← IO.FS.Handle.mk "/tmp/resid-progress.log" .append
  h.putStrLn s!"  smart-unfolding fallback: {n}"; h.flush
  unfoldDefinition? e

/-- Outcome of weak head normalisation. -/
inductive Out where
  | done (e : Expr)
  /-- `e` is stuck on the symbolic value `major` (a reduced major premise / discriminant). -/
  | stuck (e : Expr) (major : Expr)

def Out.expr : Out → Expr
  | .done e | .stuck e _ => e

/-- Nullary data definitions (e.g. network settings, inputs): their values are worth
    computing once and substituting, since the kernel does not cache across calls. -/
def isDataConst (n : Name) : MetaM Bool := do
  let some (.defnInfo d) := (← getEnv).find? n | return false
  if !d.levelParams.isEmpty then return false
  let ty := d.type
  if ty.isForall || ty.isSort then return false
  if ← isProp ty then return false
  -- instances are records of functions; leave them to the kernel
  if (← isInstance n) then return false
  return true

mutual
/-- Closed term → value; cached. Call-by-value: the targets of projections and the
    data arguments of (non-lazy) applications are evaluated first, so the kernel only
    ever sees applications of functions to values, never unevaluated computations
    (which it would recompute on every call, having no cache across calls). -/
partial def closedValue (e : Expr) : M Expr := do
  if let some v := (← (← read).closed.get)[e]? then
    modify fun s => { s with stats.cacheHits := s.stats.cacheHits + 1 }
    return v
  if ← isSynValue e then return e
  let r ← closedValueCore e
  (← read).closed.modify (·.insert e r)
  pure r

partial def closedValueCore (e : Expr) : M Expr := do
  match e with
  | .mdata _ b => closedValue b
  | .proj sn i x =>
    let v ← closedValue x
    match ← projectCore? v i with
    | some r => closedValue r
    | none => normFields (← kernelWhnf (.proj sn i v))
  | .const n _ =>
    if ← isDataConst n then normFields (← kernelWhnf e) else pure e
  | .app .. =>
    let f := e.getAppFn
    let args := e.getAppArgs
    match f with
    | .const n _ =>
      if (← getEnv).isConstructor n then return ← normFields e
      let lazyHead := isLazy n || (← isMatcher n) || (← recMajor? e).isSome
      let mut out := args
      -- `ite`/`dite`: the decision procedure is evaluated before a branch is taken
      if (n == ``ite || n == ``dite) && args.size ≥ 3 then
        let inst := args[2]!
        if !(← isSynValue inst) then out := out.set! 2 (← closedValue inst)
      unless lazyHead do
        for h : i in [0:args.size] do
          let a := args[i]
          if a.isLambda || (← isSynValue a) then continue
          if (← isProp (← inferType a)) || (← isType a) then continue
          out := out.set! i (← closedValue a)
      let r ← kernelWhnf (mkAppN f out)
      normFields r
    | _ => normFields (← kernelWhnf e)
  | _ => normFields (← kernelWhnf e)

/-- Strictly normalise a value produced by the kernel: its data fields are kernel
    thunks; each is evaluated by the kernel when that yields a constructor or literal,
    otherwise by `whnfR` (so no field is left as a lazy reference to an earlier state,
    which would make later projections walk the whole history). -/
partial def kernelDeep (e : Expr) (depth : Nat) : M Expr := do
  if depth == 0 then return ← normFields e
  let some n ← ctorName? e | return e
  let mask ← fieldMask n
  let args := e.getAppArgs
  let mut out := args
  for h : i in [0:args.size] do
    if !(mask.getD i false) then continue
    let a := args[i]
    if a.isLit || a.isFVar || a.isLambda then continue
    if ← isSynValue a then continue
    let r ← kernelWhnf a
    if (← ctorName? r).isSome then out := out.set! i (← kernelDeep r (depth - 1))
    else if r.isLit then out := out.set! i r
    else out := out.set! i (← whnfR a).expr
  return mkAppN e.getAppFn out

/-- Normalise the data fields of a constructor application (closed fields by
    `closedValue`, open ones by `whnfR`). -/
partial def normFields (e : Expr) : M Expr := do
  let some n ← ctorName? e | return e
  let mask ← fieldMask n
  let args := e.getAppArgs
  let mut out := args
  let mut changed := false
  for h : i in [0:args.size] do
    if mask.getD i false then
      let a := args[i]
      if ← isSynValue a then continue
      let a' ← if isClosed a then closedValue a else pure (← whnfR a).expr
      if !(a' == a) then
        out := out.set! i a'; changed := true
  return if changed then mkAppN e.getAppFn out else e

partial def whnfR (e : Expr) : M Out := do
  if isClosed e then return .done (← closedValue e)
  if let some v := (← (← read).open_.get)[e]? then
    modify fun s => { s with stats.cacheHits := s.stats.cacheHits + 1 }
    return .done v
  -- Open results are not cached: they embed the (growing) symbolic state, so keeping
  -- them all retains memory quadratic in the length of the run. Already-normal open
  -- data (constructors over values and neutral terms) is recognised instead.
  if e.isLit || e.isFVar || e.isLambda then return .done e
  whnfCoreR e

partial def whnfCoreR (e : Expr) : M Out := do
  modify fun s => { s with stats.steps := s.stats.steps + 1 }
  let st ← get
  if st.stats.steps > st.maxSteps then throwError "resid: step limit"
  if st.stats.steps == 999999999 then modify fun s => { s with traceKernel := true }
  if st.traceKernel then
    let h ← IO.FS.Handle.mk "/tmp/resid-progress.log" .append
    let statm ← IO.FS.readFile "/proc/self/statm"
    let rssMb := ((statm.splitOn " ")[1]!).toNat! * 4 / 1024
    h.putStrLn s!"step {st.stats.steps} rss {rssMb}: {e.ctorName} head {e.getAppFn.constName?} nargs {e.getAppNumArgs} depth {e.approxDepth}"
    h.flush
  if st.progress > 0 && st.stats.steps % st.progress == 0 then
    let statm ← IO.FS.readFile "/proc/self/statm"
    let rssPages := ((statm.splitOn " ")[1]!).toNat!
    -- `#eval` captures stdout/stderr until it finishes, so progress goes to a file
    let h ← IO.FS.Handle.mk "/tmp/resid-progress.log" .append
    h.putStrLn s!"[resid] step {st.stats.steps} rss {rssPages * 4 / 1024} MB kernel {st.stats.kernelCalls} closedMs {st.stats.kernelMs} trail {st.trail.take 12}"
    h.flush
  if let some n := e.getAppFn.constName? then
    modify fun s => { s with trail := (n :: s.trail).take 40 }
  match e with
  | .mdata _ b => whnfR b
  | .letE _ _ v b _ => whnfR (b.instantiate1 v)
  | .proj sn i s =>
    match ← whnfR s with
    | .done s' =>
      match ← projectCore? s' i with
      | some r => whnfR r
      | none => return .done (.proj sn i s')
    | .stuck s' m => return .stuck (.proj sn i s') m
  | .app .. =>
    let f := e.getAppFn
    match f with
    | .lam .. => whnfR e.headBeta
    | .mdata _ f' => whnfR (mkAppN f' e.getAppArgs)
    | .letE _ _ v b _ => whnfR (mkAppN (b.instantiate1 v) e.getAppArgs)
    | .const n _ =>
      if (← getEnv).isConstructor n then return .done (← normFields e)
      -- Container operations that never inspect element values (length, take, drop,
      -- append, extract, …) evaluate fine in the kernel even when elements are
      -- symbolic: try that first, keep the result only if it is a constructor.
      if !isLazy n && !isAtom n && !(← isMatcher n) && (← recMajor? e).isNone then
        let mut ready := true
        for a in e.getAppArgs do
          unless isClosed a || (← isSynValue a) do ready := false; break
        if ready then
          let r ← kernelWhnf e
          if (← ctorName? r).isSome || r.isLit then return .done (← kernelDeep r 64)
      if isContainerOp n then
        -- only once every open argument is a value: otherwise the kernel would also
        -- evaluate whatever computation produces it (the call-by-value step below
        -- evaluates the arguments first and the rebuilt call comes back here)
        let mut argsReady := true
        for a in e.getAppArgs do
          unless isClosed a || (← isSynValue a) do argsReady := false; break
        if argsReady then
          let r ← kernelWhnf e
          if (← ctorName? r).isSome || r.isLit then return .done r
      if isAtom n then
        -- evaluate the arguments; computed by the kernel if they all become closed
        let args := e.getAppArgs
        let mut out := args
        for h : i in [0:args.size] do
          let a := args[i]
          unless isClosed a do
            match ← whnfR a with
            | .done a' => out := out.set! i a'
            | .stuck a' m => return .stuck (mkAppN f (out.set! i a')) m
        let e' := mkAppN f out
        if isClosed e' then return .done (← closedValue e')
        return .done e'
      if let some (_, mi) ← recMajor? e then
        if mi < e.getAppNumArgs then
          match ← whnfR (e.getArg! mi) with
          | .done maj =>
            let maj := match maj with
              | .lit (.natVal 0) => mkConst ``Nat.zero
              | .lit (.natVal (k + 1)) => mkApp (mkConst ``Nat.succ) (mkRawNatLit k)
              | m => m
            let e' := setArg e mi maj
            let e'' ← whnfCore e'
            if e'' == e' then return .stuck e' maj
            return ← whnfR e''
          | .stuck maj m => return .stuck (setArg e mi maj) m
        return .done e
      if let some info ← getMatcherInfo? n then
        -- Unfold the matcher itself (its body is a chain of `casesOn`, handled by the
        -- recursor rule below). Meta's `reduceMatcher?` is avoided: it runs a full
        -- Meta `whnf` on the instantiated matcher, which for nested patterns forces
        -- fields of the (symbolic, possibly huge) discriminants through smart unfolding.
        let args := e.getAppArgs
        let d0 := info.numParams + 1
        if d0 + info.numDiscrs ≤ args.size then
          let mut cur := e
          for k in [0:info.numDiscrs] do
            match ← whnfR (cur.getArg! (d0 + k)) with
            | .done d => cur := setArg cur (d0 + k) d
            | .stuck d m => return .stuck (setArg cur (d0 + k) d) m
          match ← delta? cur with
          | some e' => return ← whnfR e'.headBeta
          | none => return .done cur
      -- Call-by-value (as Lean's compiled code): evaluate the data arguments of an
      -- ordinary function first, and use the kernel if the call becomes closed.
      -- Lazy control-flow combinators are excluded.
      unless isLazy n do
        let args := e.getAppArgs
        let mut out := args
        let mut changed := false
        for h : i in [0:args.size] do
          let a := args[i]
          if isClosed a || a.isLambda then continue
          if (← get).traceKernel then
            let hh ← IO.FS.Handle.mk "/tmp/resid-progress.log" .append
            hh.putStrLn s!"   cbv {n} arg {i}: {a.ctorName} head {a.getAppFn.constName?} depth {a.approxDepth}"
            hh.flush
          if (← isProp (← inferType a)) || (← isType a) then continue
          if (← get).traceKernel then
            let hh ← IO.FS.Handle.mk "/tmp/resid-progress.log" .append
            hh.putStrLn s!"   inferType done"; hh.flush
          match ← whnfR a with
          | .done a' => if !(a' == a) then out := out.set! i a'; changed := true
          | .stuck a' m => return .stuck (mkAppN f (out.set! i a')) m
        if changed then
          let e' := mkAppN f out
          if isClosed e' then return .done (← closedValue e')
          return ← whnfR e'
      if (← get).traceKernel then
        let hh ← IO.FS.Handle.mk "/tmp/resid-progress.log" .append
        hh.putStrLn s!"   unfold {n}"; hh.flush
      match ← unfoldStep? n e with
      | some e' =>
        if (← get).traceKernel then
          let hh ← IO.FS.Handle.mk "/tmp/resid-progress.log" .append
          hh.putStrLn s!"   unfolded {n} -> {e'.getAppFn.constName?} {e'.ctorName}"; hh.flush
        whnfR e'
      | none =>
        let e' ← whnfCore e
        if e' == e then return .done e else whnfR e'
    | .proj .. =>
      match ← whnfR f with
      | .done f' => if f' == f then return .done e else whnfR (mkAppN f' e.getAppArgs)
      | .stuck f' m => return .stuck (mkAppN f' e.getAppArgs) m
    | _ => return .done e
  | .const n _ =>
    if isAtom n || (← getEnv).isConstructor n then return .done e
    match ← unfoldStep? n e with
    | some e' => whnfR e'
    | none => return .done e
  | _ => return .done e
end

end Resid
