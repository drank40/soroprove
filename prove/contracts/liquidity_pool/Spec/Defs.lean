/- Developer-owned definitions used by the locked statements. Solutions may import this. -/
import Spec.Common

namespace Spec
open Contract

/-- The stored reserves. -/
def reserveA (s : Storage) : Int := s (.var "ReserveA")
def reserveB (s : Storage) : Int := s (.var "ReserveB")

end Spec
