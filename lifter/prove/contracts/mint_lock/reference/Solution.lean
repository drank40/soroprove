/-
The locked statements. A solution must prove theorems with exactly these names and types
(checked by `Check.lean`); it may add any lemmas of its own. Theorems marked PROBE are
expected to fail on the current model; they record a known limitation.
-/
import Spec.Defs

open Contract Spec

namespace Locked

/-- A mint succeeds only for a non-negative amount signed by the minter, who is the admin or
    a configured minter. -/
theorem mint_authorized : ∀ st, mint st →
    st.call.argA "minter" ∈ st.call.signers ∧ 0 ≤ st.call.arg "amount" ∧
    (admin st.pre = st.call.argA "minter" ∨
      st.pre (.has (minterKey (st.call.argA "contract") (st.call.argA "minter"))) = 1) := by
  rintro st ⟨u, h⟩
  have hok := h.ok
  refine ⟨h.auth_minter, ?_, ?_⟩
  · simp at hok; omega
  · simp [Spec.admin, minterKey] at hok ⊢
    rcases hok with ⟨_, h1⟩ | ⟨_, _, h2, _⟩
    · exact Or.inl h1
    · exact Or.inr h2

/-! ### Epoch limit -/

theorem mintedIn_cons (c m e : Int) (st : Step) (tr : List Step) :
    mintedIn c m e (st :: tr) =
      (if st.call.fn = "mint" ∧ st.call.argA "contract" = c ∧ st.call.argA "minter" = m ∧
          st.pre (.var "Admin") ≠ m ∧
          Int.tdiv (st.call.env "sequence") (st.pre (.fld (minterKey c m) "epoch_length")) = e
        then st.call.arg "amount" + mintedIn c m e tr else mintedIn c m e tr) := by
  unfold mintedIn
  simp only [List.filter_cons]
  by_cases h : st.call.fn = "mint" ∧ st.call.argA "contract" = c ∧ st.call.argA "minter" = m ∧
          st.pre (.var "Admin") ≠ m ∧
          Int.tdiv (st.call.env "sequence") (st.pre (.fld (minterKey c m) "epoch_length")) = e
  · obtain ⟨h1, h2, h3, h4, h5⟩ := h
    simp [h1, h2, h3, h4, h5]
  · rw [if_neg h]
    have : (st.call.fn == "mint" && st.call.argA "contract" == c &&
      st.call.argA "minter" == m && st.pre (.var "Admin") != m &&
      Int.tdiv (st.call.env "sequence") (st.pre (.fld (minterKey c m) "epoch_length")) == e)
        = false := by
      simp only [Bool.and_eq_false_iff, beq_eq_false_iff_ne, bne_eq_false_iff_eq, ne_eq]
      by_cases h1 : st.call.fn = "mint" <;> by_cases h2 : st.call.argA "contract" = c <;>
        by_cases h3 : st.call.argA "minter" = m <;> by_cases h4 : st.pre (.var "Admin") = m <;>
        simp_all
    rw [this]; rfl

theorem havoc_nonbal (s h : Storage) (k : Key) (hk : ∀ t a, k ≠ .bal t a) : havoc s h k = s k := by
  unfold havoc; split
  · exact absurd rfl (hk _ _)
  · rfl

theorem mint_post (st : Step) (u : Unk) (h : mint.Spec st u) (k : Key) (hk : ∀ t a, k ≠ .bal t a) :
    st.post k = mint.s1 st k := by
  rw [h.post]; unfold mint.s2; split
  · exact havoc_nonbal _ _ _ hk
  · rfl

/-- The inductive invariant behind `epoch_limit`: the minter's configuration is unchanged, and
    the stats entry for epoch `e` records exactly what was minted in it (and stays in the limit). -/
