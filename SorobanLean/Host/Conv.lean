/-
Val ↔ ScVal conversion (src: soroban-env-host/src/host/conversion.rs:192-666,
soroban-env-common/src/{convert.rs:419-615, object.rs:124-200, num.rs:394-430,
symbol.rs:404-437}).
-/
import SorobanLean.Host.Core

namespace Soroban
open Xdr

/-! ## Small-value predicates (num.rs:394-430) -/

def isSmallU64 (u : Nat) : Bool := u < 2^56
def isSmallI64 (i : Int) : Bool := -(2^55 : Int) ≤ i ∧ i < 2^55

def u128OfParts (p : UInt128Parts) : Nat := p.hi.toNat * 2^64 + p.lo.toNat
def i128OfParts (p : Int128Parts) : Int := p.hi.toInt * 2^64 + p.lo.toNat
def u256OfParts (p : UInt256Parts) : Nat :=
  ((p.hi_hi.toNat * 2^64 + p.hi_lo.toNat) * 2^64 + p.lo_hi.toNat) * 2^64 + p.lo_lo.toNat
def i256OfParts (p : Int256Parts) : Int :=
  ((p.hi_hi.toInt * 2^64 + p.hi_lo.toNat) * 2^64 + p.lo_hi.toNat) * 2^64 + p.lo_lo.toNat

/-- `ScValObjRef::classify` (object.rs:127-198): does this ScVal become a host object? -/
def classifyIsObject (v : SCVal) : Bool :=
  match v with
  | .SCV_BYTES _ | .SCV_STRING _ | .SCV_VEC _ | .SCV_MAP _ | .SCV_ADDRESS _ | .SCV_EXECUTABLE_TAG _ => true
  | .SCV_U64 u | .SCV_TIMEPOINT u | .SCV_DURATION u => !isSmallU64 u.toNat
  | .SCV_I64 i => !isSmallI64 i.toInt
  | .SCV_U128 u => !isSmallU64 (u128OfParts u)
  | .SCV_I128 i => !isSmallI64 (i128OfParts i)
  | .SCV_U256 u => !isSmallU64 (u256OfParts u)
  | .SCV_I256 i => !isSmallI64 (i256OfParts i)
  | .SCV_SYMBOL s => s.size > SymbolSmall.MAX_SMALL_CHARS
  | _ => false

/-- `Val::can_represent_scval` (val.rs:612-628, :633-641). -/
def canRepresentScVal : SCVal → Bool
  | .SCV_VEC none | .SCV_MAP none => false
  | .SCV_CONTRACT_INSTANCE _ | .SCV_LEDGER_KEY_CONTRACT_INSTANCE | .SCV_LEDGER_KEY_NONCE _ => false
  | _ => true

def scErrorToVal : SCError → Val
  | .SCE_CONTRACT c => Val.fromContractError c
  | .SCE_WASM_VM c => Val.fromMajorMinorAndTag c.toI32.toUInt32 ScErrorType.WasmVm.toU32 .Error
  | .SCE_CONTEXT c => Val.fromMajorMinorAndTag c.toI32.toUInt32 ScErrorType.Context.toU32 .Error
  | .SCE_STORAGE c => Val.fromMajorMinorAndTag c.toI32.toUInt32 ScErrorType.Storage.toU32 .Error
  | .SCE_OBJECT c => Val.fromMajorMinorAndTag c.toI32.toUInt32 ScErrorType.Object.toU32 .Error
  | .SCE_CRYPTO c => Val.fromMajorMinorAndTag c.toI32.toUInt32 ScErrorType.Crypto.toU32 .Error
  | .SCE_EVENTS c => Val.fromMajorMinorAndTag c.toI32.toUInt32 ScErrorType.Events.toU32 .Error
  | .SCE_BUDGET c => Val.fromMajorMinorAndTag c.toI32.toUInt32 ScErrorType.Budget.toU32 .Error
  | .SCE_VALUE c => Val.fromMajorMinorAndTag c.toI32.toUInt32 ScErrorType.Value.toU32 .Error
  | .SCE_AUTH c => Val.fromMajorMinorAndTag c.toI32.toUInt32 ScErrorType.Auth.toU32 .Error

