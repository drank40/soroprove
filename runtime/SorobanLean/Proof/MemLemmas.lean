/-
Reasoning about `LinMem` without evaluating it: a little-endian write read back at the
same place gives the value; reads of a range disjoint from a write are unaffected.
-/
import SorobanLean.Wasm.Runtime

namespace Wasm.LinMem

theorem get_set (m : LinMem) (a x : Nat) (b : UInt8) :
    (m.set a b).get x = if x = a then b else m.get x := by
  simp only [get, set]
  rw [Std.TreeMap.getElem?_insert]
  by_cases h : x = a
  · subst h; simp
  · have : compare a x ≠ .eq := by simpa [Nat.compare_eq_eq] using Ne.symm h
    simp [h, this]

theorem size_set (m : LinMem) (a : Nat) (b : UInt8) : (m.set a b).size = m.size := rfl

theorem size_writeLE (m : LinMem) (a n v : Nat) : (m.writeLE a n v).size = m.size := by
  induction n generalizing m a v with
  | zero => rfl
  | succ n ih => simp [writeLE, ih, size_set]

theorem get_writeLE_out (m : LinMem) (a n v x : Nat) (h : x < a ∨ a + n ≤ x) :
    (m.writeLE a n v).get x = m.get x := by
  induction n generalizing m a v with
  | zero => rfl
  | succ n ih =>
    simp only [writeLE]
    rw [ih _ _ _ (by omega), get_set]
    simp; omega

theorem readLE_congr (m m' : LinMem) (b k : Nat) (h : ∀ x, b ≤ x → x < b + k → m.get x = m'.get x) :
    m.readLE b k = m'.readLE b k := by
  induction k generalizing b with
  | zero => rfl
  | succ k ih =>
    simp only [readLE]
    rw [h b (Nat.le_refl _) (by omega), ih (b + 1) (fun x h1 h2 => h x (by omega) (by omega))]

/-- Reads of a range disjoint from a write are unaffected. -/
theorem readLE_writeLE_disj (m : LinMem) (a n v b k : Nat) (h : a + n ≤ b ∨ b + k ≤ a) :
    (m.writeLE a n v).readLE b k = m.readLE b k :=
  readLE_congr _ _ _ _ fun x h1 h2 => get_writeLE_out _ _ _ _ _ (by omega)

theorem readLE_lt (m : LinMem) (b k : Nat) : m.readLE b k < 256 ^ k := by
  induction k generalizing b with
  | zero => simp [readLE]
  | succ k ih =>
    simp only [readLE]
    have h1 := (m.get b).toNat_lt
    have h2 := ih (b + 1)
    rw [Nat.or_comm, ← Nat.shiftLeft_add_eq_or_of_lt (by exact h1), Nat.shiftLeft_eq, Nat.pow_succ]
    have : (m.readLE (b + 1) k) * 2 ^ 8 + (m.get b).toNat < 256 ^ k * 256 := by
      have : (m.readLE (b + 1) k) * 256 + 256 ≤ 256 ^ k * 256 := by
        have := Nat.mul_le_mul_right 256 (Nat.succ_le_of_lt h2); simpa [Nat.succ_mul] using this
      show _ * 256 + _ < _; omega
    exact this

/-- A write read back at the same place gives the value (mod `256^n`). -/
theorem readLE_writeLE_same (m : LinMem) (a n v : Nat) :
    (m.writeLE a n v).readLE a n = v % 256 ^ n := by
  induction n generalizing m a v with
  | zero => simp [readLE, Nat.mod_one]
  | succ n ih =>
    simp only [writeLE, readLE]
    rw [get_writeLE_out _ _ _ _ _ (by omega), get_set, if_pos rfl, ih]
    have hb : ((v % 256).toUInt8).toNat = v % 256 := by
      simp [Nat.toUInt8]
    rw [hb, Nat.or_comm, ← Nat.shiftLeft_add_eq_or_of_lt (Nat.mod_lt _ (by decide)), Nat.shiftLeft_eq,
      Nat.shiftRight_eq_div_pow, show (2:Nat) ^ 8 = 256 from rfl, Nat.pow_succ', Nat.mod_mul]
    rw [Nat.mul_comm]; omega

end Wasm.LinMem
