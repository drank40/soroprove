/-
Stand-in for `slice --lean-challenge` output: a lockup-style vault (signed withdrawals with
nonce replay protection, owner-gated key rotation and owner withdrawal).
-/
namespace Contract

structure State where
  owner     : Nat
  pubKey    : Nat
  used      : List Nat   -- executed withdrawal nonces
  vault     : Int        -- the contract's token balance
  deposited : Int
  withdrawn : Int        -- via signed `withdraw`
  pulled    : Int        -- via `owner_withdraw`

inductive Action where
  | deposit (amt : Int)
  | withdraw (amt : Int) (nonce : Nat) (sigOk : Bool)
  | setPubKey (caller key : Nat)
  | setOwner (caller new : Nat)
  | ownerWithdraw (caller : Nat) (amt : Int)

def init (owner key : Nat) : State := ⟨owner, key, [], 0, 0, 0, 0⟩

def guard (s : State) : Action → Prop
  | .deposit a => 0 < a
  | .withdraw a n ok => 0 < a ∧ ok = true ∧ n ∉ s.used ∧ a ≤ s.vault
  | .setPubKey c _ => c = s.owner
  | .setOwner c _ => c = s.owner
  | .ownerWithdraw c a => c = s.owner ∧ 0 < a ∧ a ≤ s.vault

def step (s : State) : Action → State
  | .deposit a => { s with vault := s.vault + a, deposited := s.deposited + a }
  | .withdraw a n _ => { s with used := n :: s.used, vault := s.vault - a, withdrawn := s.withdrawn + a }
  | .setPubKey _ k => { s with pubKey := k }
  | .setOwner _ o => { s with owner := o }
  | .ownerWithdraw _ a => { s with vault := s.vault - a, pulled := s.pulled + a }

/-- States reachable from deployment by any sequence of allowed transactions. -/
inductive Reach : State → Prop where
  | init (o k : Nat) : Reach (init o k)
  | step {s : State} (a : Action) : Reach s → guard s a → Reach (step s a)

end Contract