/-- `ConversionError` → (Value, UnexpectedType) (val.rs:351-366, error.rs From<ConversionError>). -/
def conversionError : HErr := errV .Value .UnexpectedType

/-- Decode the characters of a small symbol (symbol.rs:418-437). -/
def symbolSmallBytes (body : UInt64) : ByteArray := Id.run do
  let mut st := body
  let mut out := ByteArray.empty
  for _ in [0:64] do
    if st == 0 then break
    let code := ((st >>> ((9 - 1) * 6)) &&& 0x3f).toNat
    let ch : Nat := if code == 1 then '_'.toNat
      else if 2 ≤ code ∧ code ≤ 11 then '0'.toNat + code - 2
      else if 12 ≤ code ∧ code ≤ 37 then 'A'.toNat + code - 12
      else if 38 ≤ code ∧ code ≤ 63 then 'a'.toNat + code - 38
      else 0
    st := st <<< 6
    if ch != 0 then out := out.push ch.toUInt8
  return out

/-- `metered_collect` / `with_metered_capacity` into a container: charge_bulk_init_cpy. -/
def chargeCollect (containerSize itemSize len : Nat) : HostM Unit :=
  chargeBulkInitCpy containerSize itemSize len

/-- Variant index of a host object (comparison.rs:25-45 `host_obj_discriminant`). -/
def HostObject.disc : HostObject → Nat
  | .u64 _ => 0 | .i64 _ => 1 | .timepoint _ => 2 | .duration _ => 3 | .u128 _ => 4
  | .i128 _ => 5 | .u256 _ => 6 | .i256 _ => 7 | .bytes _ => 8 | .string _ => 9
  | .symbol _ => 10 | .vec _ => 11 | .map _ => 12 | .address _ => 13 | .muxedAddress _ => 14
  | .executableTag _ => 15

/-- `Tag::get_scval_type` (val.rs:214-252) as `Option<ScValType>` ordered with `None < Some`:
    0 = None, k+1 = ScValType discriminant k. -/
def Tag.scValType : Tag → Nat
  | .False | .True => 1 | .Void => 2 | .Error => 3 | .U32Val => 4 | .I32Val => 5
  | .U64Small | .U64Object => 6 | .I64Small | .I64Object => 7
  | .TimepointSmall | .TimepointObject => 8 | .DurationSmall | .DurationObject => 9
  | .U128Small | .U128Object => 10 | .I128Small | .I128Object => 11
  | .U256Small | .U256Object => 12 | .I256Small | .I256Object => 13
  | .BytesObject => 14 | .StringObject => 15 | .SymbolSmall | .SymbolObject => 16
  | .VecObject => 17 | .MapObject => 18 | .AddressObject | .MuxedAddressObject => 19
  | .ExecutableTagObject => 23
  | .SmallCodeUpperBound | .ObjectCodeLowerBound | .ObjectCodeUpperBound | .Bad => 0

/-- `check_val_integrity` (env.rs:44-56) + `Host::check_obj_integrity` (host.rs:813-839). -/
def checkValIntegrity (v : Val) : HostM Unit := do
  if !v.isGood then hostThrow .Value .InvalidInput
  if v.isObject then
    let o ← visitObj v
    if o.tag != v.getTag then hostThrow .Value .InvalidInput

