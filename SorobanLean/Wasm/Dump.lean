/-
Canonical text dump of a decoded module, byte-for-byte the format printed by
difftest/src/bin/decode_oracle.rs (wasmparser-nostd 0.100.2), so that the two
decoders can be diffed on a corpus.
-/
import SorobanLean.Wasm.Decode

namespace Wasm.Dump

def vt : ValType → String | .i32 => "i32" | .i64 => "i64"
def bt : BlockType → String
  | .empty => "empty" | .val t => vt t | .typeIdx i => s!"type{i}"
def strList (xs : List String) : String := "[" ++ ", ".intercalate (xs.map fun x => "\"" ++ x ++ "\"") ++ "]"
def natList (xs : List Nat) : String := "[" ++ ", ".intercalate (xs.map toString) ++ "]"
def optNat : Option Nat → String | none => "None" | some n => s!"Some({n})"
def ma (m : MemArg) : String := s!"{m.align} {m.offset}"
def w : W → String | .w32 => "i32" | .w64 => "i64"

def relop : IRelop → String
  | .eq => "eq" | .ne => "ne" | .ltS => "lt_s" | .ltU => "lt_u" | .gtS => "gt_s" | .gtU => "gt_u"
  | .leS => "le_s" | .leU => "le_u" | .geS => "ge_s" | .geU => "ge_u"
def unop : IUnop → String | .clz => "clz" | .ctz => "ctz" | .popcnt => "popcnt"
def binop : IBinop → String
  | .add => "add" | .sub => "sub" | .mul => "mul" | .divS => "div_s" | .divU => "div_u"
  | .remS => "rem_s" | .remU => "rem_u" | .and => "and" | .or => "or" | .xor => "xor"
  | .shl => "shl" | .shrS => "shr_s" | .shrU => "shr_u" | .rotl => "rotl" | .rotr => "rotr"
def loadop : LoadOp → String
  | .i32 => "i32.load" | .i64 => "i64.load" | .i32_8s => "i32.load8_s" | .i32_8u => "i32.load8_u"
  | .i32_16s => "i32.load16_s" | .i32_16u => "i32.load16_u" | .i64_8s => "i64.load8_s"
  | .i64_8u => "i64.load8_u" | .i64_16s => "i64.load16_s" | .i64_16u => "i64.load16_u"
  | .i64_32s => "i64.load32_s" | .i64_32u => "i64.load32_u"
def storeop : StoreOp → String
  | .i32 => "i32.store" | .i64 => "i64.store" | .i32_8 => "i32.store8" | .i32_16 => "i32.store16"
  | .i64_8 => "i64.store8" | .i64_16 => "i64.store16" | .i64_32 => "i64.store32"

partial def instr (i : Instr) : List String :=
  match i with
  | .unreachable => ["unreachable"] | .nop => ["nop"]
  | .block b body => [s!"block {bt b}"] ++ body.flatMap instr ++ ["end"]
  | .loop b body => [s!"loop {bt b}"] ++ body.flatMap instr ++ ["end"]
  | .if_ b thn els hasElse =>
      [s!"if {bt b}"] ++ thn.flatMap instr ++ (if hasElse then ["else"] ++ els.flatMap instr else []) ++ ["end"]
  | .br l => [s!"br {l}"] | .brIf l => [s!"br_if {l}"]
  | .brTable ls d => [s!"br_table {natList ls} {d}"]
  | .return_ => ["return"] | .call f => [s!"call {f}"]
  | .callIndirect t tb => [s!"call_indirect {t} {tb}"]
  | .drop => ["drop"] | .select => ["select"]
  | .localGet n => [s!"local.get {n}"] | .localSet n => [s!"local.set {n}"] | .localTee n => [s!"local.tee {n}"]
  | .globalGet n => [s!"global.get {n}"] | .globalSet n => [s!"global.set {n}"]
  | .load op m => [s!"{loadop op} {ma m}"] | .store op m => [s!"{storeop op} {ma m}"]
  | .memorySize => ["memory.size"] | .memoryGrow => ["memory.grow"]
  | .memoryInit s => [s!"memory.init {s}"] | .dataDrop s => [s!"data.drop {s}"]
  | .memoryCopy => ["memory.copy"] | .memoryFill => ["memory.fill"]
  | .tableInit s t => [s!"table.init {s} {t}"] | .elemDrop s => [s!"elem.drop {s}"]
  | .tableCopy d s => [s!"table.copy {d} {s}"]
  | .i32Const v => [s!"i32.const {v.toNat}"] | .i64Const v => [s!"i64.const {v.toNat}"]
  | .eqz x => [s!"{w x}.eqz"] | .relop x o => [s!"{w x}.{relop o}"]
  | .unop x o => [s!"{w x}.{unop o}"] | .binop x o => [s!"{w x}.{binop o}"]
  | .i32WrapI64 => ["i32.wrap_i64"] | .i64ExtendI32S => ["i64.extend_i32_s"]
  | .i64ExtendI32U => ["i64.extend_i32_u"]
  | .extend8S x => [s!"{w x}.extend8_s"] | .extend16S x => [s!"{w x}.extend16_s"]
  | .i64Extend32S => ["i64.extend32_s"]

