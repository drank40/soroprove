/-
SEP-41 token interface as an abstract state machine.

Sources (vendored):
* vendor/sep/sep-0041.md v0.5.2 — the interface, allowance and event semantics;
* the reference implementation, the Stellar Asset Contract
  (vendor/rs-soroban-env/soroban-env-host/src/builtin_contracts/stellar_asset_contract/
  contract.rs:158-300, allowance.rs) — for what SEP-41 leaves implicit: negative amounts
  are rejected and `from` (resp. `spender`) must authorize.

A call either fails (a trap: the host rolls the frame back, so the token state is
unchanged) or succeeds with exactly the effect given here. A conforming token may fail
for its own reasons (e.g. the SAC's deauthorized balances), so the spec constrains
successful calls only; `Allowed` says which calls must succeed for a given token.
-/

namespace Soroban.Spec.Sep41

def I128_MAX : Int := 2^127 - 1

structure Allowance where
  amount : Int := 0
  liveUntil : Nat := 0
  deriving DecidableEq, Inhabited

variable (A : Type) [DecidableEq A]

/-- The token state visible through the interface. -/
structure St where
  bal : A → Int
  allow : A → A → Allowance

inductive Event where
  | approve (from_ spender : A) (amount : Int) (liveUntil : Nat)
  | transfer (from_ to : A) (amount : Int)
  | burn (from_ : A) (amount : Int)
  | mint (to : A) (amount : Int)

variable {A}

def upd (f : A → Int) (a : A) (v : Int) : A → Int := fun x => if x = a then v else f x

/-- `read_allowance` (allowance.rs): an expired allowance reads as 0. -/
def St.allowance (s : St A) (seq : Nat) (from_ spender : A) : Int :=
  let a := s.allow from_ spender
  if a.liveUntil < seq then 0 else a.amount

/-- `spend_balance` then `receive_balance`: `from` must cover `amount`, `to` must not
    overflow i128. `from = to` is allowed and leaves the balance unchanged. -/
def move (s : St A) (from_ to : A) (amt : Int) : Option (St A) :=
  if s.bal from_ < amt then none else
  let b := upd s.bal from_ (s.bal from_ - amt)
  if b to + amt > I128_MAX then none else
  some { s with bal := upd b to (b to + amt) }

/-- `spend_allowance` (allowance.rs:spend_allowance): the amount is reduced, the
    expiration is kept; nothing is written when `amount = 0`. -/
def spendAllowance (s : St A) (seq : Nat) (from_ spender : A) (amt : Int) : Option (St A) :=
  let cur := s.allowance seq from_ spender
  if cur < amt then none else
  if amt = 0 then some s else
  some { s with allow := fun f sp =>
    if f = from_ ∧ sp = spender then { s.allow f sp with amount := cur - amt } else s.allow f sp }

/-- Who must authorize each call (`require_auth`). -/
inductive Call (A : Type) where
  | transfer (from_ to : A) (amount : Int)
  | transferFrom (spender from_ to : A) (amount : Int)
  | approve (from_ spender : A) (amount : Int) (liveUntil : Nat)
  | burn (from_ : A) (amount : Int)
  | burnFrom (spender from_ : A) (amount : Int)

def Call.authorizer : Call A → A
  | .transfer f .. | .approve f .. | .burn f .. => f
  | .transferFrom sp .. | .burnFrom sp .. => sp

def Call.amount : Call A → Int
  | .transfer _ _ a | .transferFrom _ _ _ a | .approve _ _ a _ | .burn _ a | .burnFrom _ _ a => a

/-- The effect of a successful call at ledger `seq`. -/
def Call.step (seq : Nat) (s : St A) : Call A → Option (St A × List (Event A))
  | .transfer f t a => (move s f t a).map (·, [.transfer f t a])
  | .transferFrom sp f t a => do
      let s ← spendAllowance s seq f sp a
      let s ← move s f t a
      pure (s, [.transfer f t a])
  | .approve f sp a lu =>
      if a > 0 ∧ lu < seq then none else
      some ({ s with allow := fun x y => if x = f ∧ y = sp then ⟨a, lu⟩ else s.allow x y },
            [.approve f sp a lu])
  | .burn f a =>
      if s.bal f < a then none else some ({ s with bal := upd s.bal f (s.bal f - a) }, [.burn f a])
  | .burnFrom sp f a => do
      let s ← spendAllowance s seq f sp a
      if s.bal f < a then none else some ({ s with bal := upd s.bal f (s.bal f - a) }, [.burn f a])

/-- A successful call is one with a nonnegative amount, authorized by its authorizer,
    whose effect is `step`. `auth a` = `a.require_auth()` succeeds in this transaction. -/
def Conforms (auth : A → Prop) (seq : Nat) (s : St A) (c : Call A) (s' : St A) (evs : List (Event A)) : Prop :=
  0 ≤ c.amount ∧ auth c.authorizer ∧ c.step seq s = some (s', evs)

/-! ## Consequences every caller can rely on -/

theorem move_conserves {s s' : St A} {f t : A} {a : Int} (h : move s f t a = some s') (x : A) (hx : x ≠ f ∧ x ≠ t) :
    s'.bal x = s.bal x := by
  simp only [move] at h
  split at h; · contradiction
  split at h; · contradiction
  cases h; simp [upd, hx.1, hx.2]

theorem move_sum {s s' : St A} {f t : A} {a : Int} (h : move s f t a = some s') (hne : f ≠ t) :
    s'.bal f + s'.bal t = s.bal f + s.bal t := by
  simp only [move] at h
  split at h; · contradiction
  split at h; · contradiction
  cases h; simp [upd, hne, Ne.symm hne]; omega

theorem move_from {s s' : St A} {f t : A} {a : Int} (h : move s f t a = some s') (hne : f ≠ t) :
    s'.bal f = s.bal f - a ∧ s'.bal t = s.bal t + a ∧ a ≤ s.bal f := by
  simp only [move] at h
  split at h; · contradiction
  split at h; · contradiction
  cases h; simp [upd, hne, Ne.symm hne]; omega

end Soroban.Spec.Sep41
