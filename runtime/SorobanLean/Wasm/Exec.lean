/-
Interpreter for compiled (wasmi-translated) functions.

Semantics follow soroban-wasmi 29.0.0's executor
(src: vendor/crates/soroban-wasmi-29.0.0/src/engine/executor.rs and stack/), including:
* fuel charged at the translator's charge points (see Compile.lean) plus Eager dynamic
  fuel for bulk memory/table ops (executor.rs:777-786 `consume_fuel_with_eager`);
* the call-stack depth limit (frames.rs:74-80; the root frame is pushed by `init`,
  frames.rs:67-70, without the check) and the value-stack reserve check
  (values/mod.rs:182-188, 234-247) for both Wasm callees and host functions
  (stack/mod.rs:174-206);
* the sign-extending `i32 as usize` conversion of bulk-memory operands.

Every trap carries the store and host state at the moment of the trap.

`gas` is a step budget of the Lean definition (each instruction, loop iteration
and call consumes one unit); `Res.gasOut` never corresponds to runtime behaviour.
-/
import SorobanLean.Wasm.Runtime

namespace Wasm

/-- Static context of one module instance. -/
structure Ctx (H E : Type) where
  host : HostIface H E
  funcs : Array CFunc
  nImports : Nat
  /-- Type of every function index (imports first). -/
  funcTypes : Array FuncType
  types : Array FuncType
  costs : FuelCosts := sorobanFuelCosts

/-- Mutable configuration threaded through execution. -/
structure Cfg (H : Type) where
  stk : List Value
  locals : Array Value
  st : Store
  h : H

/-- Per-frame static info: value-stack base of the frame's locals, number of
    locals (params included), and call depth (root frame = 1). -/
structure FrameInfo where
  base : Nat
  nLocals : Nat
  depth : Nat

inductive Flow where
  | next
  | br (n : Nat)
  | ret
  deriving DecidableEq, Repr, Inhabited

namespace Exec

variable {H E : Type}

/-- Results within a frame: the trap state is the store and host state. -/
abbrev R (H E α : Type) := Res E (Store × H) α

@[inline] def trapAt {α} (c : Cfg H) (t : TrapCode) : R H E α := .trap (.code t) (c.st, c.h)

@[inline] def pop1 (c : Cfg H) : R H E (Value × Cfg H) :=
  match c.stk with
  | v :: s => .ok (v, { c with stk := s })
  | [] => trapAt c .UnreachableCodeReached  -- impossible for validated code

@[inline] def popI32 (c : Cfg H) : R H E (UInt32 × Cfg H) :=
  match c.stk with
  | .i32 v :: s => .ok (v, { c with stk := s })
  | _ => trapAt c .UnreachableCodeReached  -- impossible for validated code

@[inline] def popI64 (c : Cfg H) : R H E (UInt64 × Cfg H) :=
  match c.stk with
  | .i64 v :: s => .ok (v, { c with stk := s })
  | _ => trapAt c .UnreachableCodeReached

@[inline] def push (c : Cfg H) (v : Value) : Cfg H := { c with stk := v :: c.stk }

@[inline] def chargeFuel (c : Cfg H) (n : Nat) : R H E (Cfg H) :=
  match c.st.fuel.consume n with
  | .ok f => .ok { c with st := { c.st with fuel := f } }
  | .error t => trapAt c t

/-- Eager dynamic fuel then `exec` (executor.rs:777-786). -/
@[inline] def withFuel {α} (c : Cfg H) (n : Nat) (k : Cfg H → R H E α) : R H E α :=
  (chargeFuel c n).bind k

@[inline] def lift {α} (c : Cfg H) : Except TrapCode α → R H E α := Res.ofExcept (c.st, c.h)

def binop32 (op : IBinop) (a b : UInt32) : Except TrapCode UInt32 :=
  match op with
  | .add => .ok (a + b) | .sub => .ok (a - b) | .mul => .ok (a * b)
  | .divS => Num.i32divS a b | .divU => Num.i32divU a b
  | .remS => Num.i32remS a b | .remU => Num.i32remU a b
  | .and => .ok (a &&& b) | .or => .ok (a ||| b) | .xor => .ok (a ^^^ b)
  | .shl => .ok (Num.i32shl a b) | .shrS => .ok (Num.i32shrS a b) | .shrU => .ok (Num.i32shrU a b)
  | .rotl => .ok (Num.i32rotl a b) | .rotr => .ok (Num.i32rotr a b)

