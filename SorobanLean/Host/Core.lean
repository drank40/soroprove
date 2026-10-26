/-
Core host machinery: object table, metered ordered maps, metered comparisons.

src (vendor/rs-soroban-env/soroban-env-host/src):
  host_object.rs:340-560 (handles, add/visit), host/metered_map.rs,
  host/metered_vector.rs:393-445 (binary search), host/comparison.rs,
  soroban-env-common/src/compare.rs, host.rs `obj_cmp`.
-/
import SorobanLean.Host.State

namespace Soroban
open Xdr

/-! ## Errors -/

def errV (t : ScErrorType) (c : ScErrorCode) : HErr := Val.fromError t c
/-- Lean-only marker for behaviour that is not modelled yet. Its tag byte is `Bad`
    (0x7f), so it can never coincide with an `Error` the real host produces; any
    execution reaching it is outside the verified fragment. -/
def unsupportedErr : HErr := ⟨0xFFFF_FFFF_FFFF_FF7F⟩
def unsupported {α} : HostM α := throw unsupportedErr

def hostThrow {α} (t : ScErrorType) (c : ScErrorCode) : HostM α := throw (errV t c)

/-! ## Object handles (host_object.rs:340-372) -/

def isRelativeHandle (h : UInt32) : Bool := h % 2 == 0
def handleToIndex (h : UInt32) : Nat := h.toNat / 2

/-- `index_to_handle`: (index << 1) | !relative, failing with (Object, ArithDomain)
    (`err_arith_overflow`) when it does not fit in u32. -/
def indexToHandle (index : Nat) (relative : Bool) : HostM UInt32 :=
  if index < 2^32 && index * 2 < 2^32 then
    pure (index * 2 + (if relative then 0 else 1)).toUInt32
  else hostThrow .Object .ArithDomain

/-- `Object::from_handle_and_tag` = Val::from_major_minor_and_tag(handle, 0, tag). -/
def objVal (handle : UInt32) (t : Tag) : Val := Val.fromMajorMinorAndTag handle 0 t
def objHandle (v : Val) : UInt32 := v.getMajor

/-- Tag of each host object kind (host_object.rs `HostObjectType` impls). -/
def HostObject.tag : HostObject → Tag
  | .vec _ => .VecObject | .map _ => .MapObject | .u64 _ => .U64Object | .i64 _ => .I64Object
  | .timepoint _ => .TimepointObject | .duration _ => .DurationObject | .u128 _ => .U128Object
  | .i128 _ => .I128Object | .u256 _ => .U256Object | .i256 _ => .I256Object
  | .bytes _ => .BytesObject | .string _ => .StringObject | .symbol _ => .SymbolObject
  | .address _ => .AddressObject | .muxedAddress _ => .MuxedAddressObject
  | .executableTag _ => .ExecutableTagObject

/-- `add_host_object` (host_object.rs:463-478): handle from the current length,
    charge one `HostObject` heap alloc, push. -/
def addHostObject (o : HostObject) : HostM Val := do
  let s ← get
  let handle ← indexToHandle s.objects.size false
  chargeHeapAlloc 1 DS.HostObject
  modify fun s => { s with objects := s.objects.push o }
  pure (objVal handle o.tag)

/-- `visit_obj_untyped` (host_object.rs:480-520). -/
def visitObj (obj : Val) : HostM HostObject := do
  charge .VisitObject none
  let h := objHandle obj
  if isRelativeHandle h then hostThrow .Object .InternalError
  else match (← get).objects[handleToIndex h]? with
    | some o => pure o
    | none =>
      -- `Val::try_from_val(self, &payload)` (:509-510): a payload that is not a small u64
      -- goes through `add_host_object` while `objects` is still borrowed: the heap-alloc
      -- charge happens, then `try_borrow_objects_mut` fails with (Context, InternalError).
      if obj.payload.toNat < 2^56 then hostThrow .Value .InvalidInput
      else do
        let _ ← indexToHandle (← get).objects.size false
        chargeHeapAlloc 1 DS.HostObject
        hostThrow .Context .InternalError

