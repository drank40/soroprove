import StellarLean.AnswerAttr
import StellarLean.Query

/-
  `answer`: prove a question without choosing a strategy.

  Everything `answer` may use is in the `answer` fact set:
  * the question bricks of `Query` (tagged below, once);
  * facts about each contract, tagged `@[answer]` next to the contract model.
    A WASM → Lean converter would generate these: the list of entry points,
    each precondition, and the effect of each entry point on storage.

  New vocabulary (a brick or invariant you define yourself) joins the set by
  tagging it `@[answer]`.
-/

namespace Query

open Spec (Addr)

/-! ## The bricks, for `answer` -/

attribute [answer] unchanged decreases increases neverDecreases changesBy returns signedBy
  isCaller isRecipient calls dropsAtMost gainsAtLeast Question.and Question.or Question.all Question.except Question.given
  preserves caller recipient amount

attribute [answer =] get_at get_at_addr get_add get_sub get_mul ofVal_int ofVal_none

theorem get_var [Stored α] (name : String) (c : Call) (s : Storage) :
    (var name : Term α).get c s = Stored.ofVal (s (.var name)) := rfl

attribute [answer =] get_var

theorem get_total (m : Map Int) (c : Call) (s : Storage) :
    m.total.get c s = (c.holders.map (m.read s)).sum := rfl

attribute [answer =] get_total

/-! ## Sums over holders

  Lemmas about sums need named functions: `grind` cannot match a lemma whose
  statement contains a lambda. -/

/-- `d` at `w`, 0 elsewhere. -/
def only (w : Addr) (d : Int) : Addr → Int := fun a => if a = w then d else 0

/-- Pointwise `f - g + k`. -/
def diff (f g k : Addr → Int) : Addr → Int := fun a => f a - g a + k a

theorem sum_diff (hs : List Addr) (f g k : Addr → Int) :
    (hs.map (diff f g k)).sum = (hs.map f).sum - (hs.map g).sum + (hs.map k).sum := by
  induction hs <;> grind [diff]

theorem sum_only_absent (hs : List Addr) (w : Addr) (d : Int) (hw : w ∉ hs) :
    (hs.map (only w d)).sum = 0 := by
  induction hs <;> grind [only]

@[answer =] theorem sum_only (hs : List Addr) (w : Addr) (d : Int) (hnd : hs.Nodup) (hw : w ∈ hs) :
    (hs.map (only w d)).sum = d := by
  induction hs <;> grind [only, sum_only_absent]

/-! ## Steps of a contract -/

/-- `st` is a step of one of `C`'s entry points. -/
def Contract.Steps (C : Contract) (st : Step) : Prop := ∃ e ∈ C.entries, e st

theorem Contract.models_of_steps {C : Contract} {P : Question}
    (h : ∀ st, C.Steps st → P st) : C ⊨ P :=
  fun e he st hst => h st ⟨e, he, hst⟩

/-! ## Reading a failed attempt

  When `grind` fails, its message contains values that satisfy every fact it
  knows (the `[assign]` lines). Renamed into question vocabulary, they describe
  a call that breaks the question, as far as `grind` can tell. -/

/-- `s` contains `sub`. -/
def hasSub (s sub : String) : Bool := (s.splitOn sub).length > 1

/-- Question vocabulary for a term about the step `st`. -/
def readableTerm (t : String) : String :=
  -- Field accesses first, so `st.call.caller st.call.args.amt` is not read as
  -- `caller st.call`.
  let t := [("st.call.caller", "caller"), ("st.call.args.to", "to"), ("st.call.args.amt", "amount"),
            ("caller st.call", "caller"), ("recipient st.call", "to"), ("amount st.call", "amount"),
            ("(List.map (", ""), (") st.call.holders).sum", " (total)"),
            ("st.pre", "before"), ("st.post", "after"), ("st.ret", "result")].foldl
    (fun t (a, b) => t.replace a b) t
  match t.splitOn " " with
  | [f, w, who] =>
    if hasSub f ".read" then
      let m := f.replace ".read" ""
      if who == "(total)" then s!"{m}.total {w}"
      else s!"{m}[{(who.replace "(" "").replace ")" ""}] {w}"
    else t
  | _ => t

