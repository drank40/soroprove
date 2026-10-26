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

/-- A non-admin mint succeeds only for a configured minter, and only if the
    epoch's consumed limit stays within the configured limit. -/
theorem mint_within_limit (st : Step) (h : mint st) (hm : st.pre Admin ≠ mint.minter st) :
    mint.pre_has_Minter st = 1 ∧ mint.new_MinterStats_consumed_limit st ≤ mint.pre_Minter_limit st := by
  obtain ⟨u, h⟩ := h
  rcases h.ok with ⟨_, hadm⟩ | ⟨_, _, hhas, hlim⟩
  · exact absurd hadm hm
  · exact ⟨hhas, hlim⟩
