/-
The 64-bit tagged `Val` encoding shared by guest and host.

All references are to vendor/rs-soroban-env (v30.0.0 @ 0c99950),
soroban-env-common/src unless stated otherwise.
-/
import SorobanLean.Env.HostFns

namespace Soroban

/-- src: val.rs:49-173 (`#[repr(u8)] pub enum Tag`). The three marker codes and
    `Bad` are kept because `Tag::from_u8` can produce `Bad`. -/
inductive Tag where
  | False | True | Void | Error | U32Val | I32Val | U64Small | I64Small
  | TimepointSmall | DurationSmall | U128Small | I128Small | U256Small | I256Small
  | SymbolSmall | SmallCodeUpperBound | ObjectCodeLowerBound
  | U64Object | I64Object | TimepointObject | DurationObject | U128Object | I128Object
  | U256Object | I256Object | BytesObject | StringObject | SymbolObject | VecObject
  | MapObject | AddressObject | MuxedAddressObject | ExecutableTagObject
  | ObjectCodeUpperBound | Bad
  deriving DecidableEq, Repr, Inhabited

namespace Tag

/-- `tag as u8`. src: val.rs:49-173 (explicit discriminants). -/
def toU8 : Tag → UInt8
  | .False => 0 | .True => 1 | .Void => 2 | .Error => 3 | .U32Val => 4 | .I32Val => 5
  | .U64Small => 6 | .I64Small => 7 | .TimepointSmall => 8 | .DurationSmall => 9
  | .U128Small => 10 | .I128Small => 11 | .U256Small => 12 | .I256Small => 13
  | .SymbolSmall => 14 | .SmallCodeUpperBound => 15 | .ObjectCodeLowerBound => 63
  | .U64Object => 64 | .I64Object => 65 | .TimepointObject => 66 | .DurationObject => 67
  | .U128Object => 68 | .I128Object => 69 | .U256Object => 70 | .I256Object => 71
  | .BytesObject => 72 | .StringObject => 73 | .SymbolObject => 74 | .VecObject => 75
  | .MapObject => 76 | .AddressObject => 77 | .MuxedAddressObject => 78
  | .ExecutableTagObject => 79 | .ObjectCodeUpperBound => 80 | .Bad => 0x7f

/-- src: val.rs:177-179 (`u8_is_object`): `63 < x < 80`. -/
def u8IsObject (x : UInt8) : Bool := 63 < x && x < 80

/-- src: val.rs:187-206 (`Tag::from_u8`). Codes outside `[0,15) ∪ (63,80)` map
    to `Bad`; inside, the transmute picks the declared case. -/
def fromU8 (t : UInt8) : Tag :=
  if !(t < 15 || (63 < t && t < 80)) then .Bad else
  match t.toNat with
  | 0 => .False | 1 => .True | 2 => .Void | 3 => .Error | 4 => .U32Val | 5 => .I32Val
  | 6 => .U64Small | 7 => .I64Small | 8 => .TimepointSmall | 9 => .DurationSmall
  | 10 => .U128Small | 11 => .I128Small | 12 => .U256Small | 13 => .I256Small
  | 14 => .SymbolSmall | 64 => .U64Object | 65 => .I64Object | 66 => .TimepointObject
  | 67 => .DurationObject | 68 => .U128Object | 69 => .I128Object | 70 => .U256Object
  | 71 => .I256Object | 72 => .BytesObject | 73 => .StringObject | 74 => .SymbolObject
  | 75 => .VecObject | 76 => .MapObject | 77 => .AddressObject | 78 => .MuxedAddressObject
  | 79 => .ExecutableTagObject
  | _ => .Bad  -- unreachable given the range check

end Tag

/-- src: val.rs:254-256 (`pub struct Val(u64)`). -/
structure Val where
  payload : UInt64
  deriving DecidableEq, Repr, Inhabited

namespace Val

/-- src: val.rs:21-46: TAG_BITS = 8, BODY_BITS = 56, MAJOR_BITS = 32, MINOR_BITS = 24. -/
def TAG_BITS : UInt64 := 8
def MINOR_BITS : UInt64 := 24
def TAG_MASK : UInt64 := 0xff
def MINOR_MASK : UInt64 := 0x00ff_ffff