theorem epoch_inv (pool : Addr) (s : Storage) (c m e : Int) (hlim : 0 ≤ s (.fld (minterKey c m) "limit"))
    (hK : s (.has (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e)) ≠ 1) :
    ∀ tr t, Run pool s tr t →
    (∀ st ∈ tr, st.call.fn = "set_minter" →
      ¬(st.call.argA "contract" = c ∧ st.call.argA "minter" = m)) →
    t (.has (minterKey c m)) = s (.has (minterKey c m)) ∧
    t (.fld (minterKey c m) "limit") = s (.fld (minterKey c m) "limit") ∧
    t (.fld (minterKey c m) "epoch_length") = s (.fld (minterKey c m) "epoch_length") ∧
    mintedIn c m e tr = getOr0 t (.fld (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e)
      "consumed_limit") (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e) ∧
    getOr0 t (.fld (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e)
      "consumed_limit") (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e)
      ≤ s (.fld (minterKey c m) "limit") := by
  intro tr t hrun
  induction hrun with
  | nil =>
    intro _
    simp [mintedIn, getOr0, hK, hlim]
  | cons st hrun hself hfn hent ih =>
    intro hno
    obtain ⟨h1, h2, h3, h4, h5⟩ := ih (fun st' h' => hno st' (List.mem_cons_of_mem _ h'))
    have hno' := hno st List.mem_cons_self
    obtain ⟨en, hen, hst⟩ := hent
    simp only [entries, List.mem_cons, List.not_mem_nil, or_false] at hen
    rw [mintedIn_cons]
    rcases hen with rfl | rfl | rfl | rfl | rfl
    · have hf : st.call.fn ≠ "mint" := by rw [hst.fn]; decide
      rw [if_neg (fun h => hf h.1), hst.post]; exact ⟨h1, h2, h3, h4, h5⟩
    · obtain ⟨u, hst⟩ := hst
      have hok := hst.ok
      have hp := mint_post st u hst
      have hcfg : ∀ k, (k = .has (minterKey c m) ∨ k = .fld (minterKey c m) "limit" ∨
          k = .fld (minterKey c m) "epoch_length") → st.post k = st.pre k := by
        rintro k (rfl | rfl | rfl) <;> rw [hp _ (by simp [minterKey])] <;> unfold mint.s1 <;>
          split <;> simp [minterKey]
      rw [hcfg _ (Or.inl rfl), hcfg _ (Or.inr (Or.inl rfl)), hcfg _ (Or.inr (Or.inr rfl))]
      refine ⟨h1, h2, h3, ?_⟩
      have hpK : ∀ f, st.post (.fld (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e) f)
          = mint.s1 st (.fld (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e) f) :=
        fun f => hp _ (by simp)
      have hpH : st.post (.has (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e))
          = mint.s1 st (.has (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e)) :=
        hp _ (by simp)
      by_cases hc : st.call.argA "contract" = c ∧ st.call.argA "minter" = m ∧
          st.pre (.var "Admin") ≠ m ∧
          Int.tdiv (st.call.env "sequence") (st.pre (.fld (minterKey c m) "epoch_length")) = e
      · rw [if_pos ⟨hst.fn, hc⟩]
        obtain ⟨hc1, hc2, hc3, hc4⟩ := hc
        have hE : mint.pre_Minter_epoch_length st = s (.fld (minterKey c m) "epoch_length") := by
          show st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"])
            "epoch_length") = _
          rw [hc1, hc2]; exact h3
        have hKS : mint.key_MinterStats st = statsKey c m (s (.fld (minterKey c m) "epoch_length")) e := by
          show Key.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter",
            mint.pre_Minter_epoch_length st,
            Int.tdiv (st.call.env "sequence") (mint.pre_Minter_epoch_length st)] = _
          rw [hE, hc1, hc2, ← hc4, h3]; rfl
        have hKC : mint.key_MinterStats_consumed_limit st
            = .fld (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e) "consumed_limit" := by
          show Key.fld (mint.key_MinterStats st) "consumed_limit" = _
          rw [hKS]
        have hC : mint.amount st ≥ 0 ∧ st.pre Admin ≠ mint.minter st ∧ mint.pre_has_Minter st = 1 ∧
            mint.new_MinterStats_consumed_limit st ≤ mint.pre_Minter_limit st := by
          rcases hok with ⟨_, h⟩ | h
          · exact absurd (h.trans hc2) hc3
          · exact h
        have hNC : mint.new_MinterStats_consumed_limit st
            = getOr0 st.pre (.fld (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e)
                "consumed_limit") (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e)
              + st.call.arg "amount" := by
          show getOr0 st.pre (mint.key_MinterStats_consumed_limit st) (mint.key_MinterStats st) + _ = _
          rw [hKS, hKC]; rfl
        have hL : mint.pre_Minter_limit st = s (.fld (minterKey c m) "limit") := by
          show st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"])
            "limit") = _
          rw [hc1, hc2]; exact h2
        have hpost : getOr0 st.post
            (.fld (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e) "consumed_limit")
            (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e)
            = mint.new_MinterStats_consumed_limit st := by
          unfold getOr0; rw [hpK, hpH]; unfold mint.s1; rw [if_pos hC, hKC, hKS]
          simp
        have hb := hC.2.2.2
        rw [hpost, hNC, ← h4]
        rw [hL, hNC, ← h4] at hb
        exact ⟨Int.add_comm _ _, hb⟩
      · rw [if_neg (fun h => hc h.2)]
        have hpost : getOr0 st.post
            (.fld (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e) "consumed_limit")
            (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e)
            = getOr0 st.pre
            (.fld (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e) "consumed_limit")
            (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e) := by
          unfold getOr0; rw [hpK, hpH]; unfold mint.s1; split
          · rename_i hC
            have hne : ¬ statsKey c m (s (.fld (minterKey c m) "epoch_length")) e
                = mint.key_MinterStats st := by
              intro heq
              simp only [statsKey, mint.key_MinterStats, MinterStats, Key.tup.injEq, true_and,
                List.cons.injEq, and_true, mint.contract, mint.minter,
                mint.pre_Minter_epoch_length, Minter.epoch_length, Minter] at heq
              obtain ⟨rfl, rfl, -, rfl⟩ := heq
              exact hc ⟨rfl, rfl, hC.2.1, rfl⟩
            rw [show mint.key_MinterStats_consumed_limit st
              = .fld (mint.key_MinterStats st) "consumed_limit" from rfl]
            simp only [Storage.set_get, Key.has.injEq, Key.fld.injEq, and_true, hne, if_false,
              reduceCtorEq]
          · rfl
        rw [hpost]; exact ⟨h4, h5⟩
    · obtain ⟨u, hst⟩ := hst
      have hf : st.call.fn ≠ "mint" := by rw [hst.fn]; decide
      rw [if_neg (fun h => hf h.1), hst.post]; exact ⟨h1, h2, h3, h4, h5⟩
    · have hf : st.call.fn ≠ "mint" := by rw [hst.fn]; decide
      rw [if_neg (fun h => hf h.1), hst.post]
      simp only [getOr0, statsKey, minterKey] at h1 h2 h3 h4 h5 ⊢
      simp [set_admin.s1, h1, h2, h3, h4, h5]
    · have hf : st.call.fn ≠ "mint" := by rw [hst.fn]; decide
      have hne := hno' hst.fn
      rw [if_neg (fun h => hf h.1), hst.post]
      simp only [getOr0, statsKey, minterKey] at h1 h2 h3 h4 h5 ⊢
      simp [set_minter.s1, h1, h2, h3, h4, h5]
      refine ⟨?_, ?_, ?_⟩ <;> rintro rfl rfl <;> exact absurd ⟨rfl, rfl⟩ hne

