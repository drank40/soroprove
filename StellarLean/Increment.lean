import StellarLean.Query

/-
  Soroban's increment example, translated by hand the way a WASM → Lean
  converter would describe it, plus questions about it.

    const COUNTER: Symbol = symbol_short!("COUNTER");

    pub fn increment(env: Env) -> u32 {
        let mut count: u32 = env.storage().instance().get(&COUNTER).unwrap_or(0);
        log!(&env, "count: {}", count);
        count += 1;
        env.storage().instance().set(&COUNTER, &count);
        count
    }
-/

namespace Increment

open Query
open Spec (Addr)

/-! ## The contract -/

/-- `const COUNTER: Symbol = symbol_short!("COUNTER")`, an instance-storage variable. -/
def COUNTER : Term Int := var "COUNTER"

def U32_MAX : Int := 4294967295

/-- The step size: `count += 1`. -/
def one : Call → Int := fun _ => 1

/-- `get(&COUNTER).unwrap_or(0)`: an unset slot reads as 0. -/
def count (s : Storage) : Int := Query.read s "COUNTER"

/-- `pub fn increment(env: Env) -> u32`, as the steps it can take.
    * `log!` emits an event and does not touch storage, so it does not appear.
    * `count += 1` panics on overflow (Soroban contracts build with overflow
      checks), and a panic means the call fails: there is no step. -/
def increment : Step → Prop := fun st =>
  count st.pre < U32_MAX ∧                                         -- `count += 1` does not overflow
  st.writes = [.var "COUNTER"] ∧                                   -- `set(&COUNTER, …)`
  st.post = st.pre.set (.var "COUNTER") (.int (count st.pre + 1)) ∧
  st.ret = .int (count st.pre + 1)                                 -- returns `count`

def contract : Contract where
  entries := [increment]
  framed e he st h k hk := by
    simp only [List.mem_cons, List.not_mem_nil, or_false] at he
    subst he
    obtain ⟨-, hw, hp, -⟩ := h
    have : k ≠ .var "COUNTER" := by simpa [hw] using hk
    simp [hp, Storage.set, this]

/-! ## Facts used by the answers (see `IncrementQuestions.lean`) -/

theorem contract_models {P : Question} (h : ∀ st, increment st → P st) : contract ⊨ P := by
  intro e he
  simp only [contract, List.mem_cons, List.not_mem_nil, or_false] at he
  subst he
  exact h

@[simp] theorem get_COUNTER (c : Call) (s : Storage) : COUNTER.get c s = count s := rfl

theorem count_after {st : Step} (h : increment st) : count st.post = count st.pre + 1 := by
  obtain ⟨-, -, hp, -⟩ := h
  simp [hp, count, Query.read, Storage.set]

end Increment
