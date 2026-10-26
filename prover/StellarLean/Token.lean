import StellarLean.Query

/-
  The token contract of `TokenSpec.lean`, seen through `Query`: its storage
  layout (an `owner` variable and a `balance` map) and how each `Spec.Entry`
  turns into steps. `Spec.Entry` stands in for what a WASM → Lean converter
  would produce. Questions about it are in `TokenQuestions.lean`.
-/

namespace Token

open Query
open Spec (Addr Args St Eff Entry applyAll)

/-! ## The token's storage layout -/

def owner   : Term Addr := var "owner"
def balance : Map Int   := ⟨"balance"⟩

/-! ## From `Spec.Entry` (standing in for converted WASM) to steps -/

def _root_.Spec.St.store (s : St) : Storage
  | .var n     => if n = "owner" then .addr s.owner else .int 0
  | .entry m a => if m = "balance" then .int (s.bal a) else .int 0

def _root_.Spec.Entry.step (e : Entry) (s : St) (c : Addr) (a : Args) (s' : St) : Step where
  call   := { caller := c, args := a, holders := s.holders }
  pre    := s.store
  post   := s'.store
  writes := (e.effects c a).map fun x => .entry "balance" x.who

def _root_.Spec.Entry.exec (e : Entry) : Step → Prop := fun st =>
  ∃ s c a s', s.holders.Nodup ∧ e.run s c a = some s' ∧ st = e.step s c a s'

/-- Prove a question about `e.exec` one successful run at a time. -/
theorem _root_.Spec.Entry.models {e : Entry} {P : Question}
    (h : ∀ s c a s', s.holders.Nodup → e.run s c a = some s' → P (e.step s c a s')) :
    e.exec ⊨ P := by
  rintro _ ⟨s, c, a, s', hnd, hr, rfl⟩
  exact h s c a s' hnd hr

/-! Reading storage of a model state. -/

@[simp] theorem read_balance (s : St) (a : Addr) : balance.read s.store a = s.bal a := rfl
@[simp] theorem get_owner (c : Call) (s : St) : owner.get c s.store = s.owner := rfl
@[simp] theorem step_pre (e : Entry) (s : St) (c : Addr) (a : Args) (s' : St) :
    (e.step s c a s').pre = s.store := rfl
@[simp] theorem step_post (e : Entry) (s : St) (c : Addr) (a : Args) (s' : St) :
    (e.step s c a s').post = s'.store := rfl
@[simp] theorem step_call (e : Entry) (s : St) (c : Addr) (a : Args) (s' : St) :
    (e.step s c a s').call = { caller := c, args := a, holders := s.holders } := rfl

theorem applyAll_owner (s : St) (es : List Eff) : (applyAll s es).owner = s.owner := by
  induction es generalizing s with
  | nil => rfl
  | cons e es ih => exact ih _

theorem applyAll_holders (s : St) (es : List Eff) : (applyAll s es).holders = s.holders := by
  induction es generalizing s with
  | nil => rfl
  | cons e es ih => exact ih _

theorem holders_of_run {e : Entry} {s s' : St} {c : Addr} {a : Args}
    (h : e.run s c a = some s') : s'.holders = s.holders := by
  obtain ⟨_, rfl⟩ := Spec.Entry.run_some h
  exact applyAll_holders _ _

theorem total_store (c : Call) (s : St) (h : c.holders = s.holders) :
    balance.total.get c s.store = s.sum := by
  simp only [Map.total, h]
  rfl

theorem sum_zero_of_not_who (b : Addr) : ∀ es : List Eff, (∀ x ∈ es, b ≠ x.who) →
    (es.map fun x => if b = x.who then x.delta else 0).sum = 0
  | [], _ => rfl
  | x :: es, h => by
    have hx : b ≠ x.who := h x (List.mem_cons_self ..)
    have ih := sum_zero_of_not_who b es fun y hy => h y (List.mem_cons_of_mem _ hy)
    simp [hx, ih]

theorem _root_.Spec.Entry.step_framed {e : Entry} {s s' : St} {c : Addr} {a : Args}
    (h : e.run s c a = some s') : (e.step s c a s').Framed := by
  obtain ⟨_, rfl⟩ := Spec.Entry.run_some h
  intro k hk
  cases k with
  | var n => simp [Spec.Entry.step, Spec.St.store, applyAll_owner]
  | entry m b =>
    simp only [Spec.Entry.step, Spec.St.store]
    split
    · subst_vars
      rw [Spec.applyAll_bal,
        sum_zero_of_not_who b _ fun x hx hb => hk (List.mem_map.mpr ⟨x, hx, by rw [hb]⟩)]
      simp
    · rfl

theorem _root_.Spec.Entry.exec_framed (e : Entry) : ∀ st, e.exec st → st.Framed := by
  rintro _ ⟨_, _, _, _, _, h, rfl⟩
  exact Spec.Entry.step_framed h

/-- The token contract: its two entry points. -/
def token : Contract where
  entries := [Spec.transfer.exec, Spec.mint.exec]
  framed e he := by
    simp only [List.mem_cons, List.not_mem_nil, or_false] at he
    rcases he with rfl | rfl <;> exact Spec.Entry.exec_framed _

theorem token_cases {e : Step → Prop} (he : e ∈ token.entries) :
    e = Spec.transfer.exec ∨ e = Spec.mint.exec := by
  simpa [token] using he

end Token
