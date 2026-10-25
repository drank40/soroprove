/-
  An Archetype-style specification layer in Lean 4 (core only, no Mathlib).

  Design choices (all made to keep specifications and proofs short):
  * No reentrancy, so an entry point is ONE atomic step:  State → Option State.
    There is no call stack and no loop. Failure means "nothing changed".
  * An entry point = a list of `requires` checks + a list of effects.
  * The ledger is a keyed collection: `holders` (the keys) and `bal` (the field),
    like an Archetype asset. `sum` is the sum of `bal` over `holders`.
  * Fixed shape of arguments (`Args`), no error codes, holders cannot be added.

  Checked with Lean 4.35.0; all proofs are complete (no `sorry`).
-/

namespace Spec

abbrev Addr := Nat

/-! ## Storage and effects -/

structure St where
  owner   : Addr
  holders : List Addr
  bal     : Addr → Int

/-- Archetype: `ledger.sum(balance)` -/
def St.sum (s : St) : Int := (s.holders.map s.bal).sum

/-- Archetype: `ledger.update(who, { balance += delta })` -/
structure Eff where
  who   : Addr
  delta : Int

def Eff.apply (s : St) (e : Eff) : St :=
  { s with bal := fun a => if a = e.who then s.bal a + e.delta else s.bal a }

def applyAll : St → List Eff → St
  | s, []      => s
  | s, e :: es => applyAll (e.apply s) es

/-! ## Entry points -/

structure Args where
  to  : Addr
  amt : Int

structure Entry where
  requires : List (St → Addr → Args → Bool)   -- `called by`, `require`, ...
  effects  : Addr → Args → List Eff           -- `effect { ... }`

/-- Run an entry point as `caller`. `none` = the call fails and nothing changes. -/
def Entry.run (e : Entry) (s : St) (caller : Addr) (a : Args) : Option St :=
  if e.requires.all (fun r => r s caller a) then
    some (applyAll s (e.effects caller a))
  else none

/-! ## Specification language -/

/-- Archetype `postcondition`: `P before caller args after`.
    (The ledger keys must be unique, as in an Archetype asset.) -/
def Entry.Post (e : Entry) (P : St → Addr → Args → St → Prop) : Prop :=
  ∀ s c a s', s.holders.Nodup → e.run s c a = some s' → P s c a s'

/-- Archetype `only_by_role`. -/
def Entry.OnlyBy (e : Entry) (role : St → Addr) : Prop :=
  e.Post (fun s c _ _ => c = role s)

/-! ## Library: proved once, so users never prove them again -/