/-- src: val.rs:721-723. -/
def getTagU8 (v : Val) : UInt8 := (v.payload &&& TAG_MASK).toUInt8
/-- src: val.rs:726-729. -/
def getTag (v : Val) : Tag := Tag.fromU8 v.getTagU8
/-- src: val.rs:732-734 (`self.0 >> TAG_BITS`, logical shift on u64). -/
def getBody (v : Val) : UInt64 := v.payload >>> TAG_BITS
/-- src: val.rs:742-744 (`(self.0 as i64) >> TAG_BITS`, arithmetic shift). -/
def getSignedBody (v : Val) : Int64 := v.payload.toInt64 >>> TAG_BITS.toInt64
/-- src: val.rs:777-779. -/
def getMinor (v : Val) : UInt32 := (v.getBody &&& MINOR_MASK).toUInt32
/-- src: val.rs:782-784 (`(body >> MINOR_BITS) as u32`, truncating cast). -/
def getMajor (v : Val) : UInt32 := (v.getBody >>> MINOR_BITS).toUInt32
/-- src: val.rs:747-749. -/
def hasTag (v : Val) (t : Tag) : Bool := v.getTagU8 == t.toU8
/-- src: val.rs:737-739. -/
def hasBody (v : Val) (b : UInt64) : Bool := v.getBody == b
/-- src: val.rs:767-769. -/
def hasMinor (v : Val) (m : UInt32) : Bool := v.getMinor == m
/-- src: val.rs:772-774. -/
def hasMajor (v : Val) (m : UInt32) : Bool := v.getMajor == m
/-- src: val.rs:787-789. -/
def isObject (v : Val) : Bool := Tag.u8IsObject v.getTagU8

/-- src: val.rs:752-756 (`from_body_and_tag`: `(body << 8) | tag`). -/
def fromBodyAndTag (body : UInt64) (t : Tag) : Val := ⟨(body <<< TAG_BITS) ||| t.toU8.toUInt64⟩
/-- src: val.rs:759-764. -/
def fromMajorMinorAndTag (major minor : UInt32) (t : Tag) : Val :=
  fromBodyAndTag ((major.toUInt64 <<< MINOR_BITS) ||| minor.toUInt64) t

/-- src: val.rs:792-806, 835-841. -/
def VOID : Val := fromBodyAndTag 0 .Void
def TRUE : Val := fromBodyAndTag 0 .True
def FALSE : Val := fromBodyAndTag 0 .False
def fromBool (b : Bool) : Val := if b then TRUE else FALSE
def isVoid (v : Val) : Bool := v == VOID
def isTrue (v : Val) : Bool := v == TRUE
def isFalse (v : Val) : Bool := v == FALSE

/-- src: num.rs:17-24. -/
def fromU32 (u : UInt32) : Val := fromMajorMinorAndTag u 0 .U32Val
def fromI32 (i : Int32) : Val := fromMajorMinorAndTag i.toUInt32 0 .I32Val

end Val

/-! ## Errors (src: error.rs, stellar-xdr 30.0.0 generated/sc_error_{type,code}.rs) -/

/-- src: stellar-xdr-30.0.0/src/generated/sc_error_type.rs:33-45. -/
inductive ScErrorType where
  | Contract | WasmVm | Context | Storage | Object | Crypto | Events | Budget | Value | Auth
  deriving DecidableEq, Repr, Inhabited

/-- src: stellar-xdr-30.0.0/src/generated/sc_error_code.rs (enum ScErrorCode). -/
inductive ScErrorCode where
  | ArithDomain | IndexBounds | InvalidInput | MissingValue | ExistingValue
  | ExceededLimit | InvalidAction | InternalError | UnexpectedType | UnexpectedSize
  deriving DecidableEq, Repr, Inhabited

def ScErrorType.toU32 : ScErrorType → UInt32
  | .Contract => 0 | .WasmVm => 1 | .Context => 2 | .Storage => 3 | .Object => 4
  | .Crypto => 5 | .Events => 6 | .Budget => 7 | .Value => 8 | .Auth => 9

/-- src: sc_error_type.rs:126-146 (`TryFrom<i32>`). -/
def ScErrorType.ofI32? (i : Int32) : Option ScErrorType :=
  match i.toInt with
  | 0 => some .Contract | 1 => some .WasmVm | 2 => some .Context | 3 => some .Storage
  | 4 => some .Object | 5 => some .Crypto | 6 => some .Events | 7 => some .Budget
  | 8 => some .Value | 9 => some .Auth | _ => none

