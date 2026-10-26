/-
Binary decoder for the Soroban Wasm subset.

Reference behaviour: wasmparser-nostd 0.100.2 (the parser wasmi 29.0.0 / Soroban
uses), src under vendor/crates/wasmparser-nostd-0.100.2/src:
  - LEB128 rules: binary_reader.rs (`read_var_u32`, `read_var_s32`, `read_var_s64`,
    `read_var_s33`).
  - Operator encodings: binary_reader.rs (`read_operator`, `read_0xfc_operator`).
Anything outside the accepted feature set is a decode error; a module that decodes
here is then subject to the separate validation checks.
-/
import SorobanLean.Wasm.Syntax

namespace Wasm.Decode

/-- Parser over the remaining input as a list (O(1) per byte, also under kernel
    reduction) and the current offset (only used in error messages). -/
abbrev P (α : Type) := List UInt8 → Nat → Except String (α × List UInt8 × Nat)

instance : Monad P where
  pure a := fun r p => .ok (a, r, p)
  bind m f := fun r p => match m r p with
    | .ok (a, r', p') => f a r' p'
    | .error e => .error e

def fail {α} (msg : String) : P α := fun _ p => .error s!"{msg} at offset {p}"

def pos : P Nat := fun r p => .ok (p, r, p)

def eof : P Bool := fun r p => .ok (r.isEmpty, r, p)

def u8 : P UInt8 := fun r p =>
  match r with
  | x :: r' => .ok (x, r', p + 1)
  | [] => .error s!"unexpected end at offset {p}"

/-- Look at the next byte without consuming it. -/
def peek : P UInt8 := fun r p =>
  match r with
  | x :: _ => .ok (x, r, p)
  | [] => .error s!"unexpected end at offset {p}"

def bytes (n : Nat) : P ByteArray := fun r p =>
  let t := r.take n
  if t.length = n then .ok (⟨t.toArray⟩, r.drop n, p + n) else .error s!"unexpected end at offset {p}"

/-- The rest of the input. -/
def rest : P ByteArray := fun r p => .ok (⟨r.toArray⟩, [], p + r.length)

/-- Run `m` on exactly the next `n` bytes (a sized sub-section): `m` must consume all
    of them. -/
