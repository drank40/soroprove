-- Conformance driver, appended after `slice --lean check` (the model and its
-- per-entrypoint checkers) and before the harness's observations.
--
-- For each observed successful invocation it evaluates the model's conjuncts
-- and its post state under three samples of the open values `u : Unk`:
--   * a conjunct false under every sample is reported (a definite failure if
--     the conjunct doesn't mention `u`, otherwise "unconfirmed");
--   * a post value (or presence bit, or balance) the samples agree on must
--     equal the observed one.
-- A step the model rejects means the model does NOT over-approximate the
-- contract there: a bug in the reconstruction.
open Contract

structure Obs where
  entry    : String
  retKnown : Bool
  step     : Step
  keys     : List (Key × Int)   -- observed after the call: values, presence bits, balances

def tbl (l : List (String × Int)) : String → Int := fun n => (l.lookup n).getD 0
def mkStorage (l : List (Key × Int)) : Storage := fun k => (l.lookup k).getD 0

def pick (n j : Nat) : Int :=
  match n with
  | 0 => 0
  | 1 => 1000000000000 + j
  | _ => -1000000000000 - j

def Unk.sample (n : Nat) : Unk :=
  { i := pick n, g := pick n,
    b := fun j => match n with | 0 => true | 1 => false | _ => j % 2 == 0,
    k := fun j => .var s!"?{n}.{j}",
    s := fun j _ => pick n (j + 7) }

abbrev Checker := Step → Unk → List (String × Bool) × Storage × List Key × Bool

/-- The model's verdicts on one observation: what it fails to admit. -/
def failures (chk : Checker) (o : Obs) : List String :=
  let rs := [0, 1, 2].map fun n => chk o.step (Unk.sample n)
  let r0 := rs.headD ([], fun _ => 0, [], false)
  let conj := (List.range r0.1.length).filterMap fun i =>
    let lab := (r0.1.getD i ("", true)).1
    if lab == "ret" && !o.retKnown then none
    else if rs.all (fun r => (r.1.getD i ("", true)).2 == false) then
      some s!"`{lab}` is false"
    else none
  let post := if r0.2.2.2 then [] else
    -- the model writes a key the contract didn't keep: its presence bit is observed 0.
    let written : List Key := r0.2.2.1.filter fun k => match k with
      | .has _ => !(o.keys.any (·.1 == k))
      | _ => false
    let expect : List (Key × Int) := o.keys ++ written.map (fun k => (k, 0))
    expect.filterMap fun kv =>
      let ms := rs.map (fun r => r.2.1 kv.1)
      let m := ms.headD 0
      if ms.all (· == m) && m != kv.2 then some s!"post {reprStr kv.1} = {m}, observed {kv.2}" else none
  conj ++ post

/-- How much of an observation the model pins down: (conjuncts decided under
    every sample, observed values it determines). -/
def decided (chk : Checker) (o : Obs) : Nat × Nat :=
  let rs := [0, 1, 2].map fun n => chk o.step (Unk.sample n)
  let r0 := rs.headD ([], fun _ => 0, [], false)
  let c := (List.range r0.1.length).countP fun i => rs.all (fun r => (r.1.getD i ("", true)).2 == (r0.1.getD i ("", true)).2)
  let p := if r0.2.2.2 then 0 else o.keys.countP fun kv => rs.all (fun r => r.2.1 kv.1 == r0.2.1 kv.1)
  (c, p)

def report (obs : List Obs) : IO Unit := do
  let mut bad := 0
  for (name, chk) in checkers do
    let os := obs.filter (·.entry == name)
    let fs := os.filterMap fun o => match failures chk o with
      | [] => none
      | f => some f
    bad := bad + fs.length
    let (c, p) := os.foldl (fun (a, b) o => let (x, y) := decided chk o; (a + x, b + y)) (0, 0)
    IO.println s!"{name}: {os.length} steps, {os.length - fs.length} admitted ({c} conjuncts decided, {p} observed values determined)"
    for f in fs.take 3 do
      for m in f.take 4 do
        IO.println s!"    {m}"
      IO.println "    --"
  IO.println s!"RESULT {if bad == 0 then "ok" else "FAIL"} ({obs.length} steps, {bad} not admitted)"