/-- `HostObject::try_compare_to_small` (host_object.rs:69-148). -/
def compareToSmall (o : HostObject) (rv : Val) : HostM (Option Ordering) := do
  let t := rv.getTag
  match o with
  | .u64 u => if t == .U64Small then some <$> cmpFixed DS.u64 (compare u rv.getBody.toNat) else pure none
  | .i64 i => if t == .I64Small then some <$> cmpFixed DS.i64 (compare i rv.getSignedBody.toInt) else pure none
  | .timepoint u => if t == .TimepointSmall then some <$> cmpFixed DS.u64 (compare u rv.getBody.toNat) else pure none
  | .duration u => if t == .DurationSmall then some <$> cmpFixed DS.u64 (compare u rv.getBody.toNat) else pure none
  | .u128 u => if t == .U128Small then some <$> cmpFixed DS.u128 (compare u rv.getBody.toNat) else pure none
  | .i128 i => if t == .I128Small then some <$> cmpFixed DS.i128 (compare i rv.getSignedBody.toInt) else pure none
  | .u256 u => if t == .U256Small then some <$> cmpFixed DS.U256 (compare u rv.getBody.toNat) else pure none
  | .i256 i => if t == .I256Small then some <$> cmpFixed DS.I256 (compare i rv.getSignedBody.toInt) else pure none
  | .symbol s => if t == .SymbolSmall then some <$> cmpBytesM s (symbolSmallBytes rv.getBody) else pure none
  | _ => pure none

mutual
/-- `to_host_val` (conversion.rs:432-443): depth checkpoint, then `TryFromVal<ScVal> for Val`
    (convert.rs:522-603); objects via `to_host_obj` (conversion.rs:543-665). -/
def toHostVal : Nat → SCVal → HostM Val
  | 0, _ => hostThrow .Context .InternalError
  | fu + 1, v => withDepth do
    if !canRepresentScVal v then throw conversionError
    if classifyIsObject v then toHostObj fu v
    else match v with
      | .SCV_BOOL b => pure (Val.fromBool b)
      | .SCV_VOID => pure Val.VOID
      | .SCV_ERROR e => pure (scErrorToVal e)
      | .SCV_U32 u => pure (Val.fromU32 u)
      | .SCV_I32 i => pure (Val.fromI32 i)
      | .SCV_U64 u => pure (Val.fromBodyAndTag u .U64Small)
      | .SCV_I64 i => pure (Val.fromBodyAndTag i.toUInt64 .I64Small)
      | .SCV_TIMEPOINT u => pure (Val.fromBodyAndTag u .TimepointSmall)
      | .SCV_DURATION u => pure (Val.fromBodyAndTag u .DurationSmall)
      | .SCV_U128 u => pure (Val.fromBodyAndTag (u128OfParts u).toUInt64 .U128Small)
      | .SCV_I128 i => pure (Val.fromBodyAndTag (Int64.ofInt (i128OfParts i)).toUInt64 .I128Small)
      | .SCV_U256 u => pure (Val.fromBodyAndTag u.lo_lo .U256Small)
      | .SCV_I256 i => pure (Val.fromBodyAndTag i.lo_lo .I256Small)
      | .SCV_SYMBOL s => match SymbolSmall.tryFromBytes s.toList with
          | some body => pure (Val.fromBodyAndTag body .SymbolSmall)
          | none => hostThrow .Value .InvalidInput   -- From<SymbolError> (error.rs:142-146)
      | _ => throw conversionError
