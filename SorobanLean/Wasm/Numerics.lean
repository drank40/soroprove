/-
Integer numerics of Wasm as executed by wasmi_core 0.13.0
(src: vendor/crates/wasmi_core-0.13.0/src/{untyped.rs,value.rs}).
-/
namespace Wasm

/-- src: wasmi_core-0.13.0/src/trap.rs:220-283 (`pub enum TrapCode`). -/
inductive TrapCode where
  | UnreachableCodeReached | MemoryOutOfBounds | TableOutOfBounds | IndirectCallToNull
  | IntegerDivisionByZero | IntegerOverflow | BadConversionToInteger | StackOverflow
  | BadSignature | OutOfFuel | GrowthOperationLimited
  deriving DecidableEq, Repr, Inhabited

namespace Num

/-- Count leading zeros of the low `w` bits of `x`. -/
def clzN (w : Nat) (x : Nat) : Nat := Id.run do
  let mut n := 0
  for i in [0:w] do
    if (x >>> (w - 1 - i)) &&& 1 == 1 then return n
    n := n + 1
  return n

def ctzN (w : Nat) (x : Nat) : Nat := Id.run do
  let mut n := 0
  for i in [0:w] do
    if (x >>> i) &&& 1 == 1 then return n
    n := n + 1
  return n

def popcntN (w : Nat) (x : Nat) : Nat := Id.run do
  let mut n := 0
  for i in [0:w] do
    if (x >>> i) &&& 1 == 1 then n := n + 1
  return n

/-! ### i32 (src: untyped.rs i32_* and value.rs `impl_integer!`) -/

def i32clz (a : UInt32) : UInt32 := (clzN 32 a.toNat).toUInt32
def i32ctz (a : UInt32) : UInt32 := (ctzN 32 a.toNat).toUInt32
def i32popcnt (a : UInt32) : UInt32 := (popcntN 32 a.toNat).toUInt32

/-- value.rs:644-653: zero divisor traps, `overflowing_div` overflow traps. -/
def i32divS (a b : UInt32) : Except TrapCode UInt32 :=
  if b == 0 then .error .IntegerDivisionByZero
  else if a == 0x8000_0000 && b == 0xffff_ffff then .error .IntegerOverflow
  else .ok (a.toInt32 / b.toInt32).toUInt32
def i32divU (a b : UInt32) : Except TrapCode UInt32 :=
  if b == 0 then .error .IntegerDivisionByZero else .ok (a / b)
/-- value.rs:655-660: `wrapping_rem` (INT_MIN rem -1 = 0). -/
def i32remS (a b : UInt32) : Except TrapCode UInt32 :=
  if b == 0 then .error .IntegerDivisionByZero
  else if b == 0xffff_ffff then .ok 0
  else .ok (a.toInt32 % b.toInt32).toUInt32
def i32remU (a b : UInt32) : Except TrapCode UInt32 :=
  if b == 0 then .error .IntegerDivisionByZero else .ok (a % b)
/-- untyped.rs:668-690: shift amounts masked with 0x1f. -/
def i32shl (a b : UInt32) : UInt32 := a <<< (b &&& 31)
def i32shrU (a b : UInt32) : UInt32 := a >>> (b &&& 31)
def i32shrS (a b : UInt32) : UInt32 := (a.toInt32 >>> (b &&& 31).toInt32).toUInt32
/-- value.rs:636-642: `rotate_left(other as u32)` (amount taken mod 32). -/
def i32rotl (a b : UInt32) : UInt32 :=
  let s := b &&& 31
  if s == 0 then a else (a <<< s) ||| (a >>> (32 - s))
def i32rotr (a b : UInt32) : UInt32 :=
  let s := b &&& 31
  if s == 0 then a else (a >>> s) ||| (a <<< (32 - s))

/-! ### i64 -/

def i64clz (a : UInt64) : UInt64 := (clzN 64 a.toNat).toUInt64
def i64ctz (a : UInt64) : UInt64 := (ctzN 64 a.toNat).toUInt64
def i64popcnt (a : UInt64) : UInt64 := (popcntN 64 a.toNat).toUInt64
def i64divS (a b : UInt64) : Except TrapCode UInt64 :=
  if b == 0 then .error .IntegerDivisionByZero
  else if a == 0x8000_0000_0000_0000 && b == 0xffff_ffff_ffff_ffff then .error .IntegerOverflow
  else .ok (a.toInt64 / b.toInt64).toUInt64
def i64divU (a b : UInt64) : Except TrapCode UInt64 :=
  if b == 0 then .error .IntegerDivisionByZero else .ok (a / b)
def i64remS (a b : UInt64) : Except TrapCode UInt64 :=
  if b == 0 then .error .IntegerDivisionByZero
  else if b == 0xffff_ffff_ffff_ffff then .ok 0
  else .ok (a.toInt64 % b.toInt64).toUInt64
def i64remU (a b : UInt64) : Except TrapCode UInt64 :=
  if b == 0 then .error .IntegerDivisionByZero else .ok (a % b)
def i64shl (a b : UInt64) : UInt64 := a <<< (b &&& 63)
def i64shrU (a b : UInt64) : UInt64 := a >>> (b &&& 63)
def i64shrS (a b : UInt64) : UInt64 := (a.toInt64 >>> (b &&& 63).toInt64).toUInt64
def i64rotl (a b : UInt64) : UInt64 :=
  let s := b &&& 63
  if s == 0 then a else (a <<< s) ||| (a >>> (64 - s))
def i64rotr (a b : UInt64) : UInt64 :=
  let s := b &&& 63
  if s == 0 then a else (a >>> s) ||| (a <<< (64 - s))

/-! ### sign extension and conversions -/

def sext8_32 (a : UInt32) : UInt32 := (a.toUInt8.toInt8.toInt32).toUInt32
def sext16_32 (a : UInt32) : UInt32 := (a.toUInt16.toInt16.toInt32).toUInt32
def sext8_64 (a : UInt64) : UInt64 := (a.toUInt8.toInt8.toInt64).toUInt64
def sext16_64 (a : UInt64) : UInt64 := (a.toUInt16.toInt16.toInt64).toUInt64
def sext32_64 (a : UInt64) : UInt64 := (a.toUInt32.toInt32.toInt64).toUInt64
def wrap64 (a : UInt64) : UInt32 := a.toUInt32
def extendS (a : UInt32) : UInt64 := a.toInt32.toInt64.toUInt64
def extendU (a : UInt32) : UInt64 := a.toUInt64

def b32 (b : Bool) : UInt32 := if b then 1 else 0

def i32rel (op : Nat) (a b : UInt32) : UInt32 :=
  b32 <| match op with
  | 0 => a == b | 1 => a != b
  | 2 => a.toInt32 < b.toInt32 | 3 => a < b
  | 4 => a.toInt32 > b.toInt32 | 5 => a > b
  | 6 => a.toInt32 ≤ b.toInt32 | 7 => a ≤ b
  | 8 => a.toInt32 ≥ b.toInt32 | _ => a ≥ b

def i64rel (op : Nat) (a b : UInt64) : UInt32 :=
  b32 <| match op with
  | 0 => a == b | 1 => a != b
  | 2 => a.toInt64 < b.toInt64 | 3 => a < b
  | 4 => a.toInt64 > b.toInt64 | 5 => a > b
  | 6 => a.toInt64 ≤ b.toInt64 | 7 => a ≤ b
  | 8 => a.toInt64 ≥ b.toInt64 | _ => a ≥ b

end Num
end Wasm
