/- Shared definitions for every contract's spec (trusted). -/
import Gen.Model

namespace Spec
open Contract

/-- Any sequence of calls to the deployed contract at `pool`, from `s` to `t`; `tr` is the
    list of steps taken, most recent first. The constructor runs once at deployment, so it is
    not one of these calls. -/
inductive Run (pool : Addr) : Storage → List Step → Storage → Prop where
  | nil (s : Storage) : Run pool s [] s
  | cons {s : Storage} {tr : List Step} (st : Step) :
      Run pool s tr st.pre → st.call.self = pool → st.call.fn ≠ "__constructor" →
      (∃ e ∈ entries, e st) → Run pool s (st :: tr) st.post

/-- `u` is a user other than the contract that authorized nothing during `tr`. -/
def Bystander (pool u : Addr) (tr : List Step) : Prop :=
  u ≠ pool ∧ ∀ st ∈ tr, u ∉ st.call.signers

end Spec
