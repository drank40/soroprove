-- Proofs over the generated `mint_lock.lean` model (appended to it by check.sh).
-- `Minter(contract, minter)` / `MinterStats(…)` are multi-field keys (`.tup`);
-- `MinterConfig` / `MinterStats` are structs stored field by field (`.fld`).
open Contract

/-- Only the admin configures minters, and the config is stored per (contract, minter). -/
theorem set_minter_by_admin (st : Step) (h : set_minter st) :
    st.pre (.var "Admin") ∈ st.call.signers ∧
    st.post (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit") = st.call.arg "config.limit" := by
  obtain ⟨_, _, hsig, hpost, _⟩ := h
  refine ⟨hsig, ?_⟩
  rw [hpost]; simp [Storage.set]

/-- A non-admin mint succeeds only for a configured minter, within its epoch limit. -/
theorem mint_within_limit (st : Step) (h : mint st) (hm : st.pre (.var "Admin") ≠ st.call.argA "minter") :
    st.pre (.has (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"])) = 1 ∧
    getOr0 st.pre (.fld (.tup "MinterStats" [st.call.argA "contract", st.call.argA "minter",
        st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length"),
        Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length"))])
        "consumed_limit") (base := .tup "MinterStats" [st.call.argA "contract", st.call.argA "minter",
        st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length"),
        Int.tdiv (st.call.env "sequence") (st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "epoch_length"))])
        + st.call.arg "amount"
      ≤ st.pre (.fld (.tup "Minter" [st.call.argA "contract", st.call.argA "minter"]) "limit") := by
  obtain ⟨_, _, _, _, hok, _⟩ := h
  rcases hok with ⟨_, hadm⟩ | ⟨_, _, hhas, hlim⟩
  · exact absurd hadm hm
  · exact ⟨by simpa using hhas, by omega⟩