def ScErrorCode.toU32 : ScErrorCode → UInt32
  | .ArithDomain => 0 | .IndexBounds => 1 | .InvalidInput => 2 | .MissingValue => 3
  | .ExistingValue => 4 | .ExceededLimit => 5 | .InvalidAction => 6 | .InternalError => 7
  | .UnexpectedType => 8 | .UnexpectedSize => 9

/-- src: sc_error_code.rs:134-154 (`TryFrom<i32>`). -/
def ScErrorCode.ofI32? (i : Int32) : Option ScErrorCode :=
  match i.toInt with
  | 0 => some .ArithDomain | 1 => some .IndexBounds | 2 => some .InvalidInput
  | 3 => some .MissingValue | 4 => some .ExistingValue | 5 => some .ExceededLimit
  | 6 => some .InvalidAction | 7 => some .InternalError | 8 => some .UnexpectedType
  | 9 => some .UnexpectedSize | _ => none

/-- XDR `ScError`: Contract carries a raw u32 code, every other type a ScErrorCode. -/
inductive ScError where
  | contract (code : UInt32)
  | other (ty : ScErrorType) (code : ScErrorCode)  -- ty ≠ Contract
  deriving DecidableEq, Repr, Inhabited

namespace Val

/-- src: error.rs:311-313 (`from_type_and_code`: major = code, minor = type). -/
def fromError (ty : ScErrorType) (code : ScErrorCode) : Val :=
  fromMajorMinorAndTag code.toU32 ty.toU32 .Error
/-- src: error.rs:306-308. -/
def fromContractError (code : UInt32) : Val :=
  fromMajorMinorAndTag code ScErrorType.Contract.toU32 .Error

/-- src: error.rs:96-114 (`TryFrom<Error> for ScError`): type from
    `minor as i32`, code from `major as i32` (wrapping cast). -/
def toScError? (v : Val) : Option ScError := do
  let ty ← ScErrorType.ofI32? v.getMinor.toInt32
  match ty with
  | .Contract => pure (.contract v.getMajor)
  | t => pure (.other t (← ScErrorCode.ofI32? v.getMajor.toInt32))

end Val

/-! ## Small symbols (src: symbol.rs) -/

namespace SymbolSmall

/-- src: symbol.rs:99-105: 9 chars of 6 bits; SMALL_MASK = 0x003f_ffff_ffff_ffff. -/
def MAX_SMALL_CHARS : Nat := 9
def CODE_BITS : UInt64 := 6
def CODE_MASK : UInt64 := 0x3f
def SMALL_MASK : UInt64 := 0x003f_ffff_ffff_ffff

/-- src: symbol.rs:164-174: only bits 54 and 55 of the body must be clear. -/
def bodyOk (body : UInt64) : Bool := (body &&& SMALL_MASK) == body

/-- src: symbol.rs:237-246. -/
def encodeByte (b : UInt8) : Option UInt8 :=
  if b == '_'.toNat.toUInt8 then some 1
  else if '0'.toNat.toUInt8 ≤ b && b ≤ '9'.toNat.toUInt8 then some (2 + (b - '0'.toNat.toUInt8))
  else if 'A'.toNat.toUInt8 ≤ b && b ≤ 'Z'.toNat.toUInt8 then some (12 + (b - 'A'.toNat.toUInt8))
  else if 'a'.toNat.toUInt8 ≤ b && b ≤ 'z'.toNat.toUInt8 then some (38 + (b - 'a'.toNat.toUInt8))
  else none

/-- src: symbol.rs:248-264: fails if more than 9 bytes or any byte is invalid;
    otherwise `accum = (accum << 6) | code` for each byte. Returns the body. -/
def tryFromBytes (bs : List UInt8) : Option UInt64 :=
  if bs.length > MAX_SMALL_CHARS then none else
  bs.foldlM (fun acc b => do let c ← encodeByte b; pure ((acc <<< CODE_BITS) ||| c.toUInt64)) 0

end SymbolSmall

namespace Val

/-- src: val.rs:666-704 (`is_good`). -/
def isGood (v : Val) : Bool :=
  match v.getTag with
  | .Bad | .SmallCodeUpperBound | .ObjectCodeLowerBound | .ObjectCodeUpperBound => false
  | .True | .False | .Void => v.hasBody 0
  | .I32Val | .U32Val => v.hasMinor 0
  | .Error => v.toScError?.isSome
  | .SymbolSmall => SymbolSmall.bodyOk v.getBody
  | .U64Small | .I64Small | .TimepointSmall | .DurationSmall
  | .U128Small | .I128Small | .U256Small | .I256Small => true
  | .U64Object | .I64Object | .TimepointObject | .DurationObject | .U128Object
  | .I128Object | .U256Object | .I256Object | .BytesObject | .StringObject
  | .SymbolObject | .VecObject | .MapObject | .AddressObject | .MuxedAddressObject
  | .ExecutableTagObject => v.hasMinor 0