def toHostObj : Nat → SCVal → HostM Val
  | 0, _ => hostThrow .Context .InternalError
  | fu + 1, v =>
    match v with
    | .SCV_VEC (some xs) => do
        chargeCollect DS.vec DS.val xs.size
        let vv ← toHostVals fu xs.toList
        addHostObject (.vec vv.toArray)
    | .SCV_MAP (some m) => do
        chargeCollect DS.vec (DS.pair DS.val DS.val) m.size
        let kvs ← toHostPairs fu m.toList
        let ops : MMapOps Val Val := { entrySize := DS.pair DS.val DS.val, kcmp := fun a b => cmpVal fu a b }
        let mm ← MMap.fromMap ops kvs.toArray
        addHostObject (.map mm)
    | .SCV_VEC none | .SCV_MAP none => hostThrow .Value .InvalidInput
    | .SCV_U64 u => do chargeShallowCopy 1 DS.u64; addHostObject (.u64 u.toNat)
    | .SCV_I64 i => do chargeShallowCopy 1 DS.i64; addHostObject (.i64 i.toInt)
    | .SCV_TIMEPOINT t => do chargeShallowCopy 1 DS.TimePoint; addHostObject (.timepoint t.toNat)
    | .SCV_DURATION d => do chargeShallowCopy 1 DS.Duration; addHostObject (.duration d.toNat)
    | .SCV_U128 u => do chargeShallowCopy 1 DS.u128; addHostObject (.u128 (u128OfParts u))
    | .SCV_I128 i => do chargeShallowCopy 1 DS.i128; addHostObject (.i128 (i128OfParts i))
    | .SCV_U256 u => do chargeShallowCopy 2 DS.u128; addHostObject (.u256 (u256OfParts u))
    | .SCV_I256 i => do chargeShallowCopy 2 DS.i128; addHostObject (.i256 (i256OfParts i))
    | .SCV_BYTES b => do chargeShallowCopy 1 DS.ScBytes; chargeBytesSub b; addHostObject (.bytes b)
    | .SCV_STRING b => do chargeShallowCopy 1 DS.ScString; chargeBytesSub b; addHostObject (.string b)
    | .SCV_SYMBOL b => do
        -- `s.0.metered_clone` (StringM: shallow + substructure) then `ScSymbol::try_from_bytes`
        -- (host_object.rs:286-312): length ≤ SCSYMBOL_LIMIT, every byte valid.
        chargeShallowCopy 1 DS.stringM; chargeBytesSub b
        if b.size > SCSYMBOL_LIMIT then hostThrow .Value .InvalidInput
        if !(b.toList.all fun x => (SymbolSmall.encodeByte x).isSome) then hostThrow .Value .InvalidInput
        addHostObject (.symbol b)
    | .SCV_ADDRESS a =>
        match a with
        | .SC_ADDRESS_TYPE_ACCOUNT _ | .SC_ADDRESS_TYPE_CONTRACT _ => do
            chargeShallowCopy 1 DS.ScAddress; addHostObject (.address a)
        | .SC_ADDRESS_TYPE_MUXED_ACCOUNT _ | .SC_ADDRESS_TYPE_MUXED_CONTRACT _ => do
            chargeShallowCopy 1 DS.ScAddress; addHostObject (.muxedAddress a)
        | _ => hostThrow .Object .UnexpectedType
    | .SCV_EXECUTABLE_TAG b => do chargeShallowCopy 1 DS.stringM; chargeBytesSub b; addHostObject (.executableTag b)
    | _ => hostThrow .Value .InternalError
def toHostVals : Nat → List SCVal → HostM (List Val)
  | 0, _ => hostThrow .Context .InternalError
  | _ + 1, [] => pure []
  | fu + 1, x :: xs => do let v ← toHostVal fu x; let vs ← toHostVals fu xs; pure (v :: vs)
def toHostPairs : Nat → List SCMapEntry → HostM (List (Val × Val))
  | 0, _ => hostThrow .Context .InternalError
  | _ + 1, [] => pure []
  | fu + 1, e :: es => do
    let k ← toHostVal fu e.key
    let v ← toHostVal fu e.val
    let r ← toHostPairs fu es
    pure ((k, v) :: r)
/-- `Compare<Val> for E` (soroban-env-common/src/compare.rs:126-216): equal payloads,
    objects via `Env::obj_cmp`, otherwise by tag then by the small wrapper (unmetered:
    num.rs:27-39, wrapper_macros.rs:339-382, error.rs:50-57, symbol.rs:195-199). -/
