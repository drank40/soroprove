/-
The locked statements. A solution must prove theorems with exactly these names and types
(checked by `Check.lean`); it may add any lemmas of its own. Theorems marked PROBE are
expected to fail on the current model; they record a known limitation.
-/
import Spec.Defs

open Contract Spec

namespace Locked

/-- After an increment step, the counter is the old counter plus one. -/
theorem increment_counter (st : Step) (h : increment st) :
    counter st.post = counter st.pre + 1 := by
  obtain ⟨_, _, hpost, _, _⟩ := h
  rw [hpost]
  simp [counter, getOr0, Storage.set]

theorem step_counter (st : Step) (h : ∃ e ∈ entries, e st) :
    counter st.post = counter st.pre + 1 := by
  obtain ⟨e, he, hst⟩ := h
  simp [entries] at he
  subst he
  exact increment_counter st hst

/-- Across any sequence of calls the counter grows by exactly one per call. -/
theorem counts_calls : ∀ pool s tr t, Run pool s tr t → counter t = counter s + tr.length := by
  intro pool s tr t h
  induction h with
  | nil => simp
  | cons st _ _ _ he ih =>
    rw [step_counter st he, ih]
    simp; omega

/-- `increment` returns the new count. -/
theorem returns_new_count : ∀ st, increment st → st.ret = counter st.post := by
  intro st h
  rw [increment_counter st h]
  obtain ⟨_, _, _, _, hret⟩ := h
  rw [hret]
  rfl

/-- A concrete increment call from storage `s` (caller 1, contract at 0). -/
def mkStep (s : Storage) : Step where
  call := { fn := "increment", caller := 1, self := 0, arg := fun _ => 0,
            argA := fun _ => 0, signers := [], env := fun _ => 0 }
  pre := s
  post := (s.set (.var "COUNTER") (getOr0 s (.var "COUNTER") + 1)).set (.has (.var "COUNTER")) 1
  writes := [.var "COUNTER", .has (.var "COUNTER")]
  ret := getOr0 s (.var "COUNTER") + 1

theorem mkStep_inc (s : Storage) : increment (mkStep s) := by
  refine ⟨rfl, by simp [mkStep], rfl, rfl, rfl⟩

/-- `n` consecutive increments from `s`: the trace and the final storage. -/
def trace : Nat → Storage → List Step × Storage
  | 0, s => ([], s)
  | n + 1, s => let r := trace n s; (mkStep r.2 :: r.1, (mkStep r.2).post)

theorem trace_run (n : Nat) (s : Storage) : Run 0 s (trace n s).1 (trace n s).2 := by
  induction n with
  | zero => exact Run.nil s
  | succ n ih =>
    exact Run.cons (mkStep (trace n s).2) ih rfl (by simp [mkStep])
      ⟨increment, by simp [entries], mkStep_inc _⟩

theorem trace_len (n : Nat) (s : Storage) : (trace n s).1.length = n := by
  induction n with
  | zero => rfl
  | succ n ih => simp [trace, ih]

/-- PROBE (the u32 overflow trap is not modeled): from a fresh contract the counter stays
    within u32. -/
theorem counter_fits_u32 : ∀ pool s tr t, Run pool s tr t → counter s = 0 →
    counter t ≤ 4294967295 := sorry

/-- FALSE for this model: `increment` has no overflow guard (the u32 trap is not modeled),
    so 2^32 increments from all-zero storage reach a counter of 2^32. -/
theorem counter_fits_u32_false : ¬ (∀ pool s tr t, Run pool s tr t → counter s = 0 →
    counter t ≤ 4294967295) := by
  intro h
  have hr := trace_run 4294967296 (fun _ => 0)
  have h0 : counter (fun _ => 0) = 0 := by simp [counter, getOr0]
  have hc := counts_calls _ _ _ _ hr
  rw [trace_len, h0] at hc
  have := h _ _ _ _ hr h0
  omega

/-- NON-VACUITY: increment can run. -/
theorem increment_live :
    ∃ st, increment st := ⟨mkStep (fun _ => 0), mkStep_inc _⟩

end Locked