end Val

/-! ## Host-function argument marshalling (src: soroban-env-host/src/vm/dispatch.rs) -/

namespace Env.ValTy

/-- `ValConvert::is_val_type` of each env.json argument/return type that is a
    Val wrapper. Not used for the raw `i64`/`u64` and the two enums.
    src: wrapper_macros.rs:3-21 (tag-based), :282-285 (small|object unions),
    val.rs:325-329 (Bool), symbol.rs:58 (Symbol), num.rs:12-53, error.rs:22,
    val.rs:294,345-349, bytes.rs:7, string.rs:9. -/
def isValType : ValTy → Soroban.Val → _root_.Bool
  | .Val, _ => true
  | .Void, v => v.hasTag .Void
  | .Bool, v => v.isTrue || v.isFalse
  | .Error, v => v.hasTag .Error
  | .U32Val, v => v.hasTag .U32Val
  | .U64Val, v => v.hasTag .U64Small || v.hasTag .U64Object
  | .U256Val, v => v.hasTag .U256Small || v.hasTag .U256Object
  | .I256Val, v => v.hasTag .I256Small || v.hasTag .I256Object
  | .Symbol, v => v.hasTag .SymbolSmall || v.hasTag .SymbolObject
  | .AddressObject, v => v.hasTag .AddressObject
  | .MuxedAddressObject, v => v.hasTag .MuxedAddressObject
  | .BytesObject, v => v.hasTag .BytesObject
  | .DurationObject, v => v.hasTag .DurationObject
  | .TimepointObject, v => v.hasTag .TimepointObject
  | .SymbolObject, v => v.hasTag .SymbolObject
  | .StringObject, v => v.hasTag .StringObject
  | .ExecutableTagObject, v => v.hasTag .ExecutableTagObject
  | .VecObject, v => v.hasTag .VecObject
  | .MapObject, v => v.hasTag .MapObject
  | .I64Object, v => v.hasTag .I64Object
  | .I128Object, v => v.hasTag .I128Object
  | .I256Object, v => v.hasTag .I256Object
  | .U64Object, v => v.hasTag .U64Object
  | .U128Object, v => v.hasTag .U128Object
  | .U256Object, v => v.hasTag .U256Object
  | .i64, _ => true
  | .u64, _ => true
  | .StorageType, _ => true
  | .ContractTtlExtension, _ => true

/-- Is the type passed as a raw integer (not a Val)? src: val.rs:448-475 (u64,
    i64), storage_type.rs:35,46 (enums via `declare_wasmi_marshal_for_enum!`). -/
def isRaw : ValTy → _root_.Bool
  | .i64 | .u64 | .StorageType | .ContractTtlExtension => true
  | _ => false

/-- `WasmiMarshal::try_marshal_from_value` on `Value::I64(x)`.
    - Val and wrappers: `Val::from_payload(x as u64)` must be `is_good`
      (val.rs:430-441), then the wrapper's `is_val_type` (wrapper_macros.rs:93-101).
    - u64 / i64: always succeed (val.rs:450-475).
    - StorageType / ContractTtlExtension: `FromPrimitive::from_i64`, i.e. exactly
      0, 1 or 2 (wrapper_macros.rs:196-205; storage_type.rs:13-17, 40-44). -/
def tryMarshal (t : ValTy) (x : UInt64) : _root_.Bool :=
  match t with
  | .i64 | .u64 => true
  | .StorageType | .ContractTtlExtension => x == 0 || x == 1 || x == 2
  | _ => let v : Soroban.Val := ⟨x⟩; v.isGood && t.isValType v

/-- `CheckedEnvArg` is a no-op for i64, u64 and the two enums, and runs
    `check_val_integrity` for all Val wrappers. src: env.rs:259-312. -/
def needsIntegrityCheck (t : ValTy) : _root_.Bool := !t.isRaw

end Env.ValTy

/-- The error raised when an argument fails `try_marshal_from_value`.
    src: soroban-env-host/src/vm/dispatch.rs:26-33. -/
def marshalError : Val := Val.fromError .Value .InvalidInput

end Soroban
