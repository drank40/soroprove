/-
XDR runtime used by the generated codec, transcribing stellar-xdr 30.0.0
(src: vendor/crates/stellar-xdr-30.0.0/src/generated.rs).

Every reader/writer takes `fu` (fuel: Lean termination only) and `d` (remaining
depth, `Limits::depth`). Primitive reads are themselves wrapped in
`with_limited_depth` (:783-880), so they check `d = 0` as well.
-/
import SorobanLean.Xdr.Types

namespace Xdr

/-- src: generated.rs:120-250 (`pub enum Error`, the variants reachable when reading). -/
inductive Err where
  | invalid
  | lengthExceedsMax
  | nonZeroPadding
  | depthLimitExceeded
  | lengthLimitExceeded
  /-- `read_exact` hit the end of input (an `Io` error in stellar-xdr). -/
  | io
  /-- Lean-side fuel exhaustion; never produced by stellar-xdr. -/
  | fuel
  deriving DecidableEq, Repr, Inhabited

namespace Rt

/-- Reader: the remaining input (a list, so each byte costs O(1) also under kernel
    reduction) and the remaining length limit. -/
abbrev R (α : Type) := List UInt8 → Nat → Except Err (α × List UInt8 × Nat)

instance : Monad R where
  pure a := fun r l => .ok (a, r, l)
  bind m f := fun r l => match m r l with
    | .ok (a, r', l') => f a r' l'
    | .error e => .error e

@[inline] def rfail {α} (e : Err) : R α := fun _ _ => .error e
@[inline] def invalid {α} : R α := rfail .invalid
@[inline] def lengthExceedsMax {α} : R α := rfail .lengthExceedsMax
@[inline] def depthExceeded {α} : R α := rfail .depthLimitExceeded
@[inline] def fuelOut {α} : R α := rfail .fuel

/-- `consume_len` (:426-434). -/
@[inline] def consumeLen (n : Nat) : R Unit := fun r l =>
  if n ≤ l then .ok ((), r, l - n) else .error .lengthLimitExceeded

/-- `read_exact` of `n` bytes (an `Io` error if the input ends first). -/
@[inline] def readExactL (n : Nat) : R (List UInt8) := fun r l =>
  let t := r.take n
  if t.length = n then .ok (t, r.drop n, l) else .error .io

@[inline] def readExact (n : Nat) : R ByteArray := do pure ⟨(← readExactL n).toArray⟩

def beNatL (bs : List UInt8) : Nat := bs.foldl (fun acc x => acc * 256 + x.toNat) 0
def beNat (bs : ByteArray) : Nat := beNatL bs.data.toList

def padLen (n : Nat) : Nat := (4 - n % 4) % 4

/-- Read `n` big-endian bytes as a primitive inside its own `with_limited_depth`. -/
@[inline] def rdPrim (n : Nat) (d : Nat) : R Nat :=
  match d with
  | 0 => depthExceeded
  | _ + 1 => do consumeLen n; let bs ← readExactL n; pure (beNatL bs)

def rdU32 (_fu d : Nat) : R UInt32 := do pure (← rdPrim 4 d).toUInt32
def rdI32 (_fu d : Nat) : R Int32 := do pure (← rdPrim 4 d).toUInt32.toInt32
def rdU64 (_fu d : Nat) : R UInt64 := do pure (← rdPrim 8 d).toUInt64
def rdI64 (_fu d : Nat) : R Int64 := do pure (← rdPrim 8 d).toUInt64.toInt64

/-- bool (:903-911): `u32::read_xdr` nested in its own depth level; `true` iff the value is 1. -/
def rdBool (fu d : Nat) : R Bool :=
  match d with
  | 0 => depthExceeded
  | d + 1 => do let i ← rdU32 fu d; pure (i == 1)

/-- Zero padding check (:996, :2022, :2496). -/
def rdPad (n : Nat) : R Unit := do
  let pad ← readExactL (padLen n)
  if pad.all (· == 0) then pure () else rfail .nonZeroPadding

/-- `[u8; N]` (:984-1003). -/
def rdOpaqueFixed (n : Nat) (_fu d : Nat) : R ByteArray :=
  match d with
  | 0 => depthExceeded
  | _ + 1 => do
    consumeLen n
    consumeLen (padLen n)
    let bs ← readExact n
    rdPad n
    pure bs

/-- `BytesM<MAX>` / `StringM<MAX>` / `VecM<u8, MAX>` (:1523-1548, :2003-2027, :2477-2501). -/
def rdOpaqueVar (mx : Nat) (fu d : Nat) : R ByteArray :=
  match d with
  | 0 => depthExceeded
  | d + 1 => do
    let n := (← rdU32 fu d).toNat
    if n > mx then lengthExceedsMax else do
    consumeLen n
    consumeLen (padLen n)
    let bs ← readExact n
    rdPad n
    pure bs

/-! ## Writers -/

/-- Output of a writer: the bytes and the sizes of the individual non-empty
    `write_all` calls that produced them (a metered writer charges per call,
    soroban-env-host/src/host/metered_xdr.rs:16-31). -/
