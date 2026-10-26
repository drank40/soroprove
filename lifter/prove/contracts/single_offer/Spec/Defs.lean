/- Developer-owned definitions used by the locked statements. Solutions may import this. -/
import Spec.Common

namespace Spec
open Contract

def created (s : Storage) : Prop := s (.has (.var "Offer")) = 1
def seller (s : Storage) : Addr := s (.fld (.var "Offer") "seller")
def sellToken (s : Storage) : Addr := s (.fld (.var "Offer") "sell_token")
def buyToken (s : Storage) : Addr := s (.fld (.var "Offer") "buy_token")

end Spec