def cmpVal : Nat → Val → Val → HostM Ordering
  | 0, _, _ => hostThrow .Context .InternalError
  | fu + 1, a, b => do
    if a.payload == b.payload then return .eq
    if a.isObject || b.isObject then
      let v ← envObjCmp fu a b
      return (if v == 0 then .eq else if v < 0 then .lt else .gt)
    let ta := a.getTag.toU8; let tb := b.getTag.toU8
    if ta < tb then return .lt
    if ta > tb then return .gt
    match a.getTag with
    | .Error => pure ((compare a.getMinor.toNat b.getMinor.toNat).then (compare a.getMajor.toNat b.getMajor.toNat))
    | .U32Val => pure (compare a.getMajor.toNat b.getMajor.toNat)
    | .I32Val => pure (compare a.getMajor.toInt32.toInt b.getMajor.toInt32.toInt)
    | .U64Small | .TimepointSmall | .DurationSmall | .U128Small | .U256Small =>
        pure (compare a.getBody.toNat b.getBody.toNat)
    | .I64Small | .I128Small | .I256Small => pure (compare a.getSignedBody.toInt b.getSignedBody.toInt)
    | .SymbolSmall => pure (Ord.lexBytes (symbolSmallBytes a.getBody) (symbolSmallBytes b.getBody))
    | .U64Object | .I64Object | .TimepointObject | .DurationObject | .U128Object | .I128Object
    | .U256Object | .I256Object | .BytesObject | .StringObject | .SymbolObject | .VecObject
    | .MapObject | .AddressObject | .MuxedAddressObject | .ExecutableTagObject =>
        hostThrow .Context .InternalError
    | _ => pure .eq
/-- `obj_cmp` called through `Env` (vmcaller_env.rs:181-200): `check_env_arg` on both
    arguments, then host.rs:1192-1248. -/
def envObjCmp : Nat → Val → Val → HostM Int
  | 0, _, _ => hostThrow .Context .InternalError
  | fu + 1, a, b => do
    checkValIntegrity a
    checkValIntegrity b
    let part ← (match a.isObject, b.isObject with
      | true, true => do
          let ao ← visitObj a
          let bo ← visitObj b
          pure (some (← cmpHostObj fu ao bo))
      | true, false => do
          let ao ← visitObj a
          compareToSmall ao b
      | false, true => do
          let bo ← visitObj b
          pure ((← compareToSmall bo a).map Ordering.swap)
      | false, false => hostThrow .Value .UnexpectedType)
    let res ← match part with
      | some r => pure r
      | none =>
        let ta := a.getTag.scValType; let tb := b.getTag.scValType
        if ta == tb then hostThrow .Value .InternalError
        else pure (compare ta tb)
    pure (match res with | .lt => -1 | .eq => 0 | .gt => 1)
/-- `Compare<HostObject> for Host` (comparison.rs:47-101), in the depth limiter. -/
def cmpHostObj : Nat → HostObject → HostObject → HostM Ordering
  | 0, _, _ => hostThrow .Context .InternalError
  | fu + 1, a, b => withDepth do
    match a, b with
    | .u64 x, .u64 y | .timepoint x, .timepoint y | .duration x, .duration y =>
        cmpFixed DS.u64 (compare x y)
    | .i64 x, .i64 y => cmpFixed DS.i64 (compare x y)
    | .u128 x, .u128 y => cmpFixed DS.u128 (compare x y)
    | .i128 x, .i128 y => cmpFixed DS.i128 (compare x y)
    | .u256 x, .u256 y => cmpFixed DS.U256 (compare x y)
    | .i256 x, .i256 y => cmpFixed DS.I256 (compare x y)
    | .vec x, .vec y => do
        -- `Compare<MeteredVector<Val>> for Host` (metered_vector.rs:366-390)
        let n := min x.size y.size
        charge .MemCpy (some (satMul DS.val n))
        charge .MemCmp (some (satMul DS.val n))
        cmpValList fu x.toList y.toList
    | .map x, .map y => do
        -- `Compare<MeteredOrdMap> for Host` (metered_map.rs:368-392)
        charge .MemCpy (some (satMul (DS.pair DS.val DS.val) (min x.size y.size)))
        cmpPairList fu x.toList y.toList
    | .bytes x, .bytes y | .string x, .string y | .symbol x, .symbol y
    | .executableTag x, .executableTag y => cmpBytesM x y
    | .address x, .address y => cmpScAddress x y
    | .muxedAddress x, .muxedAddress y => cmpFixed DS.MuxedScAddress (Ord.cmp_SCAddress x y)
    | x, y => pure (compare x.disc y.disc)