/-- Epoch limit, across any sequence of calls: while the admin doesn't reconfigure minter `m`
    for contract `c`, what `m` mints in an epoch starting unused stays within its limit. -/
theorem epoch_limit : ∀ pool s tr t c m e, Run pool s tr t →
    (∀ st ∈ tr, st.call.fn = "set_minter" →
      ¬(st.call.argA "contract" = c ∧ st.call.argA "minter" = m)) →
    s (.has (minterKey c m)) = 1 →
    0 ≤ s (.fld (minterKey c m) "limit") →
    s (.has (statsKey c m (s (.fld (minterKey c m) "epoch_length")) e)) ≠ 1 →
    mintedIn c m e tr ≤ s (.fld (minterKey c m) "limit") := by
  intro pool s tr t c m e hrun hno _ hlim hK
  obtain ⟨-, -, -, h4, h5⟩ := epoch_inv pool s c m e hlim hK tr t hrun hno
  rw [h4]; exact h5

/-- Only the admin can reconfigure minters. -/
theorem set_minter_authorized : ∀ e ∈ entries, ∀ st c m, e st →
    st.post (.fld (minterKey c m) "limit") ≠ st.pre (.fld (minterKey c m) "limit") →
    admin st.pre ∈ st.call.signers := by
  intro e he st c m hst hne
  simp only [entries, List.mem_cons, List.not_mem_nil, or_false] at he
  rcases he with rfl | rfl | rfl | rfl | rfl
  · exact absurd (by rw [hst.post]) hne
  · obtain ⟨u, hst⟩ := hst
    apply absurd _ hne
    rw [mint_post st u hst _ (by simp [minterKey])]
    unfold mint.s1; split <;> simp [minterKey]
  · obtain ⟨u, hst⟩ := hst
    exact absurd (by rw [hst.post]) hne
  · exact hst.auth_Admin
  · exact hst.auth_Admin

