/- Developer-owned definitions used by the locked statements. Solutions may import this. -/
import Spec.Common

namespace Spec
open Contract

def funded (s : Storage) : Prop := s (.has (.var "Balance")) = 1
def initialized (s : Storage) : Prop := s (.has (.var "Init")) = 1
def calls (f : String) (tr : List Step) : Nat := tr.countP (·.call.fn == f)

end Spec