def cmpValList : Nat → List Val → List Val → HostM Ordering
  | 0, _, _ => hostThrow .Context .InternalError
  | _ + 1, [], [] => pure .eq
  | _ + 1, [], _ :: _ => pure .lt
  | _ + 1, _ :: _, [] => pure .gt
  | fu + 1, x :: xs, y :: ys => thenM (cmpVal fu x y) fun _ => cmpValList fu xs ys
def cmpPairList : Nat → List (Val × Val) → List (Val × Val) → HostM Ordering
  | 0, _, _ => hostThrow .Context .InternalError
  | _ + 1, [], [] => pure .eq
  | _ + 1, [], _ :: _ => pure .lt
  | _ + 1, _ :: _, [] => pure .gt
  | fu + 1, x :: xs, y :: ys =>
      thenM (thenM (cmpVal fu x.1 y.1) fun _ => cmpVal fu x.2 y.2) fun _ => cmpPairList fu xs ys
end

/-- `to_valid_host_val` (conversion.rs:445-458): non-budget errors become (Value, InternalError). -/
def toValidHostVal (v : SCVal) : HostM Val :=
  tryCatch (toHostVal BIG v) fun e =>
    if e.getMinor == ScErrorType.Budget.toU32 then throw e else hostThrow .Value .InternalError

/-- `scvals_to_val_vec` (conversion.rs:216-221): metered_collect into Result<Vec<Val>, HostError>. -/
def scvalsToValVec (xs : Array SCVal) : HostM (Array Val) := do
  chargeCollect (DS.vec + DS.HostError) (DS.val + DS.HostError) xs.size
  let mut out := #[]
  for x in xs do out := out.push (← toHostVal BIG x)
  pure out

/-! ## Val → ScVal (conversion.rs:263-286, :403-431, :470-541; convert.rs:419-510) -/

def toU64Lo (i : Int) : UInt64 := UInt64.ofNat (Int.emod i (2^64)).toNat
def toI64Hi (i : Int) : Int64 := Int64.ofInt (Int.ediv i (2^64))

/-- `TryFrom<Error> for ScError` (error.rs:96-114); xdr errors → (Value, InvalidInput)
    except depth/length (not reachable here). -/
def errorValToScError (v : Val) : HostM SCError := do
  let some ty := SCErrorType.ofI32? v.getMinor.toInt32 | hostThrow .Value .InvalidInput
  let u := v.getMajor
  if ty == .SCE_CONTRACT then return .SCE_CONTRACT u
  let some c := SCErrorCode.ofI32? u.toInt32 | hostThrow .Value .InvalidInput
  pure (match ty with
    | .SCE_WASM_VM => .SCE_WASM_VM c | .SCE_CONTEXT => .SCE_CONTEXT c
    | .SCE_STORAGE => .SCE_STORAGE c | .SCE_OBJECT => .SCE_OBJECT c
    | .SCE_CRYPTO => .SCE_CRYPTO c | .SCE_EVENTS => .SCE_EVENTS c
    | .SCE_BUDGET => .SCE_BUDGET c | .SCE_VALUE => .SCE_VALUE c
    | _ => .SCE_AUTH c)