structure WBuf where
  /-- Output bytes, most recent first (appending a chunk is O(chunk)). -/
  rev : List UInt8 := []
  /-- Sizes of the write calls, most recent first. -/
  revChunks : List Nat := []
  deriving Inhabited

def WBuf.bytes (b : WBuf) : ByteArray := ⟨b.rev.reverse.toArray⟩
def WBuf.chunks (b : WBuf) : Array Nat := b.revChunks.reverse.toArray

/-- Writer: appends to an output buffer, tracking the remaining length limit. On
    error the buffer written so far is returned too. -/
abbrev W := WBuf → Nat → Except (Err × WBuf) (WBuf × Nat)

@[inline] def wNil : W := fun b l => .ok (b, l)
@[inline] def wFail (e : Err) : W := fun b _ => .error (e, b)
@[inline] def wInvalid : W := wFail .invalid
@[inline] def wLengthExceedsMax : W := wFail .lengthExceedsMax
@[inline] def wDepthExceeded : W := wFail .depthLimitExceeded
@[inline] def wFuelOut : W := wFail .fuel

def wSeq : List W → W
  | [] => wNil
  | x :: xs => fun b l => match x b l with
    | .ok (b', l') => wSeq xs b' l'
    | .error e => .error e

@[inline] def wConsume (n : Nat) : W := fun b l =>
  if n ≤ l then .ok (b, l - n) else .error (.lengthLimitExceeded, b)

/-- One `write_all`; empty slices issue no `write` call. -/
@[inline] def wBytes (bs : ByteArray) : W := fun b l =>
  .ok ({ rev := bs.data.toList.reverseAux b.rev,
         revChunks := if bs.size = 0 then b.revChunks else bs.size :: b.revChunks }, l)

def beBytes (n v : Nat) : ByteArray := ByteArray.mk <| (List.range n).reverse.toArray.map fun i => ((v >>> (8 * i)) % 256).toUInt8

@[inline] def wrPrim (n : Nat) (d : Nat) (v : Nat) : W :=
  match d with
  | 0 => wDepthExceeded
  | _ + 1 => wSeq [wConsume n, wBytes (beBytes n v)]

def wrU32 (_fu d : Nat) (x : UInt32) : W := wrPrim 4 d x.toNat
def wrI32 (_fu d : Nat) (x : Int32) : W := wrPrim 4 d x.toUInt32.toNat
def wrU64 (_fu d : Nat) (x : UInt64) : W := wrPrim 8 d x.toNat
def wrI64 (_fu d : Nat) (x : Int64) : W := wrPrim 8 d x.toUInt64.toNat

def wrBool (fu d : Nat) (x : Bool) : W :=
  match d with
  | 0 => wDepthExceeded
  | d + 1 => wrU32 fu d (if x then 1 else 0)

def zeros (n : Nat) : ByteArray := ByteArray.mk (Array.replicate n 0)

def wrOpaqueFixed (n : Nat) (_fu d : Nat) (x : ByteArray) : W :=
  match d with
  | 0 => wDepthExceeded
  | _ + 1 => if x.size != n then wInvalid else
      wSeq [wConsume n, wConsume (padLen n), wBytes x, wBytes (zeros (padLen n))]

def wrOpaqueVar (mx : Nat) (fu d : Nat) (x : ByteArray) : W :=
  match d with
  | 0 => wDepthExceeded
  | d + 1 => if x.size > mx then wLengthExceedsMax else
      wSeq [wrU32 fu d x.size.toUInt32, wConsume x.size, wConsume (padLen x.size), wBytes x, wBytes (zeros (padLen x.size))]

end Rt

/-- Limits used by the Soroban host (src: soroban-env-host/src/budget/limits.rs:12-15). -/
def DEFAULT_DEPTH : Nat := 500
def DEFAULT_LEN : Nat := 32 * 1024 * 1024

/-- Fuel that is never exhausted by inputs within the length limit. -/
def BIG_FUEL : Nat := 2 ^ 40

/-- `read_xdr_to_end` (generated.rs:601-611): all bytes must be consumed. -/
def decodeToEnd {α} (rd : Nat → Nat → Rt.R α) (b : ByteArray) (depth := DEFAULT_DEPTH) (len := DEFAULT_LEN) :
    Except Err α :=
  match rd BIG_FUEL depth b.data.toList len with
  | .ok (a, r, _) => if r.isEmpty then .ok a else .error .invalid
  | .error e => .error e

def encode {α} (wr : Nat → Nat → α → Rt.W) (x : α) (depth := DEFAULT_DEPTH) (len := DEFAULT_LEN) :
    Except Err ByteArray :=
  match wr BIG_FUEL depth x {} len with
  | .ok (b, _) => .ok b.bytes
  | .error (e, _) => .error e

/-- Like `encode`, also returning the write-call chunk sizes (partial on error). -/
def encodeChunks {α} (wr : Nat → Nat → α → Rt.W) (x : α) (depth := DEFAULT_DEPTH) (len := DEFAULT_LEN) :
    Except (Err × Array Nat) (ByteArray × Array Nat) :=
  match wr BIG_FUEL depth x {} len with
  | .ok (b, _) => .ok (b.bytes, b.chunks)
  | .error (e, b) => .error (e, b.chunks)

end Xdr