def binop64 (op : IBinop) (a b : UInt64) : Except TrapCode UInt64 :=
  match op with
  | .add => .ok (a + b) | .sub => .ok (a - b) | .mul => .ok (a * b)
  | .divS => Num.i64divS a b | .divU => Num.i64divU a b
  | .remS => Num.i64remS a b | .remU => Num.i64remU a b
  | .and => .ok (a &&& b) | .or => .ok (a ||| b) | .xor => .ok (a ^^^ b)
  | .shl => .ok (Num.i64shl a b) | .shrS => .ok (Num.i64shrS a b) | .shrU => .ok (Num.i64shrU a b)
  | .rotl => .ok (Num.i64rotl a b) | .rotr => .ok (Num.i64rotr a b)

def relIdx : IRelop → Nat
  | .eq => 0 | .ne => 1 | .ltS => 2 | .ltU => 3 | .gtS => 4 | .gtU => 5
  | .leS => 6 | .leU => 7 | .geS => 8 | .geU => 9

def unop32 : IUnop → UInt32 → UInt32
  | .clz => Num.i32clz | .ctz => Num.i32ctz | .popcnt => Num.i32popcnt
def unop64 : IUnop → UInt64 → UInt64
  | .clz => Num.i64clz | .ctz => Num.i64ctz | .popcnt => Num.i64popcnt

/-- `memory.grow` (executor.rs:1099-1137, memory/mod.rs:197-248). -/
def memoryGrow (cx : Ctx H E) (c : Cfg H) : R H E (Cfg H) := do
  let (delta, c) ← popI32 c
  let failCode : Value := .i32 0xffff_ffff
  -- Pages::new(delta) fails above the 32-bit page maximum: push -1, no fuel.
  if delta.toNat > MAX_PAGES then return push c failCode
  withFuel c (cx.costs.forBytes (delta.toNat * PAGE_SIZE)) fun c => do
    let cur := c.st.pages
    if delta = 0 then return push c (.i32 cur.toUInt32)
    let maxP := c.st.memMax.getD MAX_PAGES
    let desired := cur + delta.toNat
    let desiredSz := (if desired ≤ MAX_PAGES then desired else MAX_PAGES) * PAGE_SIZE
    match cx.host.memoryGrowing (cur * PAGE_SIZE) desiredSz ((c.st.memMax.getD MAX_PAGES) * PAGE_SIZE) c.h with
    | .trap t h => .trap t (c.st, h)
    | .gasOut => .gasOut
    | .ok (allow, h) =>
      let c := { c with h }
      if !allow then return push c failCode
      if desired ≤ maxP && desired ≤ MAX_PAGES then
        let mem := c.st.mem.grow (delta.toNat * PAGE_SIZE)
        return push { c with st := { c.st with mem } } (.i32 cur.toUInt32)
      else return push c failCode