/-- `check_val_representable_scval` (conversion.rs:390-402). -/
def checkValRepresentableScVal (v : SCVal) : HostM Unit :=
  if canRepresentScVal v then pure () else hostThrow .Value .InternalError

def i256Parts (i : Int) : Int256Parts :=
  let lolo := toU64Lo i; let r1 := Int.ediv i (2^64)
  let lohi := toU64Lo r1; let r2 := Int.ediv r1 (2^64)
  let hilo := toU64Lo r2; let r3 := Int.ediv r2 (2^64)
  { hi_hi := Int64.ofInt r3, hi_lo := hilo, lo_hi := lohi, lo_lo := lolo }

def u256Parts (u : Nat) : UInt256Parts :=
  { hi_hi := UInt64.ofNat (u / 2^192), hi_lo := UInt64.ofNat (u / 2^128),
    lo_hi := UInt64.ofNat (u / 2^64), lo_lo := UInt64.ofNat u }

mutual
/-- `from_host_val` minus the final representability check: the depth checkpoint and
    `TryFromVal<Val> for ScVal`. The check is applied by `fromHostVal`. -/
def fromHostValInner : Nat → Val → HostM SCVal
  | 0, _ => hostThrow .Context .InternalError
  | fu + 1, v => withDepth do
    if v.isObject then fromHostObj fu v
    else match v.getTag with
      | .False => pure (.SCV_BOOL false)
      | .True => pure (.SCV_BOOL true)
      | .Void => pure .SCV_VOID
      | .Error => .SCV_ERROR <$> errorValToScError v
      | .U32Val => pure (.SCV_U32 v.getMajor)
      | .I32Val => pure (.SCV_I32 v.getMajor.toInt32)
      | .U64Small => pure (.SCV_U64 v.getBody)
      | .I64Small => pure (.SCV_I64 v.getSignedBody)
      | .TimepointSmall => pure (.SCV_TIMEPOINT v.getBody)
      | .DurationSmall => pure (.SCV_DURATION v.getBody)
      | .U128Small => pure (.SCV_U128 { hi := 0, lo := v.getBody })
      | .I128Small =>
          let b := v.getSignedBody.toInt
          pure (.SCV_I128 { hi := toI64Hi b, lo := toU64Lo b })
      | .U256Small => pure (.SCV_U256 { hi_hi := 0, hi_lo := 0, lo_hi := 0, lo_lo := v.getBody })
      | .I256Small => pure (.SCV_I256 (i256Parts v.getSignedBody.toInt))
      | .SymbolSmall => pure (.SCV_SYMBOL (symbolSmallBytes v.getBody))
      | _ => throw conversionError
def fromHostValChecked : Nat → Val → HostM SCVal
  | 0, _ => hostThrow .Context .InternalError
  | fu + 1, v => do
    let r ← fromHostValInner fu v
    checkValRepresentableScVal r
    pure r
