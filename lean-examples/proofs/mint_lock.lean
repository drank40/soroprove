-- Proofs over the generated `mint_lock.lean` model (appended to it by check.sh).
-- `Minter c m` / `MinterStats c m len epoch` are multi-field keys; `MinterConfig`
-- and `MinterStats` are structs stored field by field (`Minter.limit c m`, …).
open Contract

/-- Only the admin configures minters, and the config is stored per (contract, minter). -/
theorem set_minter_by_admin (st : Step) (h : set_minter st) :
    st.pre Admin ∈ st.call.signers ∧
    st.post (Minter.limit (set_minter.contract st) (set_minter.minter st)) = set_minter.config.limit st := by
  refine ⟨h.auth_Admin, ?_⟩
  rw [h.post]; simp

/-- A non-admin mint succeeds only for a configured minter, within its epoch limit. -/
theorem mint_within_limit (st : Step) (h : mint st) (hm : st.pre Admin ≠ mint.minter st) :
    let len := st.pre (Minter.epoch_length (mint.contract st) (mint.minter st))
    let epoch := Int.tdiv (st.call.env "sequence") len
    st.pre (.has (Minter (mint.contract st) (mint.minter st))) = 1 ∧
    getOr0 st.pre (MinterStats.consumed_limit (mint.contract st) (mint.minter st) len epoch)
        (base := MinterStats (mint.contract st) (mint.minter st) len epoch) + mint.amount st
      ≤ st.pre (Minter.limit (mint.contract st) (mint.minter st)) := by
  obtain ⟨u, h⟩ := h
  have hok := h.ok
  simp only [mint.contract, mint.minter, mint.amount, Minter, Minter.limit, Minter.epoch_length, MinterStats,
    MinterStats.consumed_limit, Admin] at hok hm ⊢
  rcases hok with ⟨_, hadm⟩ | ⟨_, _, hhas, hlim⟩
  · exact absurd hadm hm
  · exact ⟨by simpa using hhas, by omega⟩
