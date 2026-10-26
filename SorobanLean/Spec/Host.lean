/-
The proof host: the Soroban host functions a contract imports, over plain state.

Each function is transcribed from the full host model (SorobanLean/Host/Fns/*.lean, which
cites soroban-env-host) with these abstractions, all in the direction of "fewer details",
never different results on the paths kept:

* no metering, and every host error is the single trap `()` (the frame is rolled back, so
  partial effects are not observable);
* values are kept canonically (`CVal`), keyed by value as the host's `Compare` does; a
  stored value comes back small when it fits, as after an XDR round trip (the full host
  returns instance-storage and map values in their original representation; Soroban SDK
  decoders accept both, so SDK-generated contracts cannot tell);
* storage is three maps; footprint and TTL liveness are assumed (entries are present or
  absent), so `extend_*_ttl` only performs its argument checks;
* `require_auth a` succeeds iff `authOk a` (whatever the transaction's signatures are),
  and is logged;
* events are logged unconverted.

Object kinds the token-style contracts here do not use (timepoint, duration, 256-bit,
executable tags) are unsupported and trap.
-/
import SorobanLean.Wasm.Exec
import SorobanLean.Host.Symbol
import SorobanLean.Env.HostFns

namespace Soroban.SHost
open Wasm

structure Addr where
  /-- 0 = account (ed25519 key), 1 = contract. -/
  kind : Nat
  id : List UInt8
  deriving DecidableEq, Inhabited

mutual
inductive CVal where
  /-- A non-object `Val` other than the kinds below (bool, void, error, u32, i32, ...). -/
  | small (payload : UInt64)
  | u64 (n : Nat)
  | i64 (i : Int)
  | u128 (n : Nat)
  | i128 (i : Int)
  | sym (b : List UInt8)
  | bytes (b : List UInt8)
  | str (b : List UInt8)
  | addr (a : Addr)
  | muxed (a : Addr) (id : Nat)
  | vec (xs : CList)
  | map (m : CMap)
inductive CList where
  | nil
  | cons (h : CVal) (t : CList)
inductive CMap where
  | nil
  | cons (k v : CVal) (t : CMap)
end

mutual
def CVal.beq : CVal → CVal → Bool
  | .small a, .small b => a == b
  | .u64 a, .u64 b | .u128 a, .u128 b => a == b
  | .i64 a, .i64 b | .i128 a, .i128 b => a == b
  | .sym a, .sym b | .bytes a, .bytes b | .str a, .str b => a == b
  | .addr a, .addr b => a == b
  | .muxed a i, .muxed b j => a == b && i == j
  | .vec a, .vec b => CList.beq a b
  | .map a, .map b => CMap.beq a b
  | _, _ => false
def CList.beq : CList → CList → Bool
  | .nil, .nil => true
  | .cons h t, .cons h' t' => CVal.beq h h' && CList.beq t t'
  | _, _ => false
def CMap.beq : CMap → CMap → Bool
  | .nil, .nil => true
  | .cons k v t, .cons k' v' t' => CVal.beq k k' && CVal.beq v v' && CMap.beq t t'
  | _, _ => false
end

instance : BEq CVal := ⟨CVal.beq⟩
instance : Inhabited CVal := ⟨.small 0⟩

def CList.ofList : List CVal → CList
  | [] => .nil
  | x :: xs => .cons x (ofList xs)
def CMap.toList : CMap → List (CVal × CVal)
  | .nil => []
  | .cons k v t => (k, v) :: t.toList
def CMap.ofList : List (CVal × CVal) → CMap
  | [] => .nil
  | (k, v) :: t => .cons k v (ofList t)

def VOIDc : CVal := .small Val.VOID.payload

/-- Host-object tag of a value that lives in the object table. -/
def CVal.objTag : CVal → Option Tag
  | .u64 _ => some .U64Object | .i64 _ => some .I64Object
  | .u128 _ => some .U128Object | .i128 _ => some .I128Object
  | .sym _ => some .SymbolObject | .bytes _ => some .BytesObject | .str _ => some .StringObject
  | .addr _ => some .AddressObject | .muxed .. => some .MuxedAddressObject
  | .vec _ => some .VecObject | .map _ => some .MapObject
  | .small _ => none

structure SH where
  /-- The frame's relative object table: guest handle `2 i` is entry `i`. -/
  objs : Array CVal := #[]
  inst : List (CVal × CVal) := []
  pers : List (CVal × CVal) := []
  temp : List (CVal × CVal) := []
  /-- Ledger sequence number. -/
  seq : Nat
  /-- `max_live_until_ledger - seq`: the largest TTL extension of a temporary entry. -/
  maxTtl : Nat
  authOk : Addr → Bool
  authed : List Addr := []
  events : List (CVal × CVal) := []

/-! ## Values across the boundary -/

/-- `relative_to_absolute` + `check_val_integrity` (Host/Core.lean, Host/Conv.lean). -/
def decode (s : SH) (v : Val) : Option CVal :=
  if !v.isGood then none else
  if v.isObject then
    let h := v.getMajor
    if h % 2 != 0 then none else
    match s.objs[h.toNat / 2]? with
    | some o => if o.objTag == some v.getTag then some o else none
    | none => none
  else match v.getTag with
    | .U64Small => some (.u64 v.getBody.toNat)
    | .I64Small => some (.i64 v.getSignedBody.toInt)
    | .U128Small => some (.u128 v.getBody.toNat)
    | .I128Small => some (.i128 v.getSignedBody.toInt)
    | .SymbolSmall => some (.sym (symbolSmallBytes v.getBody).toList)
    | .TimepointSmall | .DurationSmall | .U256Small | .I256Small => none
    | _ => some (.small v.payload)

/-- `add_host_object` + `absolute_to_relative`: a new relative handle. -/
def push (s : SH) (o : CVal) : Option (Val × SH) := do
  let t ← o.objTag
  let i := s.objs.size
  if i * 2 ≥ 2^32 then none
  pure (Val.fromMajorMinorAndTag (UInt32.ofNat (i * 2)) 0 t, { s with objs := s.objs.push o })

/-- A value handed back to the guest, small when it fits (`TryFromVal<ScVal> for Val`). -/
def materialize (s : SH) : CVal → Option (Val × SH)
  | .small p => some (⟨p⟩, s)
  | .u64 n => if isSmallU64 n then some (Val.fromBodyAndTag (UInt64.ofNat n) .U64Small, s) else push s (.u64 n)
  | .i64 i => if isSmallI64 i then some (Val.fromBodyAndTag (Int64.ofInt i).toUInt64 .I64Small, s) else push s (.i64 i)
  | .u128 n => if isSmallU64 n then some (Val.fromBodyAndTag (UInt64.ofNat n) .U128Small, s) else push s (.u128 n)
  | .i128 i => if isSmallI64 i then some (Val.fromBodyAndTag (Int64.ofInt i).toUInt64 .I128Small, s) else push s (.i128 i)
  | .sym b => match SymbolSmall.tryFromBytes b with
    | some body => some (Val.fromBodyAndTag body .SymbolSmall, s)
    | none => push s (.sym b)
  | o => push s o

/-! ## Storage -/

def lookup (m : List (CVal × CVal)) (k : CVal) : Option CVal := (m.find? (·.1 == k)).map (·.2)

def insert (m : List (CVal × CVal)) (k v : CVal) : List (CVal × CVal) :=
  if (m.find? (·.1 == k)).isSome then m.map fun e => if e.1 == k then (k, v) else e else m ++ [(k, v)]

inductive SType | temporary | persistent | inst
  deriving DecidableEq

/-- `StorageType::from(u64)` after `try_marshal` restricted it to 0..2. -/
def SType.ofRaw (x : UInt64) : SType := match x with | 0 => .temporary | 1 => .persistent | _ => .inst

def SH.store (s : SH) : SType → List (CVal × CVal)
  | .temporary => s.temp | .persistent => s.pers | .inst => s.inst

def SH.setStore (s : SH) (t : SType) (m : List (CVal × CVal)) : SH :=
  match t with
  | .temporary => { s with temp := m } | .persistent => { s with pers := m } | .inst => { s with inst := m }

/-! ## Linear memory (Host/Fns/Mem.lean) -/

def leU64 (m : LinMem) (a : Nat) : UInt64 := UInt64.ofNat (m.readLE a 8)

def readVals (s : SH) (m : LinMem) (pos len : Nat) : Option (List CVal) := do
  let byteLen := len * 8
  if byteLen ≥ 2^32 then none
  if pos + byteLen ≥ 2^32 then none
  if pos + byteLen > m.size then none
  (List.range len).mapM fun i => decode s ⟨leU64 m (pos + 8 * i)⟩

/-- `scan_linear_memory_slice` + the bounds check of `metered_vm_scan_slices_in_linear_memory`. -/
def sliceBytes (m : LinMem) (pos i : Nat) : Option (List UInt8) := do
  let sp := pos + i * 8
  if sp + 8 > m.size then none
  let p := m.readLE sp 4
  let l := m.readLE (sp + 4) 4
  if p + l ≥ 2^32 then none
  if p + l > m.size then none
  pure (m.readBytes p l).toList

/-- `ScSymbol::try_from_bytes`. -/
def symOk (b : List UInt8) : Bool := b.length ≤ Xdr.SCSYMBOL_LIMIT && b.all fun x => (SymbolSmall.encodeByte x).isSome

/-- `symbol_from_bytes`: small if possible, else a checked symbol object (same value). -/
def symbolFromBytes (b : List UInt8) : Option CVal :=
  if (SymbolSmall.tryFromBytes b).isSome || symOk b then some (.sym b) else none

/-- Symbols compare by their bytes (`compare_to_small` / `lexBytes`). -/
def symLt : CVal → CVal → Bool
  | .sym a, .sym b => compare a b == .lt
  | _, _ => false

def strictlyIncreasing : List CVal → Bool
  | a :: b :: t => symLt a b && strictlyIncreasing (b :: t)
  | _ => true

/-- `write_vals_to_linear_memory`, element by element. -/
def writeVals (s : SH) (m : LinMem) (pos : Nat) (vs : List CVal) : Option (SH × LinMem) := do
  let byteLen := vs.length * 8
  if byteLen ≥ 2^32 then none
  if pos + byteLen ≥ 2^32 then none
  if pos + byteLen > m.size then none
  let (s, m, _) ← vs.foldlM (fun (s, m, i) v => do
      let (r, s) ← materialize s v
      pure (s, m.writeLE (pos + 8 * i) 8 r.payload.toNat, i + 1)) (s, m, 0)
  pure (s, m)

/-- `map_unpack_impl` with `sparse = true` (data_helper.rs:846-951). -/
def sparseUnpack (entries : List (CVal × CVal)) (keys : List (List UInt8)) : Option (List CVal) := do
  let rec go : List (List UInt8) → Option (List UInt8) → List (CVal × CVal) → Option (List CVal)
    | [], _, rest => if rest.all (fun e => match e.1 with | .sym _ => true | _ => false) then some [] else none
    | k :: ks, prev, es => do
      if let some p := prev then if compare p k != .lt then none
      let rec scan : List (CVal × CVal) → Option (CVal × List (CVal × CVal))
        | [] => some (VOIDc, [])
        | (mk, mv) :: es => match mk with
          | .sym b => match compare b k with
            | .lt => scan es
            | .eq => some (mv, es)
            | .gt => some (VOIDc, (mk, mv) :: es)
          | _ => none
      let (v, es) ← scan es
      let vs ← go ks (some k) es
      pure (v :: vs)
  go keys none entries

/-! ## The host functions -/

abbrev R := Res Unit (Store × SH) (List Value × Store × SH)

def ok (v : Val) (st : Store) (s : SH) : R := .ok ([.i64 v.payload], st, s)
def trap (st : Store) (s : SH) : R := .trap (.host ()) (st, s)
def ofOpt (st : Store) (s : SH) : Option (Val × SH) → R
  | some (v, s') => ok v st s'
  | none => trap st s

def u32Of (x : UInt64) : Nat := (Val.getMajor ⟨x⟩).toNat

/-- `f` applied to raw argument payloads that passed `try_marshal_from_relative_value`. -/
def impl (f : Env.HostFn) (a : Array UInt64) (st : Store) (s : SH) : R :=
  let v (i : Nat) : Option CVal := decode s ⟨a[i]!⟩
  match f with
  | .put_contract_data => ofOpt st s do
      let k ← v 0; let x ← v 1; let t := SType.ofRaw a[2]!
      pure (Val.VOID, s.setStore t (insert (s.store t) k x))
  | .has_contract_data => ofOpt st s do
      let k ← v 0
      pure (Val.fromBool (lookup (s.store (SType.ofRaw a[1]!)) k).isSome, s)
  | .get_contract_data => ofOpt st s do
      let k ← v 0
      let x ← lookup (s.store (SType.ofRaw a[1]!)) k
      materialize s x
  | .extend_contract_data_ttl => ofOpt st s do
      let k ← v 0; let t := SType.ofRaw a[1]!
      let thr := u32Of a[2]!; let ext := u32Of a[3]!
      if t == .inst || thr > ext then none
      if (lookup (s.store t) k).isNone then none
      if t == .temporary && ext > s.maxTtl then none
      pure (Val.VOID, s)
  | .extend_current_contract_instance_and_code_ttl => ofOpt st s do
      if u32Of a[0]! > u32Of a[1]! then none
      pure (Val.VOID, s)
  | .require_auth => ofOpt st s do
      let .addr x ← v 0 | none
      if !s.authOk x then none
      pure (Val.VOID, { s with authed := s.authed ++ [x] })
  | .contract_event => ofOpt st s do
      let t ← v 0; let d ← v 1
      pure (Val.VOID, { s with events := s.events ++ [(t, d)] })
  | .get_ledger_sequence => ok (Val.fromU32 (UInt32.ofNat s.seq)) st s
  | .obj_from_u64 => ofOpt st s (push s (.u64 a[0]!.toNat))
  | .obj_to_u64 => ofOpt st s do
      let .u64 n ← v 0 | none
      pure (⟨UInt64.ofNat n⟩, s)
  | .obj_from_i128_pieces => ofOpt st s (push s (.i128 (a[0]!.toInt64.toInt * 2^64 + a[1]!.toNat)))
  | .obj_to_i128_lo64 => ofOpt st s do
      let .i128 i ← v 0 | none
      pure (⟨UInt64.ofNat (Int.emod i (2^64)).toNat⟩, s)
  | .obj_to_i128_hi64 => ofOpt st s do
      let .i128 i ← v 0 | none
      pure (⟨(Int64.ofInt (Int.ediv i (2^64))).toUInt64⟩, s)
  | .get_address_from_muxed_address => ofOpt st s do
      let .muxed x _ ← v 0 | none
      push s (.addr x)
  | .get_id_from_muxed_address => ofOpt st s do
      let .muxed _ id ← v 0 | none
      materialize s (.u64 id)
  | .vec_new_from_linear_memory => ofOpt st s do
      let xs ← readVals s st.mem (u32Of a[0]!) (u32Of a[1]!)
      push s (.vec (CList.ofList xs))
  | .symbol_new_from_linear_memory => ofOpt st s do
      let pos := u32Of a[0]!; let len := u32Of a[1]!
      if pos + len > st.mem.size then none
      let b := (st.mem.readBytes pos len).toList
      if !symOk b then none
      push s (.sym b)
  | .map_new_from_linear_memory | .sparse_map_new_from_linear_memory => ofOpt st s do
      let sparse := f == .sparse_map_new_from_linear_memory
      let len := u32Of a[2]!
      let keys ← (List.range len).mapM fun i => do symbolFromBytes (← sliceBytes st.mem (u32Of a[0]!) i)
      let vals ← readVals s st.mem (u32Of a[1]!) len
      if !strictlyIncreasing keys then none
      let kvs := (keys.zip vals).filter fun (_, x) => !sparse || !(x == VOIDc)
      push s (.map (CMap.ofList kvs))
  | .sparse_map_unpack_to_linear_memory =>
      match (do
        let .map m ← v 0 | none
        let len := u32Of a[3]!
        let keys ← (List.range len).mapM fun i => sliceBytes st.mem (u32Of a[1]!) i
        let vals ← sparseUnpack m.toList keys
        writeVals s st.mem (u32Of a[2]!) vals) with
      | some (s', mem) => ok Val.VOID { st with mem } s'
      | none => trap st s
  | _ => trap st s

/-- The interface given to the Wasm interpreter for a module whose imports are `imports`:
    arguments are marshalled per env.json (`try_marshal_from_relative_value`). -/
def iface (imports : Array Env.HostFn) : HostIface SH Unit where
  call _ fi args st s :=
    match imports[fi]? with
    | none => .trap (.code .UnreachableCodeReached) (st, s)
    | some f =>
      let raws := args.map fun | .i64 x => x | .i32 x => x.toUInt64
      if (f.args.map (·.2)).zip raws |>.all (fun (t, x) => t.tryMarshal x) then impl f raws.toArray st s
      else trap st s
  memoryGrowing _ _ _ s := .ok (true, s)

end Soroban.SHost

namespace Soroban.SHost
/-- An applied host call, for rewriting without unfolding `iface` everywhere. -/
theorem iface_call (imports : Array Env.HostFn) (g fi : Nat) (args : List Wasm.Value) (st : Wasm.Store) (s : SH) :
    (iface imports).call g fi args st s =
      match imports[fi]? with
      | none => .trap (.code .UnreachableCodeReached) (st, s)
      | some f =>
        let raws := args.map fun | .i64 x => x | .i32 x => x.toUInt64
        if (f.args.map (·.2)).zip raws |>.all (fun (t, x) => t.tryMarshal x) then impl f raws.toArray st s
        else trap st s := rfl
end Soroban.SHost