theorem Entry.run_some {e : Entry} {s s' : St} {c : Addr} {a : Args}
    (h : e.run s c a = some s') :
    (e.requires.all (fun r => r s c a) = true) ∧ s' = applyAll s (e.effects c a) := by
  unfold Entry.run at h
  split at h
  · rename_i hc
    exact ⟨hc, (Option.some.inj h).symm⟩
  · exact absurd h (by simp)

theorem Eff.apply_holders (s : St) (e : Eff) : (e.apply s).holders = s.holders := rfl

/-- Balance of one account after a list of effects. -/
theorem applyAll_bal (s : St) (es : List Eff) (a : Addr) :
    (applyAll s es).bal a
      = s.bal a + (es.map (fun e => if a = e.who then e.delta else 0)).sum := by
  induction es generalizing s with
  | nil => simp [applyAll]
  | cons e es ih =>
    simp only [applyAll, ih, List.map_cons, List.sum_cons]
    by_cases h : a = e.who <;> simp [Eff.apply, h] <;> omega

/-- Changing one key of a keyed collection changes the sum by `delta`
    (if the key exists). Needs unique keys. -/
theorem sum_update (hs : List Addr) (hnd : hs.Nodup) (f : Addr → Int)
    (w : Addr) (d : Int) :
    (hs.map (fun a => if a = w then f a + d else f a)).sum
      = (hs.map f).sum + (if w ∈ hs then d else 0) := by
  induction hs with
  | nil => simp
  | cons h t ih =>
    obtain ⟨hh, ht⟩ := List.nodup_cons.mp hnd
    have ih := ih ht
    simp only [List.map_cons, List.sum_cons, ih]
    by_cases hw : h = w
    · subst hw
      simp [hh] <;> omega
    · simp [hw, Ne.symm hw]
      by_cases hwt : w ∈ t <;> simp [hwt] <;> omega

theorem sum_apply (s : St) (e : Eff) (hnd : s.holders.Nodup) :
    (e.apply s).sum = s.sum + (if e.who ∈ s.holders then e.delta else 0) := by
  unfold St.sum
  exact sum_update s.holders hnd s.bal e.who e.delta

/-- Sum of the ledger after a list of effects. -/
theorem sum_applyAll (s : St) (es : List Eff) (hnd : s.holders.Nodup) :
    (applyAll s es).sum
      = s.sum + (es.map (fun e => if e.who ∈ s.holders then e.delta else 0)).sum := by
  induction es generalizing s with
  | nil => simp [applyAll]
  | cons e es ih =>
    have h1 := ih (e.apply s) hnd
    have h2 := sum_apply s e hnd
    simp only [Eff.apply_holders] at h1
    simp only [applyAll, List.map_cons, List.sum_cons]
    rw [h1, h2]
    exact Int.add_assoc _ _ _

set_option hygiene false in
/-- The boring start of every proof: get the checks and the effects out of `run`. -/
macro "unpack " e:ident : tactic =>
  `(tactic| (intro s c a s' hnd h
             obtain ⟨hreq, rfl⟩ := Entry.run_some h
             simp only [$e:ident, List.all_cons, List.all_nil, Bool.and_true,
               Bool.and_eq_true, decide_eq_true_eq] at hreq
             try dsimp only))

/-! ## A token contract (what the user writes) -/

def transfer : Entry where
  requires :=
    [ fun _ _ a => 0 < a.amt,
      fun _ c a => c ≠ a.to,
      fun s c a => a.amt ≤ s.bal c,
      fun s c a => c ∈ s.holders ∧ a.to ∈ s.holders ]
  effects := fun c a => [⟨c, -a.amt⟩, ⟨a.to, a.amt⟩]

def mint : Entry where
  requires :=
    [ fun s c _ => c = s.owner,
      fun _ _ a => 0 < a.amt,
      fun s _ a => a.to ∈ s.holders ]
  effects := fun _ a => [⟨a.to, a.amt⟩]

/-! ## Its specification (what the user proves) -/

/-- postcondition: `ledger.sum(balance) = before.ledger.sum(balance)` -/
theorem transfer_conserves :
    transfer.Post (fun s _ _ s' => s'.sum = s.sum) := by
  unpack transfer
  obtain ⟨hpos, hne, hfund, hc, hd⟩ := hreq
  rw [sum_applyAll _ _ hnd]
  simp [transfer, hc, hd] <;> omega

/-- The "ever increasing" property: nobody except the sender is ever debited. -/
theorem transfer_not_debited :
    transfer.Post (fun s c _ s' => ∀ k, k ≠ c → s.bal k ≤ s'.bal k) := by
  unpack transfer
  obtain ⟨hpos, hne, hfund, hc, hd⟩ := hreq
  intro k hk
  rw [applyAll_bal]
  by_cases hkd : k = a.to <;> simp [transfer, hk, hkd] <;> omega

/-- postcondition: the supply grows by exactly the minted amount. -/
theorem mint_supply :
    mint.Post (fun s _ a s' => s'.sum = s.sum + a.amt) := by
  unpack mint
  obtain ⟨howner, hpos, hd⟩ := hreq
  rw [sum_applyAll _ _ hnd]
  simp [mint, hd] <;> omega

/-- `only_by_role`: only the owner can mint. -/
theorem mint_only_owner : mint.OnlyBy St.owner := by
  unpack mint
  exact hreq.1

/-! ## Backwards: from the property to ALL operations

  Instead of proving one property per entry, we state the property once and
  ask Lean to check it against every entry point of the contract. -/

/-- Syntactic test: every effect on account `k` is a non-negative change. -/
def OnlyCredits (k : Addr) (es : List Eff) : Prop :=
  ∀ e ∈ es, e.who = k → 0 ≤ e.delta

theorem sum_credits_nonneg (k : Addr) :
    ∀ es : List Eff, OnlyCredits k es →
      0 ≤ (es.map (fun e => if k = e.who then e.delta else 0)).sum
  | [], _ => by simp
  | e :: es, h => by
    have h1 : OnlyCredits k es := fun x hx hk => h x (by simp [hx]) hk
    have h2 := sum_credits_nonneg k es h1
    simp only [List.map_cons, List.sum_cons]
    by_cases hk : k = e.who
    · have h3 : 0 ≤ e.delta := h e (by simp) hk.symm
      rw [ite_eq_left_of_eq_true _ _ (eq_true hk)]
      omega
    · rw [ite_eq_right_of_eq_false _ _ (eq_false hk)]
      omega

/-- The template: if an entry only credits `k`, its balance cannot go down. -/
theorem balance_not_lowered (s : St) (es : List Eff) (k : Addr)
    (h : OnlyCredits k es) : s.bal k ≤ (applyAll s es).bal k := by
  rw [applyAll_bal]
  have := sum_credits_nonneg k es h
  omega

/-- A contract is its list of entry points. -/
def NoDebit (C : List Entry) : Prop :=
  ∀ e ∈ C, e.Post (fun s c _ s' => ∀ k, k ≠ c → s.bal k ≤ s'.bal k)

/-- `mint` only credits, so it passes the check for every account. -/
theorem mint_not_debited :
    mint.Post (fun s c _ s' => ∀ k, k ≠ c → s.bal k ≤ s'.bal k) := by
  unpack mint
  obtain ⟨_, hpos, _⟩ := hreq
  intro k _
  apply balance_not_lowered
  intro e he _
  simp [mint] at he
  subst he
  exact Int.le_of_lt hpos

/-- THE GLOBAL THEOREM: over all operations of the contract, nobody except the
    caller can ever lose balance. Adding an entry to the list adds one proof
    obligation here; an entry that can debit others makes this proof fail. -/
theorem token_no_debit : NoDebit [transfer, mint] := by
  intro e he
  simp only [List.mem_cons, List.not_mem_nil, or_false] at he
  rcases he with rfl | rfl
  · exact transfer_not_debited
  · exact mint_not_debited

end Spec
