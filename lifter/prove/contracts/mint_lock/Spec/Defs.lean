/- Developer-owned definitions used by the locked statements. Solutions may import this. -/
import Spec.Common

namespace Spec
open Contract

def admin (s : Storage) : Addr := s (.var "Admin")
def minterKey (c m : Addr) : Key := .tup "Minter" [c, m]
def statsKey (c m len e : Int) : Key := .tup "MinterStats" [c, m, len, e]
/-- Total amount minted over `tr` by non-admin minter `m` for token contract `c` in epoch `e`. -/
def mintedIn (c m e : Int) (tr : List Step) : Int :=
  (tr.filter fun st => st.call.fn == "mint" && st.call.argA "contract" == c &&
      st.call.argA "minter" == m && st.pre (.var "Admin") != m &&
      Int.tdiv (st.call.env "sequence") (st.pre (.fld (minterKey c m) "epoch_length")) == e).foldr
    (fun st acc => st.call.arg "amount" + acc) 0

end Spec