/-- `from_host_obj` (conversion.rs:470-541), inside `visit_obj_untyped`. -/
def fromHostObj : Nat → Val → HostM SCVal
  | 0, _ => hostThrow .Context .InternalError
  | fu + 1, v => do
    let o ← visitObj v
    match o with
    | .vec xs => do
        chargeBulkInitCpy DS.vec DS.ScVal xs.size
        let sv ← fromHostVals fu xs.toList
        pure (.SCV_VEC (some sv.toArray))
    | .map m => do
        let es ← hostMapToScMap fu false m
        pure (.SCV_MAP (some es))
    | .u64 u => do chargeShallowCopy 1 DS.u64; pure (.SCV_U64 (UInt64.ofNat u))
    | .i64 i => do chargeShallowCopy 1 DS.i64; pure (.SCV_I64 (Int64.ofInt i))
    | .timepoint t => do chargeShallowCopy 1 DS.TimePoint; pure (.SCV_TIMEPOINT (UInt64.ofNat t))
    | .duration d => do chargeShallowCopy 1 DS.Duration; pure (.SCV_DURATION (UInt64.ofNat d))
    | .u128 u => do chargeShallowCopy 1 DS.u128; pure (.SCV_U128 { hi := UInt64.ofNat (u / 2^64), lo := UInt64.ofNat u })
    | .i128 i => do chargeShallowCopy 1 DS.i128; pure (.SCV_I128 { hi := toI64Hi i, lo := toU64Lo i })
    | .u256 u => do chargeShallowCopy 2 DS.u128; pure (.SCV_U256 (u256Parts u))
    | .i256 i => do chargeShallowCopy 2 DS.i128; pure (.SCV_I256 (i256Parts i))
    | .bytes b => do chargeShallowCopy 1 DS.ScBytes; chargeBytesSub b; pure (.SCV_BYTES b)
    | .string b => do chargeShallowCopy 1 DS.ScString; chargeBytesSub b; pure (.SCV_STRING b)
    | .symbol b => do chargeShallowCopy 1 DS.ScSymbol; chargeBytesSub b; pure (.SCV_SYMBOL b)
    | .address a => do chargeShallowCopy 1 DS.ScAddress; pure (.SCV_ADDRESS a)
    | .muxedAddress a => do
        if (← get).storageKeyConversionActive then hostThrow .Storage .InvalidInput
        chargeShallowCopy 1 DS.ScAddress; pure (.SCV_ADDRESS a)
    | .executableTag b => do chargeShallowCopy 1 DS.ScString; chargeBytesSub b; pure (.SCV_EXECUTABLE_TAG b)
def fromHostVals : Nat → List Val → HostM (List SCVal)
  | 0, _ => hostThrow .Context .InternalError
  | _ + 1, [] => pure []
  | fu + 1, x :: xs => do let a ← fromHostValChecked fu x; let r ← fromHostVals fu xs; pure (a :: r)
/-- `host_map_to_scmap` / `instance_storage_map_to_scmap` (conversion.rs:263-286):
    capacity charge, `iter` scan charge, then key/value conversions. -/
def hostMapToScMap : Nat → Bool → Array (Val × Val) → HostM (Array SCMapEntry)
  | 0, _, _ => hostThrow .Context .InternalError
  | fu + 1, forStorage, m => do
    chargeBulkInitCpy DS.vec DS.ScMapEntry m.size
    chargeAccess (DS.pair DS.val DS.val) m.size
    let es ← mapEntries fu forStorage m.toList
    pure es.toArray
def mapEntries : Nat → Bool → List (Val × Val) → HostM (List SCMapEntry)
  | 0, _, _ => hostThrow .Context .InternalError
  | _ + 1, _, [] => pure []
  | fu + 1, forStorage, (k, v) :: r => do
    let key ← if forStorage then fromHostValForStorageF fu k else fromHostValChecked fu k
    let val ← fromHostValChecked fu v
    let rest ← mapEntries fu forStorage r
    pure ({ key, val } :: rest)
/-- `from_host_val_for_storage` (conversion.rs:418-431): the flag is reset even on error. -/
def fromHostValForStorageF : Nat → Val → HostM SCVal
  | 0, _ => hostThrow .Context .InternalError
  | fu + 1, v => do
    modify fun s => { s with storageKeyConversionActive := true }
    let r ← tryCatch (do let a ← fromHostValInner fu v; pure (Except.ok a)) (fun e => pure (Except.error e))
    modify fun s => { s with storageKeyConversionActive := false }
    let r ← (match r with | .ok a => pure a | .error e => throw e : HostM SCVal)
    checkValRepresentableScVal r
    pure r
end

def fromHostVal (v : Val) : HostM SCVal := fromHostValChecked BIG v
def fromHostValForStorage (v : Val) : HostM SCVal := fromHostValForStorageF BIG v
def instanceStorageMapToScMap (m : Array (Val × Val)) : HostM (Array SCMapEntry) :=
  hostMapToScMap BIG true m

end Soroban
