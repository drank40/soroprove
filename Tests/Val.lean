import SorobanLean.Val
open Soroban

-- Tag round-trip for every u8 except the marker codes (src: val.rs test_tag_from_u8).
example : (List.range 256).all (fun i =>
    let t := Tag.fromU8 i.toUInt8
    t == .Bad || t.toU8 == i.toUInt8) = true := by decide +kernel
example : Tag.fromU8 15 = .Bad ∧ Tag.fromU8 63 = .Bad ∧ Tag.fromU8 80 = .Bad := by decide +kernel

-- Constants.
example : Val.VOID.payload = 2 ∧ Val.TRUE.payload = 1 ∧ Val.FALSE.payload = 0 := by decide +kernel
example : (Val.fromI32 (-10)).getMajor.toInt32 = -10 := by decide +kernel
example : (Val.fromU32 0xffffffff).isGood = true := by decide +kernel
-- signed body is an arithmetic shift
example : (Val.fromBodyAndTag 0xff_ffff_ffff_fff6 .I64Small).getSignedBody = -10 := by decide +kernel

-- Errors: (Value, InvalidInput) round-trips; an unknown code is not good.
example : (Val.fromError .Value .InvalidInput).toScError? = some (.other .Value .InvalidInput) := by decide +kernel
example : (Val.fromMajorMinorAndTag 10 8 .Error).isGood = false := by decide +kernel
example : (Val.fromContractError 12345).isGood = true := by decide +kernel

-- Small symbols: "hello" encodes to 5 six-bit codes.
example : SymbolSmall.tryFromBytes "hello".toUTF8.toList =
  some (((((((45 : UInt64) <<< 6) ||| 42) <<< 6 ||| 49) <<< 6 ||| 49) <<< 6) ||| 52) := by decide +kernel
example : SymbolSmall.tryFromBytes "hello_world".toUTF8.toList = none := by decide +kernel
example : SymbolSmall.tryFromBytes "a-b".toUTF8.toList = none := by decide +kernel

-- Marshalling: a VecObject arg rejects a MapObject-tagged value; enums accept 0..2 only.
example : Env.ValTy.tryMarshal .VecObject (Val.fromMajorMinorAndTag 3 0 .MapObject).payload = false := by decide +kernel
example : Env.ValTy.tryMarshal .VecObject (Val.fromMajorMinorAndTag 3 0 .VecObject).payload = true := by decide +kernel
example : Env.ValTy.tryMarshal .VecObject ((Val.fromMajorMinorAndTag 3 1 .VecObject).payload) = false := by decide +kernel
example : Env.ValTy.tryMarshal .StorageType 3 = false ∧ Env.ValTy.tryMarshal .StorageType 2 = true := by decide +kernel
