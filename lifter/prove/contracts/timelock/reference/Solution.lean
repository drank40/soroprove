import Spec.Defs

open Contract Spec

namespace Locked

/-- The inductive invariant behind `claim_at_most_once`. -/
def Inv (tr : List Step) (t : Storage) : Prop :=
  (calls "deposit" tr = 0 ∧ calls "claim" tr = 0 ∧ t (.has (.var "Init")) ≠ 1 ∧
      t (.has (.var "Balance")) ≠ 1) ∨
  (calls "deposit" tr = 1 ∧ t (.has (.var "Init")) = 1 ∧
    ((calls "claim" tr = 0 ∧ t (.has (.var "Balance")) = 1) ∨
     (calls "claim" tr = 1 ∧ t (.has (.var "Balance")) ≠ 1)))

theorem inv_run : ∀ pool s tr t, Run pool s tr t → ¬ initialized s → ¬ funded s → Inv tr t := by
  intro pool s tr t h hi hf
  induction h with
  | nil => exact Or.inl ⟨rfl, rfl, hi, hf⟩
  | cons st _ _ _ he ih =>
    simp only [entries, List.mem_cons, List.not_mem_nil, or_false] at he
    obtain ⟨e, he, hst⟩ := he
    rcases he with rfl | rfl
    · obtain ⟨u, hs⟩ := hst
      have hfn := hs.fn
      have hpost := hs.post
      have hg : st.pre (.has (.var "Balance")) = 1 := hs.gate1
      have hI : st.post (.has (.var "Init")) = st.pre (.has (.var "Init")) := by
        rw [hpost, claim.s2, Storage.set_get, if_neg (by simp), claim.s1,
          xfer_other _ _ _ _ _ _ (by intros; simp)]
      have hB : st.post (.has (.var "Balance")) = 0 := by
        rw [hpost, claim.s2, Storage.set_get, if_pos (by simp)]
      have e1 : ("claim" == "deposit") = false := by decide
      simp only [Inv, calls, List.countP_cons, hfn, hI, hB, e1, beq_self_eq_true] at ih ⊢
      simp only [if_true, Bool.false_eq_true, if_false] at ⊢
      omega
    · obtain ⟨u, hs⟩ := hst
      have hfn := hs.fn
      have hpost := hs.post
      have hg : st.pre (.has (.var "Init")) ≠ 1 := hs.gate2
      have hI : st.post (.has (.var "Init")) = 1 := by
        rw [hpost, deposit.s3, Storage.set_get, if_pos (by simp)]
      have hB : st.post (.has (.var "Balance")) = 1 := by
        rw [hpost, deposit.s3, Storage.set_get, if_neg (by simp), Storage.set_get,
          if_neg (by simp), deposit.s2, Storage.set_get, if_pos (by simp)]
      have e1 : ("deposit" == "claim") = false := by decide
      simp only [Inv, calls, List.countP_cons, hfn, hI, hB, e1, beq_self_eq_true] at ih ⊢
      simp only [if_true, Bool.false_eq_true, if_false] at ⊢
      rcases ih with ⟨h1, h2, -, -⟩ | ⟨-, h2, -⟩
      · exact Or.inr ⟨by omega, trivial, Or.inl ⟨by omega, trivial⟩⟩
      · exact absurd h2 hg

/-- Pays out once: from a fresh contract, any sequence of calls has at most one deposit and
    at most as many claims as deposits. -/
theorem claim_at_most_once : ∀ pool s tr t, Run pool s tr t → ¬ initialized s → ¬ funded s →
    calls "deposit" tr ≤ 1 ∧ calls "claim" tr ≤ calls "deposit" tr := by
  intro pool s tr t h hi hf
  have := inv_run pool s tr t h hi hf
  simp only [Inv] at this
  omega

/-- `claim` needs the claimant's signature and pays them exactly the recorded amount in the
    recorded token. -/
theorem claim_pays_recorded : ∀ st, claim st → st.call.argA "claimant" ≠ st.call.self →
    st.call.argA "claimant" ∈ st.call.signers ∧
    bal (st.pre (.fld (.var "Balance") "token")) st.post (st.call.argA "claimant") =
      bal (st.pre (.fld (.var "Balance") "token")) st.pre (st.call.argA "claimant") +
        st.pre (.fld (.var "Balance") "amount") := by
  intro st ⟨u, hs⟩ hne
  refine ⟨hs.auth_claimant, ?_⟩
  rw [hs.post, claim.s2, bal_set _ _ _ _ _ (by intros; simp), claim.s1, bal_xfer]
  simp [hne]

/-- NON-VACUITY: a claim paying a positive amount can happen. -/
theorem claim_live :
    ∃ st, claim st ∧ 0 < st.pre (.fld (.var "Balance") "amount") := by
  let c : Call := ⟨"claim", 0, 1, fun _ => 0, fun _ => 2, [2], fun _ => 0⟩
  let pre : Storage := fun _ => 1
  let st : Step := ⟨c, pre, claim.s2 ⟨c, pre, pre, [], 0⟩,
    [.bal 1 1, .bal 1 2, .has (.var "Balance")], 2⟩
  refine ⟨st, ⟨⟨(fun _ => 0), (fun n => if n = 2 then 1 else 0), (fun _ => false),
    (fun _ => .var ""), (fun _ => fun _ => 0)⟩, ?_⟩, ?_⟩
  · refine ⟨rfl, ?_, ?_, ?_, rfl, ?_, rfl, rfl, rfl⟩ <;> simp [st, c, pre, xferOk, bal]
  · simp [st, pre]

end Locked
