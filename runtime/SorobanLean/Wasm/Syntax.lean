/-
Abstract syntax of the Wasm subset Soroban accepts.

Feature set (src: vendor/rs-soroban-env/soroban-env-host/src/budget/wasmi_helper.rs:144-156):
MVP integer instructions + mutable-global + sign-extension + bulk-memory.
Floats, multi-value, reference types, tail calls, extended-const and
saturating float-to-int are all disabled, and wasmparser-nostd 0.100.2 rejects
them at validation (src: vendor/crates/wasmparser-nostd-0.100.2/src/validator/operators.rs:563).

Control flow is kept structured (`block`/`loop`/`if` carry their bodies) so that
the interpreter recurses on the instruction list and a proof step is O(1).
-/
namespace Wasm

/-- Only integer value types are accepted (floats disabled). -/
inductive ValType where
  | i32 | i64
  deriving DecidableEq, Repr, Inhabited

structure FuncType where
  params : List ValType
  results : List ValType
  deriving DecidableEq, Repr, Inhabited

/-- Block types. With multi-value disabled a type-index block type is only valid
    if it has no params and at most one result (checked by the validator). -/
inductive BlockType where
  | empty
  | val (t : ValType)
  | typeIdx (i : Nat)
  deriving DecidableEq, Repr, Inhabited

structure MemArg where
  align : Nat
  offset : Nat   -- u32
  deriving DecidableEq, Repr, Inhabited

/-- Integer width selector. -/
inductive W where
  | w32 | w64
  deriving DecidableEq, Repr, Inhabited

inductive IUnop where
  | clz | ctz | popcnt
  deriving DecidableEq, Repr, Inhabited

inductive IBinop where
  | add | sub | mul | divS | divU | remS | remU | and | or | xor | shl | shrS | shrU | rotl | rotr
  deriving DecidableEq, Repr, Inhabited

inductive IRelop where
  | eq | ne | ltS | ltU | gtS | gtU | leS | leU | geS | geU
  deriving DecidableEq, Repr, Inhabited

/-- Loads: result width, number of bytes read, sign-extension. -/
inductive LoadOp where
  | i32 | i64
  | i32_8s | i32_8u | i32_16s | i32_16u
  | i64_8s | i64_8u | i64_16s | i64_16u | i64_32s | i64_32u
  deriving DecidableEq, Repr, Inhabited

inductive StoreOp where
  | i32 | i64 | i32_8 | i32_16 | i64_8 | i64_16 | i64_32
  deriving DecidableEq, Repr, Inhabited

inductive Instr where
  -- control
  | unreachable
  | nop
  | block (bt : BlockType) (body : List Instr)
  | loop (bt : BlockType) (body : List Instr)
  /-- `hasElse` records an explicit `else` opcode (even with an empty else arm);
      wasmi's translator treats the two encodings differently for fuel. -/
  | if_ (bt : BlockType) (thn els : List Instr) (hasElse : Bool)
  | br (l : Nat)
  | brIf (l : Nat)
  | brTable (ls : List Nat) (dflt : Nat)
  | return_
  | call (f : Nat)
  | callIndirect (typeIdx tableIdx : Nat)
  -- parametric
  | drop
  | select
  -- variables
  | localGet (i : Nat) | localSet (i : Nat) | localTee (i : Nat)
  | globalGet (i : Nat) | globalSet (i : Nat)
  -- memory
  | load (op : LoadOp) (m : MemArg)
  | store (op : StoreOp) (m : MemArg)
  | memorySize
  | memoryGrow
  -- bulk memory (0xFC prefix)
  | memoryInit (seg : Nat)
  | dataDrop (seg : Nat)
  | memoryCopy
  | memoryFill
  | tableInit (seg table : Nat)
  | elemDrop (seg : Nat)
  | tableCopy (dst src : Nat)
  -- numeric
  | i32Const (v : UInt32)
  | i64Const (v : UInt64)
  | eqz (w : W)
  | relop (w : W) (op : IRelop)
  | unop (w : W) (op : IUnop)
  | binop (w : W) (op : IBinop)
  | i32WrapI64
  | i64ExtendI32S
  | i64ExtendI32U
  | extend8S (w : W)
  | extend16S (w : W)
  | i64Extend32S
  deriving Repr, Inhabited