def constOp : ConstExpr → String
  | .i32Const v => s!"i32.const {v.toNat}" | .i64Const v => s!"i64.const {v.toNat}"
  | .globalGet i => s!"global.get {i}" | .refFunc f => s!"ref.func {f}" | .refNull _ => "ref.null"

def constDbg : ConstExpr → String
  | .refFunc f => s!"RefFunc \{ function_index: {f} }"
  | .refNull .funcref => "RefNull { ty: FuncRef }"
  | .refNull .externref => "RefNull { ty: ExternRef }"
  | e => constOp e

/-- FNV-1a 64, matching decode_oracle.rs. -/
def fnv (b : ByteArray) : UInt64 :=
  b.foldl (fun h x => (h ^^^ x.toUInt64) * 1099511628211) 1469598103934665603

def hex (n : Nat) : String := String.ofList (Nat.toDigits 16 n)

def module (m : Module) : List String := Id.run do
  let mut o : List String := []
  -- Sections are printed in wasmparser payload order, which equals binary
  -- order; customs are interleaved in the binary but we print them last on
  -- both sides (the oracle output is sorted by section kind below).
  for t in m.types do
    o := o ++ [s!"type {strList (t.params.map vt)} -> {strList (t.results.map vt)}"]
  for i in m.imports do
    let d := match i.desc with
      | .func t => s!"func {t}" | .mem l => s!"mem {l.min} {optNat l.max}"
      | .global g => s!"global {vt g.ty} {if g.isMut then 1 else 0}"
      | .table t => s!"table {t.limits.min} {optNat t.limits.max}"
    o := o ++ [s!"import {i.module} {i.name} {d}"]
  for t in m.tables do o := o ++ [s!"table {t.limits.min} {optNat t.limits.max}"]
  for l in m.mems do o := o ++ [s!"memory {l.min} {optNat l.max}"]
  for g in m.globals do o := o ++ [s!"global {vt g.type.ty} {if g.type.isMut then 1 else 0} {constOp g.init}"]
  for e in m.exports do
    let (k, i) := match e.desc with
      | .func i => ("func", i) | .table i => ("table", i) | .mem i => ("mem", i) | .global i => ("global", i)
    o := o ++ [s!"export {e.name} {k} {i}"]
  if let some s := m.start then o := o ++ [s!"start {s}"]
  for e in m.elems do
    let mode := match e.mode with
      | .passive => "passive" | .declarative => "declared" | .active t off => s!"active {t} {constOp off}"
    let funcsOnly := e.items.all fun | .refFunc _ => true | _ => false
    let items := if funcsOnly && e.type == .funcref
      then e.items.map (fun | .refFunc f => s!"f{f}" | _ => "") else e.items.map constDbg
    o := o ++ [s!"elem {mode} {strList items}"]
  if let some c := m.dataCount then o := o ++ [s!"datacount {c}"]
  for h : k in [0:m.funcs.size] do
    let f := m.funcs[k]
    o := o ++ [s!"func {k} type {f.typeIdx} locals {strList (f.localGroups.map fun (n, t) => s!"{n}x{vt t}")}"]
    o := o ++ (f.body.flatMap instr ++ ["end"]).map ("  " ++ ·)
  for d in m.datas do
    let mode := match d.mode with | .passive => "passive" | .active mi off => s!"active {mi} {constOp off}"
    o := o ++ [s!"data {mode} {d.init.size} {hex (fnv d.init).toNat}"]
  for (n, b) in m.customs do o := o ++ [s!"custom {n} {b.size}"]
  return o

end Wasm.Dump