/-- Access to the context stack (`try_borrow_context_stack[_mut]`): fails while it is
    mutably borrowed. -/
def checkCtxBorrow : HostM Unit := do
  if (← get).ctxBorrowedMut then hostThrow .Context .InternalError

/-- Run `f` with the context stack mutably borrowed (the flag is restored on error). -/
def withCtxBorrowMut {α} (f : HostM α) : HostM α := do
  checkCtxBorrow
  modify fun s => { s with ctxBorrowedMut := true }
  let r ← tryCatch (Except.ok <$> f) (fun e => pure (Except.error e))
  modify fun s => { s with ctxBorrowedMut := false }
  match r with
  | .ok a => pure a
  | .error e => throw e

/-- `with_current_context_mut` (frame.rs:291-313): `f` gets the top context and returns
    its replacement, which is written back only on success. -/
def withCurrentContext {α} (f : Context → HostM (α × Context)) : HostM α := do
  checkCtxBorrow
  match (← get).contexts.back? with
  | none => hostThrow .Context .InternalError
  | some ctx =>
    let (a, ctx') ← withCtxBorrowMut (f ctx)
    modify fun s => { s with contexts := s.contexts.set! (s.contexts.size - 1) ctx' }
    pure a

/-- Current frame's relative object table (frame.rs:331-352). -/
def withRelTable {α} (f : Array Val → HostM (α × Array Val)) : HostM α :=
  withCurrentContext fun ctx =>
    match ctx.frame with
    | .contractVM cid fn args inst rel => do
      let (a, rel') ← f rel
      pure (a, { ctx with frame := .contractVM cid fn args inst rel' })
    | _ => hostThrow .Context .InternalError

/-- `relative_to_absolute` (host_object.rs:375-423). -/
def relativeToAbsolute (v : Val) : HostM Val := do
  if !v.isObject then return v
  let h := objHandle v
  if isRelativeHandle h then
    let idx := handleToIndex h
    let absOpt ← withRelTable fun t => pure (t[idx]?, t)
    match absOpt with
    | some a => if a.getTag == v.getTag then pure a else hostThrow .Value .InvalidInput
    | none => hostThrow .Value .InvalidInput
  else hostThrow .Value .InvalidInput

/-- `absolute_to_relative` (host_object.rs:425-457). -/
def absoluteToRelative (v : Val) : HostM Val := do
  if !v.isObject then return v
  let h := objHandle v
  if isRelativeHandle h then hostThrow .Context .InternalError
  else
    chargeHeapAlloc 1 DS.val   -- charge_heap_alloc::<Object>(1)
    let idx ← withRelTable fun t => pure (t.size, t.push v)
    let handle ← indexToHandle idx true
    pure (objVal handle v.getTag)

/-! ## Metered ordered maps (host/metered_map.rs) -/

/-- Bit length = `64 - leading_zeros(len)`. -/
def bitLen (n : Nat) : Nat := if n = 0 then 0 else Nat.log2 n + 1

def chargeAccess (entrySize count : Nat) : HostM Unit := charge .MemCpy (some (satMul entrySize count))
def chargeBinsearch (entrySize len : Nat) : HostM Unit :=
  charge .MemCpy (some (satMul entrySize (bitLen len + 1)))

/-- `binary_search_by_pre_rust_182` with a metered comparator (`cmp probe key`).
    A comparator error aborts (the Rust version returns `Equal` thereafter, which
    stops at the next iteration without further comparisons, then propagates). -/
def binSearch {α} [Inhabited α] (xs : Array α) (cmp : α → HostM Ordering) : HostM (Except Nat Nat) := do
  let mut size := xs.size
  let mut left := 0
  let mut right := size
  for _ in [0:xs.size + 1] do
    if left < right then
      let mid := left + size / 2
      let c ← cmp (xs[mid]!)
      left := if c == .lt then mid + 1 else left
      right := if c == .gt then mid else right
      if c == .eq then return .ok mid
      size := right - left
  return .error left

/-- A metered map is an array of (K, V) kept sorted by `kcmp`. `entrySize` is
    `<(K, V) as DeclaredSizeForMetering>::DECLARED_SIZE`. -/
structure MMapOps (K V : Type) where
  entrySize : Nat
  kcmp : K → K → HostM Ordering
  /-- extra substructure charge of a (K, V) element on deep clone (none if shallow) -/
  sub : K × V → HostM Unit := fun _ => pure ()

namespace MMap
variable {K V : Type} [Inhabited K] [Inhabited V]

def find (o : MMapOps K V) (m : Array (K × V)) (k : K) : HostM (Except Nat Nat) := do
  chargeBinsearch o.entrySize m.size
  binSearch m fun p => o.kcmp p.1 k

/-- `from_map` (metered_map.rs:100-121): scan charge, then each adjacent pair must
    compare `Less`, else (Object, InvalidInput). -/
def fromMap (o : MMapOps K V) (m : Array (K × V)) : HostM (Array (K × V)) := do
  if m.size ≥ 2^32 then hostThrow .Object .IndexBounds
  chargeAccess o.entrySize m.size
  for i in [1:m.size] do
    if (← o.kcmp m[i-1]!.1 m[i]!.1) != .lt then hostThrow .Object .InvalidInput
  pure m

/-- `from_exact_iter` (:122-138): deep clone charge of the Vec<(K,V)> then from_map. -/
def fromExactIter (o : MMapOps K V) (m : Array (K × V)) : HostM (Array (K × V)) := do
  if m.size ≥ 2^32 then hostThrow .Object .IndexBounds
  chargeShallowCopy 1 DS.vec
  chargeHeapAlloc m.size o.entrySize
  chargeShallowCopy m.size o.entrySize
  for e in m do o.sub e
  fromMap o m

/-- `insert` (:157-185). -/
def insert (o : MMapOps K V) (m : Array (K × V)) (k : K) (v : V) : HostM (Array (K × V)) := do
  chargeAccess o.entrySize 1
  match ← find o m k with
  | .ok pos => fromExactIter o ((m.extract 0 pos).push (k, v) ++ m.extract (pos + 1) m.size)
  | .error pos =>
    if m.size == 2^32 - 1 then hostThrow .Object .IndexBounds
    fromExactIter o ((m.extract 0 pos).push (k, v) ++ m.extract pos m.size)

/-- `get` (:186-203). -/
def get? (o : MMapOps K V) (m : Array (K × V)) (k : K) : HostM (Option V) := do
  match ← find o m k with
  | .ok i => do chargeAccess o.entrySize 1; pure (some m[i]!.2)
  | .error _ => pure none

def containsKey (o : MMapOps K V) (m : Array (K × V)) (k : K) : HostM Bool := do
  match ← find o m k with
  | .ok _ => pure true
  | .error _ => pure false

end MMap

/-! ## Metered comparisons (host/comparison.rs) -/

/-- `Compare<&[u8]> for Budget` (:94-100): MemCmp(min len) then lexicographic. -/
def cmpBytesM (a b : ByteArray) : HostM Ordering := do
  charge .MemCmp (some (min a.size b.size))
  pure (Ord.lexBytes a b)

/-- `FixedSizeOrdType` (:110-133): MemCmp(declared size), then derived Ord. -/
def cmpFixed (declSize : Nat) (o : Ordering) : HostM Ordering := do
  charge .MemCmp (some declSize)
  pure o

def cmpScAddress (a b : SCAddress) : HostM Ordering := cmpFixed DS.ScAddress (Ord.cmp_SCAddress a b)
def cmpDurability (a b : ContractDataDurability) : HostM Ordering :=
  cmpFixed DS.ContractDataDurability (Ord.cmp_ContractDataDurability a b)

/-- `then` for metered tuple comparisons (compare.rs:30-50). -/
@[inline] def thenM (a : HostM Ordering) (b : Unit → HostM Ordering) : HostM Ordering := do
  match ← a with
  | .eq => b ()
  | o => pure o

/-- SCVal discriminant (variant index) as used by `discriminant().cmp` (ScValType order). -/
def scvalDisc (v : SCVal) : Nat :=
  match v with
  | .SCV_BOOL _ => 0 | .SCV_VOID => 1 | .SCV_ERROR _ => 2 | .SCV_U32 _ => 3 | .SCV_I32 _ => 4
  | .SCV_U64 _ => 5 | .SCV_I64 _ => 6 | .SCV_TIMEPOINT _ => 7 | .SCV_DURATION _ => 8
  | .SCV_U128 _ => 9 | .SCV_I128 _ => 10 | .SCV_U256 _ => 11 | .SCV_I256 _ => 12
  | .SCV_BYTES _ => 13 | .SCV_STRING _ => 14 | .SCV_SYMBOL _ => 15 | .SCV_VEC _ => 16
  | .SCV_MAP _ => 17 | .SCV_ADDRESS _ => 18 | .SCV_CONTRACT_INSTANCE _ => 19
  | .SCV_LEDGER_KEY_CONTRACT_INSTANCE => 20 | .SCV_LEDGER_KEY_NONCE _ => 21
  | .SCV_EXECUTABLE_TAG _ => 22

mutual
/-- `Compare<ScVal> for Budget` (comparison.rs:254-311), in the budget depth limiter. -/
def cmpScVal : Nat → SCVal → SCVal → HostM Ordering
  | 0, _, _ => hostThrow .Context .InternalError
  | fu + 1, a, b => withDepth do
    match a, b with
    | .SCV_VEC (some x), .SCV_VEC (some y) => do
        charge .MemCpy (some (satMul DS.ScVal (min x.size y.size)))
        cmpScVals fu x.toList y.toList
    | .SCV_MAP (some x), .SCV_MAP (some y) => do
        charge .MemCpy (some (satMul DS.ScMapEntry (min x.size y.size)))
        cmpEntries fu x.toList y.toList
    | .SCV_VEC none, _ | _, .SCV_VEC none | .SCV_MAP none, _ | _, .SCV_MAP none =>
        hostThrow .Value .InvalidInput
    | .SCV_BYTES x, .SCV_BYTES y | .SCV_STRING x, .SCV_STRING y | .SCV_SYMBOL x, .SCV_SYMBOL y
    | .SCV_EXECUTABLE_TAG x, .SCV_EXECUTABLE_TAG y => cmpBytesM x y
    | .SCV_CONTRACT_INSTANCE x, .SCV_CONTRACT_INSTANCE y =>
        thenM (cmpFixed DS.ContractExecutable (Ord.cmp_ContractExecutable x.executable y.executable)) fun _ =>
          match x.storage, y.storage with
          | none, none => pure .eq | none, some _ => pure .lt | some _, none => pure .gt
          | some m1, some m2 => do
            charge .MemCpy (some (satMul DS.ScMapEntry (min m1.size m2.size)))
            cmpEntries fu m1.toList m2.toList
    | .SCV_VOID, .SCV_VOID | .SCV_LEDGER_KEY_CONTRACT_INSTANCE, .SCV_LEDGER_KEY_CONTRACT_INSTANCE => pure .eq
    | .SCV_BOOL x, .SCV_BOOL y => cmpFixed DS.bool (compare x y)
    | .SCV_ERROR x, .SCV_ERROR y => cmpFixed DS.ScError (Ord.cmp_SCError x y)
    | .SCV_U32 x, .SCV_U32 y => cmpFixed DS.u32 (compare x.toNat y.toNat)
    | .SCV_I32 x, .SCV_I32 y => cmpFixed DS.i32 (compare x.toInt y.toInt)
    | .SCV_U64 x, .SCV_U64 y => cmpFixed DS.u64 (compare x.toNat y.toNat)
    | .SCV_I64 x, .SCV_I64 y => cmpFixed DS.i64 (compare x.toInt y.toInt)
    | .SCV_TIMEPOINT x, .SCV_TIMEPOINT y => cmpFixed DS.TimePoint (compare x.toNat y.toNat)
    | .SCV_DURATION x, .SCV_DURATION y => cmpFixed DS.Duration (compare x.toNat y.toNat)
    | .SCV_U128 x, .SCV_U128 y => cmpFixed DS.UInt128Parts (Ord.cmp_UInt128Parts x y)
    | .SCV_I128 x, .SCV_I128 y => cmpFixed DS.Int128Parts (Ord.cmp_Int128Parts x y)
    | .SCV_U256 x, .SCV_U256 y => cmpFixed DS.UInt256Parts (Ord.cmp_UInt256Parts x y)
    | .SCV_I256 x, .SCV_I256 y => cmpFixed DS.Int256Parts (Ord.cmp_Int256Parts x y)
    | .SCV_ADDRESS x, .SCV_ADDRESS y => cmpScAddress x y
    | .SCV_LEDGER_KEY_NONCE x, .SCV_LEDGER_KEY_NONCE y => cmpFixed DS.ScNonceKey (Ord.cmp_SCNonceKey x y)
    | x, y => pure (compare (scvalDisc x) (scvalDisc y))
/-- `Compare<Vec<ScVal>>` (compare.rs:51-67). -/
def cmpScVals : Nat → List SCVal → List SCVal → HostM Ordering
  | 0, _, _ => hostThrow .Context .InternalError
  | _ + 1, [], [] => pure .eq
  | _ + 1, [], _ => pure .lt
  | _ + 1, _, [] => pure .gt
  | fu + 1, x :: xs, y :: ys => do
    match ← cmpScVal fu x y with
    | .eq => cmpScVals fu xs ys
    | o => pure o
/-- `Compare<Vec<ScMapEntry>>` with `Compare<ScMapEntry>` (comparison.rs:217-225). -/
def cmpEntries : Nat → List SCMapEntry → List SCMapEntry → HostM Ordering
  | 0, _, _ => hostThrow .Context .InternalError
  | _ + 1, [], [] => pure .eq
  | _ + 1, [], _ => pure .lt
  | _ + 1, _, [] => pure .gt
  | fu + 1, x :: xs, y :: ys => do
    let o ← thenM (cmpScVal fu x.key y.key) fun _ => cmpScVal fu x.val y.val
    match o with
    | .eq => cmpEntries fu xs ys
    | o => pure o
end

/-- LedgerKey variant index (derived discriminant order). -/
def ledgerKeyDisc : LedgerKey → Nat
  | .ACCOUNT _ => 0 | .TRUSTLINE _ => 1 | .OFFER _ => 2 | .DATA _ => 3 | .CLAIMABLE_BALANCE _ => 4
  | .LIQUIDITY_POOL _ => 5 | .CONTRACT_DATA _ => 6 | .CONTRACT_CODE _ => 7 | .CONFIG_SETTING _ => 8
  | .TTL _ => 9

/-- `Storage::check_supported_ledger_key_type` (storage.rs:140-147). -/
def checkSupportedKey (k : LedgerKey) : HostM Unit :=
  match k with
  | .ACCOUNT _ | .TRUSTLINE _ | .CONTRACT_DATA _ | .CONTRACT_CODE _ => pure ()
  | _ => hostThrow .Storage .InternalError

/-- `Compare<LedgerKey> for Budget` (comparison.rs:330-357). -/
def cmpLedgerKey (a b : LedgerKey) : HostM Ordering := do
  checkSupportedKey a
  checkSupportedKey b
  match a, b with
  | .ACCOUNT x, .ACCOUNT y => cmpFixed 32 (Ord.cmp_LedgerKeyAccount x y)   -- DECLARED_SIZE LedgerKeyAccount = 32
  | .TRUSTLINE x, .TRUSTLINE y => cmpFixed 77 (Ord.cmp_LedgerKeyTrustLine x y)
  | .CONTRACT_DATA x, .CONTRACT_DATA y =>
      thenM (cmpScAddress x.contract y.contract) fun _ =>
      thenM (cmpScVal BIG x.key y.key) fun _ =>
      cmpDurability x.durability y.durability
  | .CONTRACT_CODE x, .CONTRACT_CODE y => cmpFixed DS.LedgerKeyContractCode (Ord.cmp_LedgerKeyContractCode x y)
  | x, y => pure (compare (ledgerKeyDisc x) (ledgerKeyDisc y))

end Soroban