/-- Limits of memories and tables. -/
structure Limits where
  min : Nat
  max : Option Nat
  deriving DecidableEq, Repr, Inhabited

inductive RefType where
  | funcref | externref
  deriving DecidableEq, Repr, Inhabited

structure TableType where
  elem : RefType
  limits : Limits
  deriving DecidableEq, Repr, Inhabited

structure GlobalType where
  ty : ValType
  isMut : Bool
  deriving DecidableEq, Repr, Inhabited

inductive ImportDesc where
  | func (typeIdx : Nat)
  | table (t : TableType)
  | mem (l : Limits)
  | global (g : GlobalType)
  deriving DecidableEq, Repr, Inhabited

structure Import where
  module : String
  name : String
  desc : ImportDesc
  deriving DecidableEq, Repr, Inhabited

/-- Constant expressions (MVP + `ref.func`/`ref.null` as allowed in element
    segment items). -/
inductive ConstExpr where
  | i32Const (v : UInt32)
  | i64Const (v : UInt64)
  | globalGet (i : Nat)
  | refFunc (f : Nat)
  | refNull (t : RefType)
  deriving DecidableEq, Repr, Inhabited

structure Global where
  type : GlobalType
  init : ConstExpr
  deriving DecidableEq, Repr, Inhabited

inductive ExportDesc where
  | func (i : Nat) | table (i : Nat) | mem (i : Nat) | global (i : Nat)
  deriving DecidableEq, Repr, Inhabited

structure Export where
  name : String
  desc : ExportDesc
  deriving DecidableEq, Repr, Inhabited

inductive ElemMode where
  | passive
  | active (table : Nat) (offset : ConstExpr)
  | declarative
  deriving DecidableEq, Repr, Inhabited

structure Elem where
  type : RefType
  /-- Each item is a constant expression yielding a function reference or null. -/
  items : List ConstExpr
  mode : ElemMode
  deriving DecidableEq, Repr, Inhabited

/-- A function body: local declarations (expanded) and its code. -/
structure Func where
  typeIdx : Nat
  locals : List ValType
  body : List Instr
  /-- Raw count of `(n, type)` local groups, needed for fuel accounting. -/
  localGroups : List (Nat × ValType)
  deriving Repr, Inhabited

inductive DataMode where
  | passive
  | active (mem : Nat) (offset : ConstExpr)
  deriving DecidableEq, Repr, Inhabited

structure Data where
  init : ByteArray
  mode : DataMode
  deriving Inhabited

structure Module where
  types : Array FuncType := #[]
  imports : Array Import := #[]
  funcs : Array Func := #[]
  tables : Array TableType := #[]
  mems : Array Limits := #[]
  globals : Array Global := #[]
  exports : Array Export := #[]
  start : Option Nat := none
  elems : Array Elem := #[]
  datas : Array Data := #[]
  dataCount : Option Nat := none
  customs : Array (String × ByteArray) := #[]
  deriving Inhabited

namespace Module

/-- Imported functions occupy the low function indices. -/
def importedFuncTypes (m : Module) : Array Nat :=
  m.imports.filterMap fun i => match i.desc with | .func t => some t | _ => none

def numImportedFuncs (m : Module) : Nat := m.importedFuncTypes.size

def importedGlobals (m : Module) : Array GlobalType :=
  m.imports.filterMap fun i => match i.desc with | .global g => some g | _ => none

/-- Type of function index `f` (imports first, then defined functions). -/
def funcTypeIdx? (m : Module) (f : Nat) : Option Nat :=
  if h : f < m.numImportedFuncs then some m.importedFuncTypes[f]
  else (m.funcs[f - m.numImportedFuncs]?).map (·.typeIdx)

def funcType? (m : Module) (f : Nat) : Option FuncType := do
  m.types[← m.funcTypeIdx? f]?

def customSection? (m : Module) (name : String) : Option ByteArray :=
  (m.customs.find? (·.1 == name)).map (·.2)

end Module

end Wasm
