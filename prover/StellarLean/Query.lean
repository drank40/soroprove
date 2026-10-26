import StellarLean.TokenSpec

/-
  Asking questions about contract storage.

  Storage is named variables and hash maps, the way a Soroban contract sees
  it once you strip away the encoding. A question is built from bricks:

    what we look at    `owner`, `balance[caller]`, `balance[user]`, `balance.total`,
                       and sums/differences/products of these (`t + u`, `t * u`)
    how it may change  `unchanged`, `decreases`, `increases`, `neverDecreases`,
                       `changesBy`, `dropsAtMost`, `gainsAtLeast`, `signedBy`
    which call         `calls "swap"` (for contracts with several entry points)
    glue               `∧ₛ`, `∀ₛ user, …`, `.except (isCaller user)`

  and asked of an entry point or a whole contract with `⊨`:

    transfer.exec ⊨ decreases balance[caller]
    "Is the caller's balance reduced when a transfer happens?"

  Every brick knows which storage slots it reads, so the library can answer
  "nothing it reads was written" questions with one theorem (`Contract.frame`).

  Contracts described with this library: `Token.lean` (with
  `TokenQuestions.lean`), `Increment.lean` (with `IncrementQuestions.lean`),
  `SorobanToken.lean` and `SorobanAmm.lean` (with their `…Answers.lean`).
-/

namespace Query

open Spec (Addr Args St Eff Entry applyAll)

/-! ## Storage: named variables and hash maps -/

inductive Val where
  | none              -- slot not set
  | int  (i : Int)
  | addr (a : Addr)

/-- A storage slot: a variable, or one entry of a map. -/
inductive Key where
  | var   (name : String)
  | entry (map : String) (k : Addr)
  deriving DecidableEq

abbrev Storage := Key → Val

/-- Write one slot (`storage().set(key, value)`). -/
def Storage.set (s : Storage) (k : Key) (v : Val) : Storage :=
  fun k' => if k' = k then v else s k'

/-- Types that can be kept in storage. -/
class Stored (α : Type) where
  ofVal : Val → α

instance : Stored Int  := ⟨fun | .int i => i  | _ => 0⟩
instance : Stored Addr := ⟨fun | .addr a => a | _ => 0⟩

@[simp] theorem ofVal_int (i : Int) : (Stored.ofVal (.int i) : Int) = i := rfl
@[simp] theorem ofVal_none : (Stored.ofVal .none : Int) = 0 := rfl

/-- Read a variable; an unset slot reads as the type's default
    (`get(&KEY).unwrap_or(0)` for numbers). -/
def read [Stored α] (s : Storage) (name : String) : α := Stored.ofVal (s (.var name))

/-! ## Calls, steps, contracts -/

/-- What an entry point is called with. `holders` is model-only (ghost):
    Soroban maps cannot be iterated, but totals need the list of keys. -/
structure Call where
  caller  : Addr      -- signed the call (`require_auth`)
  args    : Args
  holders : List Addr
  /-- The entry point invoked (`"swap"`, …), for contracts with several. -/
  fn      : String := ""
  /-- Further number arguments, by name (`"desired_a"`, …); booleans are 0/1. -/
  arg     : String → Int := fun _ => 0

/-- One call of one entry point. -/
structure Step where
  call   : Call
  pre    : Storage
  post   : Storage
  writes : List Key   -- slots given to `put`/`del_contract_data`
  ret    : Val := .none

/-- Storage changes only at written slots. -/
def Step.Framed (st : Step) : Prop := ∀ k, k ∉ st.writes → st.post k = st.pre k

/-- A contract: for each entry point, the steps it can take. -/
structure Contract where
  entries : List (Step → Prop)
  framed  : ∀ e ∈ entries, ∀ st, e st → st.Framed

/-! ## Bricks: what we look at -/

/-- A value read from storage during a call, with the slots it reads. -/
structure Term (α : Type) where
  get   : Call → Storage → α
  reads : Call → Key → Prop
  agree : ∀ c s s', (∀ k, reads c k → s k = s' k) → get c s = get c s'

/-- A storage variable. -/
def var [Stored α] (name : String) : Term α where
  get _ s   := read s name
  reads _ k := k = .var name
  agree _ _ _ h := by simp only [read]; rw [h _ rfl]

/-- A storage hash map. Index it with `m[who]`. -/
structure Map (α : Type) where
  name : String

/-- Whose entry: a fixed address, or one taken from the call. -/
abbrev Who := Call → Addr