/-- PROBE (`token.mint` is a call the model doesn't interpret, so it opens every ledger): a
    mint changes no balance except the recipient's. -/
theorem mint_only_credits_to : ∀ st, mint st → ∀ u tok, u ≠ st.call.argA "to" →
    bal tok st.post u = bal tok st.pre u := sorry

/-- The external `token.mint` call is modelled as `havoc`, which may set every token balance
    arbitrarily: an admin mint of 0 to address 0 whose havoc credits address 1 is admitted. -/
theorem mint_only_credits_to_false : ¬ (∀ st, mint st → ∀ u tok, u ≠ st.call.argA "to" →
    bal tok st.post u = bal tok st.pre u) := by
  intro h
  let c : Call := { fn := "mint", caller := 1, self := 0, arg := fun _ => 0, argA := fun _ => 0,
                    signers := [0], env := fun _ => 0 }
  let un : Unk := { i := fun _ => 0, g := fun _ => 0, b := fun _ => false, k := fun _ => .var "",
                    s := fun _ _ => 1 }
  let st : Step := { call := c, pre := fun _ => 0, post := havoc (fun _ => 0) (fun _ => 1),
                     writes := [mint.key_MinterStats_consumed_limit ⟨c, fun _ => 0, fun _ => 0, [], 0⟩,
                       .has (mint.key_MinterStats ⟨c, fun _ => 0, fun _ => 0, [], 0⟩)], ret := 2 }
  have hm : mint st := ⟨un, {
    fn := rfl
    notReentrant := by decide
    auth_minter := by simp [st, c]
    ok := by simp [st, c]
    post := by simp [st, c, un]
    writes := rfl
    ret := by simp [st, c] }⟩
  have := h st hm 1 0 (by simp [st, c])
  simp [st, bal, havoc] at this

/-- NON-VACUITY: a non-admin minter can mint. -/
theorem mint_live :
    ∃ st, mint st ∧ 0 < st.call.arg "amount" ∧ admin st.pre ≠ st.call.argA "minter" := by
  let c : Call := { fn := "mint", caller := 5, self := 7, arg := fun _ => 1,
                    argA := fun n => if n = "minter" then 1 else 0,
                    signers := [1], env := fun _ => 0 }
  let pre : Storage := fun k =>
    if k = .fld (.tup "Minter" [0, 1]) "limit" then 10 else if k = .var "Admin" then 0 else 1
  let un : Unk := { i := fun _ => 0, g := fun _ => 0, b := fun _ => false, k := fun _ => .var "",
                    s := fun _ => pre }
  let st0 : Step := { call := c, pre := pre, post := pre, writes := [], ret := 2 }
  let st : Step := { call := c, pre := pre, post := mint.s2 st0 un, ret := 2,
                     writes := [mint.key_MinterStats_consumed_limit st0, .has (mint.key_MinterStats st0)] }
  refine ⟨st, ⟨un, {
    fn := rfl
    notReentrant := by decide
    auth_minter := by simp [st, st0, c]
    ok := by simp [st, st0, c, pre, getOr0]
    post := rfl
    writes := rfl
    ret := by simp [st, st0, c, pre, getOr0] }⟩, by simp [st, st0, c], by simp [Spec.admin, st, st0, c, pre]⟩

end Locked