/-- Internal terms that only repeat or encode other lines. -/
def noise (t : String) : Bool :=
  hasSub t "Stored.ofVal" || hasSub t ".get " || hasSub t "fun " || hasSub t "✝" ||
    hasSub t "only " || hasSub t "diff " || hasSub t "holders" ||
    t.all fun c => c.isUpper || c.isDigit || c == '_'

/-- The `[assign]` lines of a `grind` failure, readable and without repeats:
    the call first, then storage. `strip` lists namespace prefixes to drop. -/
def readableModel (strip : List String) (msg : String) : List String := Id.run do
  let mut seen : List String := []
  let mut call : List String := []
  let mut storage : List String := []
  for line in msg.splitOn "\n" do
    match line.splitOn "[assign] " with
    | [_, rest] =>
      match rest.splitOn " := " with
      | [term, value] =>
        let t := readableTerm (strip.foldl (fun t ns => t.replace ns "") term.trimAscii.toString)
        unless noise t || seen.contains t do
          seen := t :: seen
          let l := s!"  {t} = {value.trimAscii.toString}"
          if hasSub t " " || hasSub t "[" then storage := storage ++ [l] else call := call ++ [l]
      | _ => pure ()
    | _ => pure ()
  return call ++ storage

/-! ## The tactic -/

/-- Answer a question about a contract. The strategy follows from the shape:
    * a property of every reachable state: the invariant rule, then `grind`
      on the starting states and on each step;
    * `C ⊨ question`: look at any step `st` of any entry point;
    * anything else: `grind` with the `answer` facts.
    If no strategy proves it, the error shows a call that breaks the question,
    as far as `answer` can tell. -/
syntax "answer" : tactic

open Lean Elab Tactic in
-- `hygiene false` so `answer` names the fact set and `st` names the step.
set_option hygiene false in
elab_rules : tactic
  | `(tactic| answer) => do
    -- Each strategy: a setup that only applies to the right shape of question,
    -- then the proof search.
    let strategies : List (TSyntax `tactic × TSyntax `tactic) := [
      (← `(tactic| refine Contract.invariant _ _ ?_ ?_ ‹Contract.Reachable _ _ _›),
       ← `(tactic| ((focus (intro _ _; grind [answer]));
                    (focus (refine Contract.models_of_steps fun st _ => ?_; grind [answer]))))),
      (← `(tactic| refine Contract.models_of_steps fun st _ => ?_),
       ← `(tactic| grind [answer])),
      (← `(tactic| skip),
       ← `(tactic| grind [answer]))]
    -- The failure of the first strategy whose setup applied is the one to report.
    let mut relevant : Option Exception := none
    for (setup, search) in strategies do
      let saved ← saveState
      try evalTactic setup
      catch _ => saved.restore; continue
      try
        evalTactic search
        return
      catch ex =>
        if relevant.isNone then relevant := some ex
        saved.restore
    let some ex := relevant | throwError "answer: no strategy applies to this question."
    if (← getMainTarget).isAppOf ``Exists then
      throwError "answer: could not prove this. It asks for an example call to exist, \
        and `answer` cannot construct examples yet: give the call explicitly."
    -- Drop the namespaces that are open here, longest first.
    let opened := (← getOpenDecls).filterMap fun
      | .simple ns [] => some ns
      | _ => none
    let nss := ((← getCurrNamespace) :: opened).flatMap fun ns =>
      ns.components.length.fold (init := []) fun k _ acc =>
        (ns.components.take (k + 1)).foldl Name.append .anonymous :: acc
    let strip := (nss.map (toString · ++ ".")).mergeSort (·.length ≥ ·.length)
    let model := readableModel strip (← ex.toMessageData.toString)
    if model.isEmpty then
      throwError "answer: could not prove this, and found no example that breaks it.\n\
        It may need facts `answer` does not have: tag them with `@[answer]`."
    throwError "answer: could not prove this. A call that breaks it, as far as `answer` can tell:\n\
      {"\n".intercalate model}\n\
      If the question is true after all, `answer` is missing a fact: tag it with `@[answer]`."

end Query