def caller    : Who := Call.caller
def recipient : Who := fun c => c.args.to
def amount (c : Call) : Int := c.args.amt

def Map.read [Stored α] (m : Map α) (s : Storage) (a : Addr) : α :=
  Stored.ofVal (s (.entry m.name a))

def Map.at [Stored α] (m : Map α) (w : Who) : Term α where
  get c s   := m.read s (w c)
  reads c k := k = .entry m.name (w c)
  agree _ _ _ h := by simp only [Map.read]; rw [h _ rfl]

instance [Stored α] : GetElem (Map α) Who (Term α) (fun _ _ => True) := ⟨fun m w _ => m.at w⟩
instance [Stored α] : GetElem (Map α) Addr (Term α) (fun _ _ => True) :=
  ⟨fun m a _ => m.at fun _ => a⟩

/-- Sum of a map over the (ghost) holders. -/
def Map.total (m : Map Int) : Term Int where
  get c s   := (c.holders.map (m.read s)).sum
  reads c k := ∃ a ∈ c.holders, k = .entry m.name a
  agree c _ _ h := by
    congr 1
    exact List.map_congr_left fun a ha => by simp only [Map.read]; rw [h _ ⟨a, ha, rfl⟩]

/-- Arithmetic on number terms: `t + u`, `t - u`, `t * u`. -/
def Term.map₂ (f : Int → Int → Int) (t u : Term Int) : Term Int where
  get c s   := f (t.get c s) (u.get c s)
  reads c k := t.reads c k ∨ u.reads c k
  agree c s s' h := by
    rw [t.agree c s s' fun k hk => h k (.inl hk), u.agree c s s' fun k hk => h k (.inr hk)]

instance : Add (Term Int) := ⟨Term.map₂ (· + ·)⟩
instance : Sub (Term Int) := ⟨Term.map₂ (· - ·)⟩
instance : Mul (Term Int) := ⟨Term.map₂ (· * ·)⟩

/-! ## Bricks: how it may change -/

/-- A yes/no question about one step. -/
def Question := Step → Prop

def unchanged (t : Term α) : Question :=
  fun st => t.get st.call st.post = t.get st.call st.pre
def decreases (t : Term Int) : Question :=
  fun st => t.get st.call st.post < t.get st.call st.pre
def increases (t : Term Int) : Question :=
  fun st => t.get st.call st.pre < t.get st.call st.post
def neverDecreases (t : Term Int) : Question :=
  fun st => t.get st.call st.pre ≤ t.get st.call st.post
def changesBy (t : Term Int) (d : Call → Int) : Question :=
  fun st => t.get st.call st.post = t.get st.call st.pre + d st.call
/-- The call returns the value of `t` after the call. -/
def returns [Stored α] (t : Term α) : Question :=
  fun st => Stored.ofVal st.ret = t.get st.call st.post

/-- The address stored in `t` signed the call. -/
def signedBy (t : Term Addr) : Question :=
  fun st => t.get st.call st.pre = st.call.caller

def isCaller    (u : Addr) : Question := fun st => u = st.call.caller
def isRecipient (u : Addr) : Question := fun st => u = st.call.args.to

/-- The call invokes entry point `f`. -/
def calls (f : String) : Question := fun st => st.call.fn = f

/-- `t` goes down by at most `d` (e.g. "pays at most `in_max`"). -/
def dropsAtMost (t : Term Int) (d : Call → Int) : Question :=
  fun st => t.get st.call st.pre - d st.call ≤ t.get st.call st.post
/-- `t` goes up by at least `d` (e.g. "receives at least `min_a`"). -/
def gainsAtLeast (t : Term Int) (d : Call → Int) : Question :=
  fun st => t.get st.call st.pre + d st.call ≤ t.get st.call st.post

/-! ## Glue -/

def Question.and (P Q : Question) : Question := fun st => P st ∧ Q st
def Question.or  (P Q : Question) : Question := fun st => P st ∨ Q st
def Question.all {β : Type} (P : β → Question) : Question := fun st => ∀ b, P b st
/-- `P`, except on steps where `g` holds. -/
def Question.except (P : Question) (g : Question) : Question := fun st => g st ∨ P st
/-- `P`, on steps where `g` holds (nothing is claimed about the others). -/
def Question.given (P : Question) (g : Question) : Question := fun st => g st → P st

