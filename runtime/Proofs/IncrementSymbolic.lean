/-
`increment` for every stored counter value: the real call1 input of corpus/e2e_increment.txt
with the instance entry's `COUNTER` value replaced by an arbitrary `c : UInt32`.
-/
import Proofs.Common

namespace Proofs
open Soroban

/-- Big-endian bytes of a `u32` (the XDR encoding of `uint32`). -/
def be32 (c : UInt32) : List UInt8 :=
  [(c >>> 24).toUInt8, (c >>> 16).toUInt8, (c >>> 8).toUInt8, c.toUInt8]

/-- The instance `LedgerEntry` bytes up to the counter value (from the real ledger entry). -/
def instancePrefix : List UInt8 := [0, 0, 3, 232, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 1, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 0, 0, 0, 20, 0, 0, 0, 1, 0, 0, 0, 19, 0, 0, 0, 0, 67, 222, 76, 81, 196, 20, 10, 68, 240, 174, 97, 137, 66, 190, 120, 167, 96, 221, 12, 183, 125, 195, 176, 191, 8, 8, 110, 117, 189, 145, 186, 102, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 15, 0, 0, 0, 7, 67, 79, 85, 78, 84, 69, 82, 0, 0, 0, 0, 3]

/-- The encoded instance entry holding `COUNTER ↦ U32 c` (then `ext = v0`). -/
def instanceEntry (c : UInt32) : ByteArray := ⟨(instancePrefix ++ be32 c ++ [0, 0, 0, 0]).toArray⟩

def incInput (c : UInt32) : E2EInput :=
  { call1Input with
    ledgerEntries := #[call1Input.ledgerEntries[0]!,
      (some (instanceEntry c), some { liveUntilLedger := 2000, entrySizeForRent := 132 })] }

/-- XDR of `ScVal::U32(v)`. -/
def u32ScVal (v : UInt32) : ByteArray := ⟨([0, 0, 0, 3] ++ be32 v).toArray⟩

set_option maxRecDepth 200000
/-- Sanity: for `c = 1` this is exactly the oracle's call1. -/
theorem incInput_one_result : resultBytes? (incInput 1) = some (u32ScVal 2) := by decide +kernel

theorem incInput_one_resultU : resultBytesU? (incInput 1) = some (u32ScVal 2) := by decide +kernel

end Proofs