/-- One non-control instruction. -/
def simple (cx : Ctx H E) (i : Instr) (c : Cfg H) : R H E (Cfg H) :=
  match i with
  | .nop => .ok c
  | .drop => do let (_, c) ← pop1 c; pure c
  | .select => do
      let (cond, c) ← popI32 c
      let (b, c) ← pop1 c
      let (a, c) ← pop1 c
      pure (push c (if cond != 0 then a else b))
  | .localGet n => match c.locals[n]? with
      | some v => .ok (push c v) | none => trapAt c .UnreachableCodeReached
  | .localSet n => do
      let (v, c) ← pop1 c
      pure { c with locals := c.locals.set! n v }
  | .localTee n => match c.stk with
      | v :: _ => .ok { c with locals := c.locals.set! n v }
      | [] => trapAt c .UnreachableCodeReached
  | .globalGet n => match c.st.globals[n]? with
      | some v => .ok (push c v) | none => trapAt c .UnreachableCodeReached
  | .globalSet n => do
      let (v, c) ← pop1 c
      pure { c with st := { c.st with globals := c.st.globals.set! n v } }
  | .load op m => do
      let (a, c) ← popI32 c
      let ea ← lift c (Mem.effAddr c.st.mem a m.offset (Mem.loadBytes op))
      pure (push c (Mem.loadValue op (Mem.readLE c.st.mem ea (Mem.loadBytes op))))
  | .store op m => do
      let (v, c) ← pop1 c
      let (a, c) ← popI32 c
      let n := Mem.storeBytes op
      let ea ← lift c (Mem.effAddr c.st.mem a m.offset n)
      pure { c with st := { c.st with mem := Mem.writeLE c.st.mem ea n (Mem.storeRaw v) } }
  | .memorySize => .ok (push c (.i32 c.st.pages.toUInt32))
  | .memoryGrow => memoryGrow cx c
  | .memoryFill => do
      -- executor.rs:1139-1158
      let (n, c) ← popI32 c
      let (v, c) ← popI32 c
      let (d, c) ← popI32 c
      let n := bulkUsize n
      let d := bulkUsize d
      withFuel c (cx.costs.forBytes n) fun c =>
        if d + n > c.st.mem.size then trapAt c .MemoryOutOfBounds
        else .ok { c with st := { c.st with mem := Mem.writeBytes c.st.mem d n v.toUInt8 } }
  | .memoryCopy => do
      -- executor.rs:1160-1182
      let (n, c) ← popI32 c
      let (s, c) ← popI32 c
      let (d, c) ← popI32 c
      let n := bulkUsize n
      let s := bulkUsize s
      let d := bulkUsize d
      withFuel c (cx.costs.forBytes n) fun c =>
        if s + n > c.st.mem.size then trapAt c .MemoryOutOfBounds
        else if d + n > c.st.mem.size then trapAt c .MemoryOutOfBounds
        else .ok { c with st := { c.st with mem := Mem.copyWithin c.st.mem s d n } }
  | .memoryInit seg => do
      -- executor.rs:1184-1209
      let (n, c) ← popI32 c
      let (s, c) ← popI32 c
      let (d, c) ← popI32 c
      let n := bulkUsize n
      let s := bulkUsize s
      let d := bulkUsize d
      withFuel c (cx.costs.forBytes n) fun c =>
        let data := c.st.datas[seg]?.getD ByteArray.empty
        if d + n > c.st.mem.size then trapAt c .MemoryOutOfBounds
        else if s + n > data.size then trapAt c .MemoryOutOfBounds
        else .ok { c with st := { c.st with mem := Mem.copyFrom c.st.mem d data s n } }
  | .dataDrop seg => .ok { c with st := { c.st with datas := c.st.datas.set! seg ByteArray.empty } }
  | .tableCopy _ _ => do
      -- executor.rs:1300-1328, table/mod.rs:439-459 (single table: copy_within)
      let (n, c) ← popI32 c
      let (s, c) ← popI32 c
      let (d, c) ← popI32 c
      withFuel c (cx.costs.forLocals n.toNat) fun c =>   -- fuel_for_elements: len / 8
        let size := c.st.table.size
        if (max d.toNat s.toNat) + n.toNat ≥ 2^32 || (max d.toNat s.toNat) + n.toNat > size then
          trapAt c .TableOutOfBounds
        else .ok { c with st := { c.st with table := Mem.arrCopyWithin c.st.table s.toNat d.toNat n.toNat } }
  | .tableInit seg _ => do
      -- executor.rs:1330-1352
      let (n, c) ← popI32 c
      let (s, c) ← popI32 c
      let (d, c) ← popI32 c
      withFuel c (cx.costs.forLocals n.toNat) fun c =>
        let elem := c.st.elems[seg]?.getD #[]
        if d.toNat + n.toNat > c.st.table.size then trapAt c .TableOutOfBounds
        else if s.toNat + n.toNat > elem.size then trapAt c .TableOutOfBounds
        else .ok { c with st := { c.st with table := Mem.arrCopyFrom c.st.table d.toNat elem s.toNat n.toNat } }
  | .elemDrop seg => .ok { c with st := { c.st with elems := c.st.elems.set! seg #[] } }
  | .i32Const v => .ok (push c (.i32 v))
  | .i64Const v => .ok (push c (.i64 v))
  | .eqz .w32 => do let (a, c) ← popI32 c; pure (push c (.i32 (Num.b32 (a == 0))))
  | .eqz .w64 => do let (a, c) ← popI64 c; pure (push c (.i32 (Num.b32 (a == 0))))
  | .relop .w32 op => do
      let (b, c) ← popI32 c; let (a, c) ← popI32 c
      pure (push c (.i32 (Num.i32rel (relIdx op) a b)))
  | .relop .w64 op => do
      let (b, c) ← popI64 c; let (a, c) ← popI64 c
      pure (push c (.i32 (Num.i64rel (relIdx op) a b)))
  | .unop .w32 op => do let (a, c) ← popI32 c; pure (push c (.i32 (unop32 op a)))
  | .unop .w64 op => do let (a, c) ← popI64 c; pure (push c (.i64 (unop64 op a)))
  | .binop .w32 op => do
      let (b, c) ← popI32 c; let (a, c) ← popI32 c
      let r ← lift c (binop32 op a b)
      pure (push c (.i32 r))
  | .binop .w64 op => do
      let (b, c) ← popI64 c; let (a, c) ← popI64 c
      let r ← lift c (binop64 op a b)
      pure (push c (.i64 r))
  | .i32WrapI64 => do let (a, c) ← popI64 c; pure (push c (.i32 (Num.wrap64 a)))
  | .i64ExtendI32S => do let (a, c) ← popI32 c; pure (push c (.i64 (Num.extendS a)))
  | .i64ExtendI32U => do let (a, c) ← popI32 c; pure (push c (.i64 (Num.extendU a)))
  | .extend8S .w32 => do let (a, c) ← popI32 c; pure (push c (.i32 (Num.sext8_32 a)))
  | .extend16S .w32 => do let (a, c) ← popI32 c; pure (push c (.i32 (Num.sext16_32 a)))
  | .extend8S .w64 => do let (a, c) ← popI64 c; pure (push c (.i64 (Num.sext8_64 a)))
  | .extend16S .w64 => do let (a, c) ← popI64 c; pure (push c (.i64 (Num.sext16_64 a)))
  | .i64Extend32S => do let (a, c) ← popI64 c; pure (push c (.i64 (Num.sext32_64 a)))
  -- control instructions never reach `simple`
  | _ => trapAt c .UnreachableCodeReached

/-- Keep the top `k` values of `s'` above the block-entry stack `s`. -/
@[inline] def restore (k : Nat) (s' s : List Value) : List Value := s'.take k ++ s

/-- Value-stack pointer of a frame (stack/values: params+locals then operands). -/
@[inline] def sp (fi : FrameInfo) (c : Cfg H) : Nat := fi.base + fi.nLocals + c.stk.length

mutual

def execList (cx : Ctx H E) (fi : FrameInfo) : Nat → List CInstr → Cfg H → R H E (Flow × Cfg H)
  | 0, _, _ => .gasOut
  | _ + 1, [], c => .ok (.next, c)
  | g + 1, i :: is, c =>
    match execInstr cx fi g i c with
    | .ok (.next, c') => execList cx fi g is c'
    | .ok (fl, c') => .ok (fl, c')
    | .trap t s => .trap t s
    | .gasOut => .gasOut

def execInstr (cx : Ctx H E) (fi : FrameInfo) : Nat → CInstr → Cfg H → R H E (Flow × Cfg H)
  | 0, _, _ => .gasOut
  | _ + 1, .simple i, c => (simple cx i c).bind fun c => .ok (.next, c)
  | _ + 1, .unreachable, c => trapAt c .UnreachableCodeReached
  | g + 1, .block k body, c =>
    match execList cx fi g body c with
    | .ok (.next, c') | .ok (.br 0, c') => .ok (.next, { c' with stk := restore k c'.stk c.stk })
    | .ok (.br (n + 1), c') => .ok (.br n, c')
    | .ok (.ret, c') => .ok (.ret, c')
    | .trap t s => .trap t s
    | .gasOut => .gasOut
  | g + 1, .loop k fuel body, c =>
    match chargeFuel c fuel with
    | .trap t s => .trap t s
    | .gasOut => .gasOut
    | .ok cf =>
      match execList cx fi g body cf with
      | .ok (.next, c') => .ok (.next, { c' with stk := restore k c'.stk c.stk })
      | .ok (.br 0, c') =>
        -- branch to the loop header: params (none) kept, re-enter (charges fuel again)
        execInstr cx fi g (.loop k fuel body) { c' with stk := c.stk }
      | .ok (.br (n + 1), c') => .ok (.br n, c')
      | .ok (.ret, c') => .ok (.ret, c')
      | .trap t s => .trap t s
      | .gasOut => .gasOut
  | g + 1, .if_ k fThen fElse thn els, c =>
    match popI32 c with
    | .trap t s => .trap t s
    | .gasOut => .gasOut
    | .ok (cond, c0) =>
      let arm : Option (Nat × List CInstr) :=
        if cond != 0 then some (fThen, thn) else fElse.map fun f => (f, els)
      match arm with
      | none => .ok (.next, c0)
      | some (f, body) =>
        match chargeFuel c0 f with
        | .trap t s => .trap t s
        | .gasOut => .gasOut
        | .ok cf =>
          match execList cx fi g body cf with
          | .ok (.next, c') | .ok (.br 0, c') => .ok (.next, { c' with stk := restore k c'.stk c0.stk })
          | .ok (.br (n + 1), c') => .ok (.br n, c')
          | .ok (.ret, c') => .ok (.ret, c')
          | .trap t s => .trap t s
          | .gasOut => .gasOut
  | _ + 1, .br l, c => .ok (.br l, c)
  | _ + 1, .brIf l, c =>
    match popI32 c with
    | .ok (v, c') => .ok (if v != 0 then .br l else .next, c')
    | .trap t s => .trap t s
    | .gasOut => .gasOut
  | _ + 1, .brTable ls d, c =>
    match popI32 c with
    | .ok (v, c') => .ok (.br (ls.getD v.toNat d), c')   -- executor.rs:945-953 (index clamped to default)
    | .trap t s => .trap t s
    | .gasOut => .gasOut
  | _ + 1, .return_, c => .ok (.ret, c)
  | g + 1, .call f, c => callFunc cx fi g f c
  | g + 1, .callIndirect t _, c =>
    -- executor.rs:807-835
    match popI32 c with
    | .trap t s => .trap t s
    | .gasOut => .gasOut
    | .ok (idx, c') =>
      match c'.st.table[idx.toNat]? with
      | none => trapAt c' .TableOutOfBounds
      | some none => trapAt c' .IndirectCallToNull
      | some (some f) =>
        if cx.funcTypes[f]? != cx.types[t]? then trapAt c' .BadSignature
        else callFunc cx fi g f c'

/-- Call function index `f` from a frame. -/
def callFunc (cx : Ctx H E) (fi : FrameInfo) : Nat → Nat → Cfg H → R H E (Flow × Cfg H)
  | 0, _, _ => .gasOut
  | g + 1, f, c =>
    let ft := cx.funcTypes[f]?.getD default
    let np := ft.params.length
    let nr := ft.results.length
    -- call_stack.push of the caller frame (frames.rs:74-80)
    if fi.depth = MAX_RECURSION_DEPTH then trapAt c .StackOverflow else
    let args := (c.stk.take np).reverse
    let rest := c.stk.drop np
    let spNow := sp fi c
    if f < cx.nImports then
      -- host function (stack/mod.rs:174-206): reserve max(inputs, outputs)
      if spNow + max np nr > MAX_VALUE_STACK then trapAt c .StackOverflow else
      match cx.host.call g f args c.st c.h with
      | .ok (res, st, h) => .ok (.next, { c with stk := res.reverse ++ rest, st, h })
      | .trap t s => .trap t s
      | .gasOut => .gasOut
    else
      match cx.funcs[f - cx.nImports]? with
      | none => trapAt c .UnreachableCodeReached
      | some cf =>
        -- prepare_wasm_call: reserve(max_stack_height) then zero locals (values/mod.rs:182-188)
        if spNow + cf.maxStackHeight > MAX_VALUE_STACK then trapAt c .StackOverflow else
        let locals := (args ++ cf.locals.map Value.zero).toArray
        let fi' : FrameInfo := { base := spNow - np, nLocals := locals.size, depth := fi.depth + 1 }
        let c0 : Cfg H := { stk := [], locals, st := c.st, h := c.h }
        match chargeFuel c0 cf.entryFuel with
        | .trap t s => .trap t s
        | .gasOut => .gasOut
        | .ok c1 =>
          match execList cx fi' g cf.body c1 with
          | .ok (_, c') => .ok (.next, { c with stk := (c'.stk.take nr) ++ rest, st := c'.st, h := c'.h })
          | .trap t s => .trap t s
          | .gasOut => .gasOut
end

/-- Invoke function `f` as the root of an execution (engine/mod.rs:639-670):
    reserve params, prepare_wasm_call (reserve + zero locals), root frame pushed
    without the depth check. Returns results in order. -/
def invoke (cx : Ctx H E) (g : Nat) (f : Nat) (args : List Value) (st : Store) (h : H) :
    Res E (Store × H) (List Value × Store × H) :=
  let ft := cx.funcTypes[f]?.getD default
  if f < cx.nImports then cx.host.call g f args st h
  else
  match cx.funcs[f - cx.nImports]? with
  | none => .trap (.code .UnreachableCodeReached) (st, h)
  | some cf =>
    if args.length > MAX_VALUE_STACK then .trap (.code .StackOverflow) (st, h) else
    if args.length + cf.maxStackHeight > MAX_VALUE_STACK then .trap (.code .StackOverflow) (st, h) else
    let locals := (args ++ cf.locals.map Value.zero).toArray
    let fi : FrameInfo := { base := 0, nLocals := locals.size, depth := 1 }
    let c0 : Cfg H := { stk := [], locals, st, h }
    match chargeFuel c0 cf.entryFuel with
    | .trap t s => .trap t s
    | .gasOut => .gasOut
    | .ok c1 =>
      match execList cx fi g cf.body c1 with
      | .ok (_, c') => .ok ((c'.stk.take ft.results.length).reverse, c'.st, c'.h)
      | .trap t s => .trap t s
      | .gasOut => .gasOut

end Exec
end Wasm