infixr:35 " ∧ₛ " => Question.and
infixr:30 " ∨ₛ " => Question.or
macro "∀ₛ " x:ident ", " P:term : term => `(Question.all fun $x => $P)

class Models (α : Type) where
  models : α → Question → Prop

infix:25 " ⊨ " => Models.models

instance : Models (Step → Prop) := ⟨fun e P => ∀ st, e st → P st⟩
instance : Models Contract := ⟨fun C P => ∀ e ∈ C.entries, e ⊨ P⟩

theorem Contract.and {C : Contract} {P Q : Question} (hP : C ⊨ P) (hQ : C ⊨ Q) :
    C ⊨ P ∧ₛ Q :=
  fun e he st h => ⟨hP e he st h, hQ e he st h⟩

/-! ## Library: proved once -/

/-- Frame rule: a term that reads no written slot is unchanged. -/
theorem Term.frame (t : Term α) {st : Step} (hf : st.Framed)
    (hd : ∀ k, t.reads st.call k → k ∉ st.writes) : unchanged t st :=
  t.agree _ _ _ fun k hk => hf k (hd k hk)

/-- Frame rule for a whole contract. -/
theorem Contract.frame (C : Contract) (t : Term α)
    (hd : ∀ e ∈ C.entries, ∀ st, e st → ∀ k, t.reads st.call k → k ∉ st.writes) :
    C ⊨ unchanged t :=
  fun e he st h => t.frame (C.framed e he st h) (hd e he st h)

/-- A property of storage alone. -/
abbrev Invariant := Storage → Prop

def preserves (I : Invariant) : Question := fun st => I st.pre → I st.post

/-- Storage states reachable from `init` by any sequence of calls. -/
inductive Contract.Reachable (C : Contract) (init : Invariant) : Storage → Prop
  | init {s} : init s → C.Reachable init s
  | step {e st} : e ∈ C.entries → e st → C.Reachable init st.pre → C.Reachable init st.post

/-- Invariant rule: true initially and preserved by every entry point means
    true in every reachable state. -/
theorem Contract.invariant (C : Contract) (I : Invariant) {init : Invariant}
    (h0 : ∀ s, init s → I s) (hC : C ⊨ preserves I) :
    ∀ {s}, C.Reachable init s → I s := by
  intro s h
  induction h with
  | init h => exact h0 _ h
  | step he h _ ih => exact hC _ he _ h ih

/-! ## Reading through `m[who]` -/

@[simp] theorem get_at [Stored α] (m : Map α) (w : Who) (c : Call) (s : Storage) :
    (m[w] : Term α).get c s = m.read s (w c) := rfl
@[simp] theorem get_add (t u : Term Int) (c : Call) (s : Storage) :
    (t + u).get c s = t.get c s + u.get c s := rfl
@[simp] theorem get_sub (t u : Term Int) (c : Call) (s : Storage) :
    (t - u).get c s = t.get c s - u.get c s := rfl
@[simp] theorem get_mul (t u : Term Int) (c : Call) (s : Storage) :
    (t * u).get c s = t.get c s * u.get c s := rfl

@[simp] theorem get_at_addr [Stored α] (m : Map α) (a : Addr) (c : Call) (s : Storage) :
    (m[a] : Term α).get c s = m.read s a := rfl

/-- Reading a map entry after writing one. -/
theorem Map.read_set [Stored α] (m : Map α) (s : Storage) (w a : Addr) (v : Val) :
    m.read (s.set (.entry m.name w) v) a = if a = w then Stored.ofVal v else m.read s a := by
  by_cases h : a = w <;> simp [Map.read, Storage.set, h]

theorem Map.read_set_other [Stored α] (m : Map α) (s : Storage) (n : String) (w a : Addr) (v : Val)
    (h : n ≠ m.name) : m.read (s.set (.entry n w) v) a = m.read s a := by
  simp [Map.read, Storage.set, Ne.symm h]

@[simp] theorem Map.read_set_var [Stored α] (m : Map α) (s : Storage) (n : String) (v : Val)
    (a : Addr) : m.read (s.set (.var n) v) a = m.read s a := by
  simp [Map.read, Storage.set]

/-- Reading a variable after writing one. -/
theorem read_set_var [Stored α] (s : Storage) (n n' : String) (v : Val) :
    (read (s.set (.var n) v) n' : α) = if n' = n then Stored.ofVal v else read s n' := by
  by_cases h : n' = n <;> simp [read, Storage.set, h]

@[simp] theorem read_set_entry [Stored α] (s : Storage) (m : String) (w : Addr) (v : Val)
    (n : String) : (read (s.set (.entry m w) v) n : α) = read s n := by
  simp [read, Storage.set]

end Query
