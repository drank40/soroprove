/- Developer-owned definitions used by the locked statements. Solutions may import this. -/
import Spec.Common

namespace Spec
open Contract

/-- `a`'s balance (an absent entry reads as 0). -/
def balanceOf (s : Storage) (a : Addr) : Int := getOr0 s (.entry "Balance" a)
def allowanceKey (owner spender : Addr) : Key := .tup "Allowance" [owner, spender]
/-- `owner` has no allowance granted to anyone. -/
def NoAllowances (s : Storage) (owner : Addr) : Prop := ∀ sp, s (.has (allowanceKey owner sp)) ≠ 1
def admin (s : Storage) : Addr := s (.var "Admin")

end Spec
