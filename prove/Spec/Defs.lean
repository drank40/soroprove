/- Developer-owned definitions used by the locked statements. Solutions may import this. -/
import Gen.Model

namespace Spec
open Contract

/-- Tokens out never exceed tokens in. -/
def Solvent (s : State) : Prop := s.withdrawn + s.pulled ≤ s.deposited

end Spec