def sub {α} (n : Nat) (m : P α) : P α := fun r p =>
  let t := r.take n
  if t.length = n then
    match m t p with
    | .ok (a, r', _) => if r'.isEmpty then .ok (a, r.drop n, p + n) else .error s!"section size mismatch at offset {p}"
    | .error e => .error e
  else .error s!"unexpected end at offset {p}"

/-- Lean fuel for instruction decoding: twice the remaining length (+2). -/
def withRemainingFuel {α} (m : Nat → P α) : P α := fun r p => m (2 * r.length + 2) r p

/-- Unsigned LEB128 for `bits` = 32 (src: binary_reader.rs `read_var_u32`):
    at most 5 bytes; in the 5th byte only the low 4 bits may be set. -/
def varU32 : P Nat := go 5 0 0
where
  /-- `fu` bounds the loop: `shift` reaches 28 after 4 bytes and the 5th byte always
      returns or fails, so `fu = 5` is never exhausted. -/
  go : Nat → Nat → Nat → P Nat
  | 0, _, _ => fail "invalid var_u32: integer representation too long"
  | fu + 1, acc, shift => do
    let byte ← u8
    let acc := acc ||| ((byte.toNat &&& 0x7f) <<< shift)
    if shift == 28 && byte.toNat >>> 4 != 0 then
      fail "invalid var_u32: integer too large"
    else if byte &&& 0x80 == 0 then pure acc
    else if shift == 28 then fail "invalid var_u32: integer representation too long"
    else go fu acc (shift + 7)

/-- Signed LEB128 producing an `Int` in `[-2^(bits-1), 2^(bits-1))`
    (src: binary_reader.rs `read_var_s32`/`read_var_s64`/`read_var_s33`): at most
    ceil(bits/7) bytes, and the unused high bits of the last byte must be a sign
    extension of the value. -/
def varS (bits : Nat) : P Int := go (bits / 7 + 1) 0 0
where
  /-- Each byte adds 7 to `shift` and the loop stops once `shift + 7 ≥ bits`, so at
      most `⌈bits/7⌉ ≤ bits/7 + 1` iterations happen. -/
  go : Nat → Nat → Nat → P Int
  | 0, _, _ => fail s!"invalid var_s{bits}: integer representation too long"
  | fu + 1, acc, shift => do
    let byte ← u8
    let acc := acc ||| ((byte.toNat &&& 0x7f) <<< shift)
    let shift' := shift + 7
    if byte &&& 0x80 == 0 then
      -- final byte: check unused bits are a sign extension
      if shift' ≥ bits then
        -- number of value bits held by this byte
        let used := bits - shift
        let signAndUnused := byte.toNat >>> (used - 1)  -- sign bit and above (7 bit byte)
        let ok := signAndUnused == 0 || signAndUnused == (0x7f >>> (used - 1))
        if !ok then fail s!"invalid var_s{bits}: integer too large" else pure ()
      let total := min shift' bits
      let v : Int := if (acc >>> (total - 1)) &&& 1 == 1 then (acc : Int) - (1 <<< total : Nat) else acc
      -- normalize to bits width if the encoding used more than `bits` value bits
      let m : Int := (1 <<< bits : Nat)
      let half : Int := (1 <<< (bits - 1) : Nat)
      let v := ((v % m) + m) % m
      pure (if v ≥ half then v - m else v)
    else if shift' ≥ bits then fail s!"invalid var_s{bits}: integer representation too long"
    else go fu acc shift'

def varS32 : P Int := varS 32
def varS64 : P Int := varS 64
def varS33 : P Int := varS 33

def vec {α} (elem : P α) : P (List α) := do
  let n ← varU32
  let rec loop : Nat → List α → P (List α)
    | 0, acc => pure acc.reverse
    | k+1, acc => do let a ← elem; loop k (a :: acc)
  loop n []

/-- UTF-8 name (src: binary_reader.rs `read_string`, validates UTF-8). -/
def name : P String := do
  let n ← varU32
  let bs ← bytes n
  match String.fromUTF8? bs with
  | some s => pure s
  | none => fail "invalid UTF-8 encoding"

def valType : P ValType := do
  match (← u8).toNat with
  | 0x7f => pure .i32
  | 0x7e => pure .i64
  | 0x7d | 0x7c => fail "floating-point support is disabled"
  | 0x7b => fail "SIMD support is not enabled"
  | 0x70 | 0x6f => fail "reference types support is not enabled"
  | b => fail s!"invalid value type {b}"

def refType : P RefType := do
  match (← u8).toNat with
  | 0x70 => pure .funcref
  -- externref needs reference types (src: validator/core.rs:180-182, validator.rs:255-264)
  | 0x6f => fail "reference types support is not enabled"
  | b => fail s!"invalid reference type {b}"

def limits : P Limits := do
  match (← u8).toNat with
  | 0x00 => pure ⟨← varU32, none⟩
  | 0x01 => do let mn ← varU32; let mx ← varU32; pure ⟨mn, some mx⟩
  | b => fail s!"invalid limits flags {b}"

def globalType : P GlobalType := do
  let t ← valType
  match (← u8).toNat with
  | 0 => pure ⟨t, false⟩
  | 1 => pure ⟨t, true⟩
  | _ => fail "malformed mutability"

def funcType : P FuncType := do
  match (← u8).toNat with
  | 0x60 => do
      let ps ← vec valType
      let rs ← vec valType
      -- src: validator/core.rs:481-486
      if rs.length > 1 then fail "func type returns multiple values but the multi-value feature is not enabled"
      else pure ⟨ps, rs⟩
  | _ => fail "invalid function type form"

def blockType : P BlockType := do
  let b ← peek
  if b == 0x40 then do let _ ← u8; pure .empty
  else if b == 0x7f then do let _ ← u8; pure (.val .i32)
  else if b == 0x7e then do let _ ← u8; pure (.val .i64)
  else if b == 0x7d || b == 0x7c then fail "floating-point support is disabled"
  else do
    let i ← varS33
    if i < 0 then fail "invalid block type"
    -- src: validator/operators.rs:595-602
    else fail "blocks, loops, and ifs may only produce a resulttype when multi-value is not enabled"

def memArg : P MemArg := do
  let a ← varU32
  let o ← varU32
  pure ⟨a, o⟩

/-- A reserved zero memory/table index (bulk-memory encodings accept any LEB
    encoding of 0, src: validator/operators.rs `check_memory_index`). -/
def zeroByte (what : String) : P Unit := do
  let b ← varU32
  if b != 0 then fail s!"{what}: multi-memory / reference types not enabled" else pure ()

/-- `read_first_byte_and_var_u32` + the validator's "zero byte expected" rule for
    `call_indirect` (reference types off) and `memory.size/grow` (multi-memory off):
    the *first byte* of the encoding must be 0x00 (src: binary_reader.rs:250, :781-785,
    :834-841; validator/operators.rs:1171-1176, :1395-1406). -/
def firstByteZero (msg : String) : P Unit := do
  let b0 ← peek
  let _ ← varU32
  if b0 != 0 then fail msg else pure ()

def toU32 (i : Int) : UInt32 := UInt32.ofInt i
def toU64 (i : Int) : UInt64 := UInt64.ofInt i

/-- Terminator of an instruction sequence. -/
inductive Term where | end_ | else_
  deriving DecidableEq

mutual
/-- Decode instructions until `end` or `else`. `fu` is Lean fuel, decreased on every
    call edge (`instrsGo → instr → instrsGo`) so that the recursion is structural and
    kernel-reducible. Every `instrsGo` step reads at least one byte, so twice the
    remaining input length (+2) is never exhausted. -/
def instrsGo : Nat → List Instr → P (List Instr × Term)
  | 0, _ => fail "decoder fuel exhausted"
  | fu + 1, acc => do
    let op ← u8
    match op.toNat with
    | 0x0b => pure (acc.reverse, .end_)
    | 0x05 => pure (acc.reverse, .else_)
    | _ => do let i ← instr fu op; instrsGo fu (i :: acc)

def instr : Nat → UInt8 → P Instr
  | 0, _ => fail "decoder fuel exhausted"
  | fu + 1, op => do
      match op.toNat with
      | 0x00 => pure .unreachable
      | 0x01 => pure .nop
      | 0x02 => do
          let bt ← blockType
          let (body, t) ← instrsGo fu []
          if t != .end_ then fail "else outside if" else pure (.block bt body)
      | 0x03 => do
          let bt ← blockType
          let (body, t) ← instrsGo fu []
          if t != .end_ then fail "else outside if" else pure (.loop bt body)
      | 0x04 => do
          let bt ← blockType
          let (thn, t) ← instrsGo fu []
          if t == .else_ then do
            let (els, t2) ← instrsGo fu []
            if t2 != .end_ then fail "duplicate else" else pure (.if_ bt thn els true)
          else pure (.if_ bt thn [] false)
      | 0x0c => return .br (← varU32)
      | 0x0d => return .brIf (← varU32)
      | 0x0e => do let ls ← vec varU32; let d ← varU32; pure (.brTable ls d)
      | 0x0f => pure .return_
      | 0x10 => return .call (← varU32)
      | 0x11 => do
          let t ← varU32
          firstByteZero "reference-types not enabled: zero byte expected"
          pure (.callIndirect t 0)
      | 0x1a => pure .drop
      | 0x1b => pure .select
      | 0x1c => fail "reference types support is not enabled"
      | 0x20 => return .localGet (← varU32)
      | 0x21 => return .localSet (← varU32)
      | 0x22 => return .localTee (← varU32)
      | 0x23 => return .globalGet (← varU32)
      | 0x24 => return .globalSet (← varU32)
      | 0x25 | 0x26 => fail "reference types support is not enabled"
      | 0x28 => return .load .i32 (← memArg)
      | 0x29 => return .load .i64 (← memArg)
      | 0x2a | 0x2b => fail "floating-point support is disabled"
      | 0x2c => return .load .i32_8s (← memArg)
      | 0x2d => return .load .i32_8u (← memArg)
      | 0x2e => return .load .i32_16s (← memArg)
      | 0x2f => return .load .i32_16u (← memArg)
      | 0x30 => return .load .i64_8s (← memArg)
      | 0x31 => return .load .i64_8u (← memArg)
      | 0x32 => return .load .i64_16s (← memArg)
      | 0x33 => return .load .i64_16u (← memArg)
      | 0x34 => return .load .i64_32s (← memArg)
      | 0x35 => return .load .i64_32u (← memArg)
      | 0x36 => return .store .i32 (← memArg)
      | 0x37 => return .store .i64 (← memArg)
      | 0x38 | 0x39 => fail "floating-point support is disabled"
      | 0x3a => return .store .i32_8 (← memArg)
      | 0x3b => return .store .i32_16 (← memArg)
      | 0x3c => return .store .i64_8 (← memArg)
      | 0x3d => return .store .i64_16 (← memArg)
      | 0x3e => return .store .i64_32 (← memArg)
      | 0x3f => do firstByteZero "multi-memory not enabled: zero byte expected"; pure .memorySize
      | 0x40 => do firstByteZero "multi-memory not enabled: zero byte expected"; pure .memoryGrow
      | 0x41 => return .i32Const (toU32 (← varS32))
      | 0x42 => return .i64Const (toU64 (← varS64))
      | 0x43 | 0x44 => fail "floating-point support is disabled"
      | 0x45 => pure (.eqz .w32)
      | 0x46 => pure (.relop .w32 .eq) | 0x47 => pure (.relop .w32 .ne)
      | 0x48 => pure (.relop .w32 .ltS) | 0x49 => pure (.relop .w32 .ltU)
      | 0x4a => pure (.relop .w32 .gtS) | 0x4b => pure (.relop .w32 .gtU)
      | 0x4c => pure (.relop .w32 .leS) | 0x4d => pure (.relop .w32 .leU)
      | 0x4e => pure (.relop .w32 .geS) | 0x4f => pure (.relop .w32 .geU)
      | 0x50 => pure (.eqz .w64)
      | 0x51 => pure (.relop .w64 .eq) | 0x52 => pure (.relop .w64 .ne)
      | 0x53 => pure (.relop .w64 .ltS) | 0x54 => pure (.relop .w64 .ltU)
      | 0x55 => pure (.relop .w64 .gtS) | 0x56 => pure (.relop .w64 .gtU)
      | 0x57 => pure (.relop .w64 .leS) | 0x58 => pure (.relop .w64 .leU)
      | 0x59 => pure (.relop .w64 .geS) | 0x5a => pure (.relop .w64 .geU)
      | 0x67 => pure (.unop .w32 .clz) | 0x68 => pure (.unop .w32 .ctz) | 0x69 => pure (.unop .w32 .popcnt)
      | 0x6a => pure (.binop .w32 .add) | 0x6b => pure (.binop .w32 .sub) | 0x6c => pure (.binop .w32 .mul)
      | 0x6d => pure (.binop .w32 .divS) | 0x6e => pure (.binop .w32 .divU)
      | 0x6f => pure (.binop .w32 .remS) | 0x70 => pure (.binop .w32 .remU)
      | 0x71 => pure (.binop .w32 .and) | 0x72 => pure (.binop .w32 .or) | 0x73 => pure (.binop .w32 .xor)
      | 0x74 => pure (.binop .w32 .shl) | 0x75 => pure (.binop .w32 .shrS) | 0x76 => pure (.binop .w32 .shrU)
      | 0x77 => pure (.binop .w32 .rotl) | 0x78 => pure (.binop .w32 .rotr)
      | 0x79 => pure (.unop .w64 .clz) | 0x7a => pure (.unop .w64 .ctz) | 0x7b => pure (.unop .w64 .popcnt)
      | 0x7c => pure (.binop .w64 .add) | 0x7d => pure (.binop .w64 .sub) | 0x7e => pure (.binop .w64 .mul)
      | 0x7f => pure (.binop .w64 .divS) | 0x80 => pure (.binop .w64 .divU)
      | 0x81 => pure (.binop .w64 .remS) | 0x82 => pure (.binop .w64 .remU)
      | 0x83 => pure (.binop .w64 .and) | 0x84 => pure (.binop .w64 .or) | 0x85 => pure (.binop .w64 .xor)
      | 0x86 => pure (.binop .w64 .shl) | 0x87 => pure (.binop .w64 .shrS) | 0x88 => pure (.binop .w64 .shrU)
      | 0x89 => pure (.binop .w64 .rotl) | 0x8a => pure (.binop .w64 .rotr)
      | 0xa7 => pure .i32WrapI64
      | 0xac => pure .i64ExtendI32S
      | 0xad => pure .i64ExtendI32U
      | 0xc0 => pure (.extend8S .w32) | 0xc1 => pure (.extend16S .w32)
      | 0xc2 => pure (.extend8S .w64) | 0xc3 => pure (.extend16S .w64) | 0xc4 => pure .i64Extend32S
      | 0xd0 | 0xd1 | 0xd2 => fail "reference types support is not enabled"
      | 0xfc => do
          match ← varU32 with
          | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 => fail "floating-point support is disabled"
          | 8 => do let s ← varU32; zeroByte "memory.init"; pure (.memoryInit s)
          | 9 => return .dataDrop (← varU32)
          | 10 => do zeroByte "memory.copy"; zeroByte "memory.copy"; pure .memoryCopy
          | 11 => do zeroByte "memory.fill"; pure .memoryFill
          | 12 => do let s ← varU32; let t ← varU32; pure (.tableInit s t)
          | 13 => return .elemDrop (← varU32)
          | 14 => do let d ← varU32; let s ← varU32; pure (.tableCopy d s)
          | 15 | 16 | 17 => fail "reference types support is not enabled"
          | n => fail s!"unknown 0xfc subopcode {n}"
      | 0xfd => fail "SIMD support is not enabled"
      | n =>
          if (0x5b ≤ n && n ≤ 0x66) || (0x8b ≤ n && n ≤ 0xa6) || (0xa8 ≤ n && n ≤ 0xab) || (0xae ≤ n && n ≤ 0xbf)
          then fail "floating-point support is disabled"
          else fail s!"illegal opcode {n}"
end

/-- A constant expression terminated by `end`. -/
def constExpr : P ConstExpr := do
  let op ← u8
  let e ← match op.toNat with
    | 0x41 => do pure (ConstExpr.i32Const (toU32 (← varS32)))
    | 0x42 => do pure (ConstExpr.i64Const (toU64 (← varS64)))
    | 0x23 => do pure (ConstExpr.globalGet (← varU32))
    -- `ref.func` / `ref.null` need reference types (const exprs are checked by the
    -- operator validator, src: validator/core.rs:236-260, validator.rs:263)
    | 0xd2 | 0xd0 => fail "reference types support is not enabled"
    | 0x43 | 0x44 => fail "floating-point support is disabled"
    | n => fail s!"constant expression required (opcode {n})"
  let e2 ← u8
  if e2 != 0x0b then fail "constant expression required" else pure e

def import_ : P Import := do
  let m ← name
  let n ← name
  let d ← match (← u8).toNat with
    | 0 => do pure (ImportDesc.func (← varU32))
    | 1 => do let t ← refType; let l ← limits; pure (ImportDesc.table ⟨t, l⟩)
    | 2 => do pure (ImportDesc.mem (← limits))
    | 3 => do pure (ImportDesc.global (← globalType))
    | k => fail s!"invalid import kind {k}"
  pure ⟨m, n, d⟩

def export_ : P Export := do
  let n ← name
  let d ← match (← u8).toNat with
    | 0 => do pure (ExportDesc.func (← varU32))
    | 1 => do pure (ExportDesc.table (← varU32))
    | 2 => do pure (ExportDesc.mem (← varU32))
    | 3 => do pure (ExportDesc.global (← varU32))
    | k => fail s!"invalid export kind {k}"
  pure ⟨n, d⟩

/-- Element segments, all 8 encodings of the bulk-memory proposal. -/
def elem : P Elem := do
  let flags ← varU32
  let funcIdxs : P (List ConstExpr) := do
    let fs ← vec varU32; pure (fs.map ConstExpr.refFunc)
  let elemKind : P RefType := do
    match (← u8).toNat with
    | 0 => pure .funcref
    | k => fail s!"invalid element kind {k}"
  match flags with
  | 0 => do let o ← constExpr; let is ← funcIdxs; pure ⟨.funcref, is, .active 0 o⟩
  | 1 => do let _ ← elemKind; let is ← funcIdxs; pure ⟨.funcref, is, .passive⟩
  | 2 => do let t ← varU32; let o ← constExpr; let _ ← elemKind; let is ← funcIdxs; pure ⟨.funcref, is, .active t o⟩
  | 3 => do let _ ← elemKind; let is ← funcIdxs; pure ⟨.funcref, is, .declarative⟩
  | 4 => do let o ← constExpr; let is ← vec constExpr; pure ⟨.funcref, is, .active 0 o⟩
  | 5 => do let rt ← refType; let is ← vec constExpr; pure ⟨rt, is, .passive⟩
  | 6 => do let t ← varU32; let o ← constExpr; let rt ← refType; let is ← vec constExpr; pure ⟨rt, is, .active t o⟩
  | 7 => do let rt ← refType; let is ← vec constExpr; pure ⟨rt, is, .declarative⟩
  | f => fail s!"invalid element segment flags {f}"

def data : P Data := do
  match ← varU32 with
  | 0 => do let o ← constExpr; let n ← varU32; let b ← bytes n; pure ⟨b, .active 0 o⟩
  | 1 => do let n ← varU32; let b ← bytes n; pure ⟨b, .passive⟩
  | 2 => do let m ← varU32; let o ← constExpr; let n ← varU32; let b ← bytes n; pure ⟨b, .active m o⟩
  | f => fail s!"invalid data segment flags {f}"

/-- One code entry: locals then body (sizes are checked by `sub`). -/
def code : P (List (Nat × ValType) × List Instr) := do
  let size ← varU32
  sub size do
    let groups ← vec (do let n ← varU32; let t ← valType; pure (n, t))
    -- src: validator/operators.rs:3186-3191 (MAX_WASM_FUNCTION_LOCALS = 50000,
    -- limits.rs); params are added to this count by `Validate`.
    if (groups.map (·.1)).sum > 50000 then fail "too many locals" else pure ()
    let (body, t) ← withRemainingFuel fun fu => instrsGo fu []
    if t != .end_ then fail "else outside if" else pure (groups, body)

mutual
def dataRefsOk (dc : Option Nat) : List Instr → Bool
  | [] => true
  | i :: is => dataRefOk dc i && dataRefsOk dc is
def dataRefOk (dc : Option Nat) : Instr → Bool
  | .memoryInit s | .dataDrop s => match dc with | some n => s < n | none => false
  | .block _ b | .loop _ b => dataRefsOk dc b
  | .if_ _ t e _ => dataRefsOk dc t && dataRefsOk dc e
  | _ => true
end

/-- Decode a whole module. Section ordering: non-custom sections must appear in
    increasing id order (datacount=12 sits between element=9 and code=10), each
    at most once. -/
def module : P Module := do
  let magic ← bytes 4
  if magic.toList != [0x00, 0x61, 0x73, 0x6d] then fail "magic header not detected" else pure ()
  let ver ← bytes 4
  if ver.toList != [0x01, 0x00, 0x00, 0x00] then fail "unknown binary version" else pure ()
  -- order rank of each section id (spec 5.5.2: datacount comes before code)
  let rank : Nat → Nat := fun id => match id with
    | 12 => 95 | 10 => 100 | 11 => 110 | n => n * 10
  let rec loop (m : Module) (lastRank : Nat) (funcTys : Option (List Nat)) (fuel : Nat) : P Module := do
    match fuel with
    | 0 => fail "too many sections"
    | fuel + 1 =>
    if ← eof then
      match funcTys with
      | some ts => if ts.length != m.funcs.size then fail "function and code section have inconsistent lengths" else pure ()
      | none => pure ()
      -- src: validator/core.rs:96-104
      match m.dataCount with
      | some n => if n != m.datas.size then fail "data count and data section have inconsistent lengths" else pure ()
      | none => pure ()
      -- src: validator/core.rs:515-523 (max 1 table w/o reference types, 1 memory w/o multi-memory)
      let nTables := m.tables.size + (m.imports.filter fun i => match i.desc with | .table _ => true | _ => false).size
      let nMems := m.mems.size + (m.imports.filter fun i => match i.desc with | .mem _ => true | _ => false).size
      if nTables > 1 then fail "multiple tables" else pure ()
      if nMems > 1 then fail "multiple memories" else pure ()
      -- src: validator/operators.rs:2975-2996 (memory.init / data.drop need a data count)
      if !(m.funcs.all fun f => dataRefsOk m.dataCount f.body) then fail "data count section required / unknown data segment" else pure ()
      pure m
    else
      let id := (← u8).toNat
      let size ← varU32
      if id == 0 then
        let m ← sub size do
          let n ← name
          let p ← pos
          let rest ← rest
          let _ := p
          pure { m with customs := m.customs.push (n, rest) }
        loop m lastRank funcTys fuel
      else
        if id > 12 then fail s!"malformed section id {id}" else pure ()
        if rank id ≤ lastRank then fail "section out of order" else pure ()
        let (m, funcTys) ← sub size do
          match id with
          | 1 => do pure ({ m with types := (← vec funcType).toArray }, funcTys)
          | 2 => do pure ({ m with imports := (← vec import_).toArray }, funcTys)
          | 3 => do pure (m, some (← vec varU32))
          | 4 => do pure ({ m with tables := (← vec (do let t ← refType; let l ← limits; pure (⟨t, l⟩ : TableType))).toArray }, funcTys)
          | 5 => do pure ({ m with mems := (← vec limits).toArray }, funcTys)
          | 6 => do pure ({ m with globals := (← vec (do let t ← globalType; let e ← constExpr; pure (⟨t, e⟩ : Global))).toArray }, funcTys)
          | 7 => do pure ({ m with exports := (← vec export_).toArray }, funcTys)
          | 8 => do pure ({ m with start := some (← varU32) }, funcTys)
          | 9 => do pure ({ m with elems := (← vec elem).toArray }, funcTys)
          | 10 => do
              let cs ← vec code
              let tys := funcTys.getD []
              if tys.length != cs.length then fail "function and code section have inconsistent lengths" else pure ()
              let fs := (tys.zip cs).map fun (ti, (groups, body)) =>
                ({ typeIdx := ti, locals := groups.flatMap (fun (n, t) => List.replicate n t),
                   body := body, localGroups := groups } : Func)
              pure ({ m with funcs := fs.toArray }, funcTys)
          | 11 => do pure ({ m with datas := (← vec data).toArray }, funcTys)
          | 12 => do pure ({ m with dataCount := some (← varU32) }, funcTys)
          | _ => fail "unreachable"
        loop m (rank id) funcTys fuel
  loop {} 0 none 100000

def decodeModule (b : ByteArray) : Except String Module :=
  (module b.data.toList 0).map (·.1)

end Wasm.Decode
