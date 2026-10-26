/- Developer-owned definitions used by the locked statements. Solutions may import this. -/
import Spec.Common

namespace Spec
open Contract

def counter (s : Storage) : Int := getOr0 s (.var "COUNTER")

end Spec
