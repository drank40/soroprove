/-
The Soroprove state machine: one contract invocation as transitions over syscalls.

The machine state has three first-class components besides the contract's own storage:
* `Balances` — global token state: every traced SEP-41 token's balances and allowances,
  for every address;
* `Auths` — what was authorized: passed `require_auth*` checks and
  `authorize_as_curr_contract` grants, together with the role mapping (`Role`), which
  ties privileged addresses to storage keys;
* `flows` — the token balance transitions (value movements) performed, in order.

Semantics follow SorobanLean/Spec/Syscalls.lean (sources cited there). A run is a trace
of syscalls; it ends by returning (the effects commit) or failing (everything reverts).
-/
import SorobanLean.Spec.Syscalls

namespace Soroban.Prove
open SHost (CVal CList Addr SType)
open Soroban.Spec

/-! ## Global token balances -/

/-- The state of every traced token. -/
structure Balances where
  tok : Addr → Sep41.St Addr

namespace Balances
def bal (b : Balances) (token holder : Addr) : Int := (b.tok token).bal holder
def allowance (b : Balances) (seq : Nat) (token from_ spender : Addr) : Int :=
  (b.tok token).allowance seq from_ spender
def set (b : Balances) (token : Addr) (s : Sep41.St Addr) : Balances :=
  ⟨fun t => if t = token then s else b.tok t⟩
end Balances

/-- One token balance transition. -/
structure Flow where
  token : Addr
  op : Sep41.Call Addr

/-- The address a flow debits (`from`), and who had to authorize it. -/
def Flow.debited (f : Flow) : Addr :=
  match f.op with
  | .transfer fr .. | .transferFrom _ fr .. | .burn fr _ | .burnFrom _ fr _ | .approve fr .. => fr

/-! ## Roles and auths -/

def CList.toList : CList → List CVal
  | .nil => []
  | .cons h t => h :: CList.toList t

/-- Where a role's members are stored in the contract's storage. -/
inductive RoleKey where
  /-- `storage[key] = Address` (e.g. `DataKey::Admin ↦ addr`). -/
  | single (t : SType) (key : CVal)
  /-- `storage[key] = Vec<Address>`. -/
  | list (t : SType) (key : CVal)
  /-- `storage[(tag, addr)]` is present (e.g. `DataKey::Minter(addr) ↦ true`; a
      `contracttype` enum variant with data is `Vec[Symbol(tag), addr]`). -/
  | keyed (t : SType) (tag : CVal)

/-- A role: a name (classified automatically or given manually) and where it lives. -/
structure Role where
  name : String
  key : RoleKey

abbrev Storage := SType → CVal → Option CVal

def RoleKey.holds (st : Storage) (a : Addr) : RoleKey → Prop
  | .single t k => st t k = some (.addr a)
  | .list t k => ∃ xs, st t k = some (.vec xs) ∧ CVal.addr a ∈ CList.toList xs
  | .keyed t tag => (st t (.vec (.cons tag (.cons (.addr a) .nil)))).isSome

/-- How the model sees an address: the contract itself, a holder of some roles, or a user. -/
inductive Who where
  | self
  | privileged (roles : List String)
  | user

/-- What was authorized during the invocation. -/
structure Auths where
  /-- `(address, args)` of every `require_auth*` that passed. -/
  checked : List (Addr × List CVal) := []
  /-- `authorize_as_curr_contract` entries: callees may act as this contract. -/
  grants : List CVal := []

/-! ## The machine -/

inductive Phase where
  | running
  | returned (v : AV)
  | failed (e : Err)

structure Machine where
  phase : Phase := .running
  storage : Storage
  bal : Balances
  auths : Auths := {}
  /-- Pending executable update (applied when the invocation commits). -/
  upgrade : Option Exe := none
  flows : List Flow := []

/-- The roles an address holds now. -/
def Machine.HasRole (m : Machine) (r : Role) (a : Addr) : Prop := r.key.holds m.storage a

def Machine.classify (env : Env) (roles : List Role) (m : Machine) (a : Addr)
    [∀ r : Role, Decidable (m.HasRole r a)] : Who :=
  if a = env.self then .self else
  match roles.filter (fun r => decide (m.HasRole r a)) with
  | [] => .user
  | rs => .privileged (rs.map (·.name))

/-- Token state may change during a call to a contract we do not trace, but without
    grants and without allowances given by `self`, never at `self`'s expense: every SEP-41
    debit of `self` needs `self`'s auth, which only `self` as direct invoker or a grant
    gives (auth.rs:1164-1225). Assumes plain SEP-41 tokens (an admin `clawback` breaks it). -/
def Unknown (env : Env) (m m' : Machine) : Prop :=
  m'.phase = .running ∧ m'.storage = m.storage ∧ m'.auths = m.auths ∧ m'.upgrade = m.upgrade ∧
  m'.flows = m.flows ∧
  (m.auths.grants = [] → (∀ t sp, m.bal.allowance env.seq t env.self sp = 0) →
    ∀ t, m'.bal.bal t env.self ≥ m.bal.bal t env.self ∧
      (m'.bal.tok t).allow env.self = (m.bal.tok t).allow env.self)

def Machine.fail (m : Machine) (e : Err) : Machine := { m with phase := .failed e }

/-- A traced token call is allowed: nonnegative amount, and its authorizer is this
    contract (the direct invoker of the token) or has signed. -/
def TokenOk (env : Env) (op : Sep41.Call Addr) : Prop :=
  0 ≤ op.amount ∧ env.authorizes (some env.self) op.authorizer []

/-- The effect of a successful traced token call. -/
def Machine.tokenCall (m : Machine) (c : Addr) (op : Sep41.Call Addr) (s' : Sep41.St Addr) : Machine :=
  { m with bal := m.bal.set c s', flows := m.flows ++ [⟨c, op⟩] }

def Machine.putS (m : Machine) (t : SType) (k : CVal) (v : Option CVal) : Machine :=
  { m with storage := fun t' k' => if t' = t ∧ k' == k then v else m.storage t' k' }

/-- One transition: a running machine executes a syscall. -/
inductive Step (env : Env) : Machine → Sys → Machine → Prop where
  -- calls
  | callSelf {m f args} (h : m.phase = .running) :
      Step env m (.call env.self f args) (m.fail (.host .Context .InvalidAction))
  | tryCallSelf {m f args} (h : m.phase = .running) : Step env m (.tryCall env.self f args) m
  | callToken {m c f args op s' evs} (h : m.phase = .running) (hc : env.isToken c)
      (hop : sep41Call f args = some op) (hok : TokenOk env op)
      (hs : op.step env.seq (m.bal.tok c) = some (s', evs)) :
      Step env m (.call c f args) (m.tokenCall c op s')
  | tryCallToken {m c f args op s' evs} (h : m.phase = .running) (hc : env.isToken c)
      (hop : sep41Call f args = some op) (hok : TokenOk env op)
      (hs : op.step env.seq (m.bal.tok c) = some (s', evs)) :
      Step env m (.tryCall c f args) (m.tokenCall c op s')
  | callTokenFail {m c f args op e} (h : m.phase = .running) (hc : env.isToken c)
      (hop : sep41Call f args = some op)
      (hno : ¬ (TokenOk env op ∧ (op.step env.seq (m.bal.tok c)).isSome)) :
      Step env m (.call c f args) (m.fail e)
  | tryCallTokenFail {m c f args op} (h : m.phase = .running) (hc : env.isToken c)
      (hop : sep41Call f args = some op)
      (hno : ¬ (TokenOk env op ∧ (op.step env.seq (m.bal.tok c)).isSome)) :
      Step env m (.tryCall c f args) m
  | callOther {m m' c f args} (h : m.phase = .running) (hne : c ≠ env.self)
      (hnt : ¬ (env.isToken c ∧ (sep41Call f args).isSome)) (hu : Unknown env m m') :
      Step env m (.call c f args) m'
  | callOtherFail {m c f args e} (h : m.phase = .running) (hne : c ≠ env.self)
      (hnt : ¬ (env.isToken c ∧ (sep41Call f args).isSome)) :
      Step env m (.call c f args) (m.fail e)
  | tryCallOther {m m' c f args} (h : m.phase = .running) (hne : c ≠ env.self)
      (hnt : ¬ (env.isToken c ∧ (sep41Call f args).isSome)) (hu : Unknown env m m') :
      Step env m (.tryCall c f args) m'
  -- auth
  | requireAuth {m a args} (h : m.phase = .running) (hs : env.signed a args) :
      Step env m (.requireAuth a args) { m with auths := { m.auths with checked := m.auths.checked ++ [(a, args)] } }
  | requireAuthFail {m a args} (h : m.phase = .running) (hs : ¬ env.signed a args) :
      Step env m (.requireAuth a args) (m.fail (.host .Auth .InvalidAction))
  | requireAuthForArgs {m a args} (h : m.phase = .running) (hs : env.signed a args) :
      Step env m (.requireAuthForArgs a args) { m with auths := { m.auths with checked := m.auths.checked ++ [(a, args)] } }
  | requireAuthForArgsFail {m a args} (h : m.phase = .running) (hs : ¬ env.signed a args) :
      Step env m (.requireAuthForArgs a args) (m.fail (.host .Auth .InvalidAction))
  | verifySig {m sch pk msg sig ctx} (h : m.phase = .running) (hs : env.sigOk sch pk msg sig ctx) :
      Step env m (.verifySig sch pk msg sig ctx) m
  | verifySigFail {m sch pk msg sig ctx} (h : m.phase = .running) (hs : ¬ env.sigOk sch pk msg sig ctx) :
      Step env m (.verifySig sch pk msg sig ctx) (m.fail (.host .Crypto .InvalidInput))
  | recover {m d sig rid k} (h : m.phase = .running) (hr : env.recover d sig rid = some k) :
      Step env m (.recoverSecp256k1 d sig rid) m
  | recoverFail {m d sig rid} (h : m.phase = .running) (hr : env.recover d sig rid = none) :
      Step env m (.recoverSecp256k1 d sig rid) (m.fail (.host .Crypto .InvalidInput))
  | grant {m e} (h : m.phase = .running) :
      Step env m (.authorizeAsCurrContract e) { m with auths := { m.auths with grants := m.auths.grants ++ [e] } }
  -- upgrades
  | updateWasm {m hsh} (h : m.phase = .running) (hx : env.wasmExists hsh) :
      Step env m (.updateWasm hsh) { m with upgrade := some (.wasm hsh) }
  | updateWasmFail {m hsh} (h : m.phase = .running) (hx : ¬ env.wasmExists hsh) :
      Step env m (.updateWasm hsh) (m.fail (.host .Storage .MissingValue))
  | updateRef {m o t} (h : m.phase = .running) (hx : env.wasmExists t) :
      Step env m (.updateExecutableRef o t) { m with upgrade := some (.externalRef o t) }
  | updateRefFail {m o t} (h : m.phase = .running) (hx : ¬ env.wasmExists t) :
      Step env m (.updateExecutableRef o t) (m.fail (.host .Storage .MissingValue))
  -- storage
  | put {m k v t} (h : m.phase = .running) : Step env m (.put k v t) (m.putS t k (some v))
  | get {m k t v} (h : m.phase = .running) (hv : m.storage t k = some v) : Step env m (.get k t) m
  | getMissing {m k t} (h : m.phase = .running) (hv : m.storage t k = none) :
      Step env m (.get k t) (m.fail (.host .Storage .MissingValue))
  | has {m k t} (h : m.phase = .running) : Step env m (.has k t) m
  | del {m k t} (h : m.phase = .running) : Step env m (.del k t) (m.putS t k none)
  -- context
  | currentAddress {m} (h : m.phase = .running) : Step env m .currentAddress m
  | failContract {m c} (h : m.phase = .running) : Step env m (.failWithError (.contract c)) (m.fail (.contract c))
  | failHost {m t c} (h : m.phase = .running) :
      Step env m (.failWithError (.host t c)) (m.fail (.host .Context .UnexpectedType))
  | objCmp {m a b} (h : m.phase = .running) : Step env m (.objCmp a b) m

/-- A run: syscalls executed in order, then the contract returns `v` (or a failure ends it). -/
inductive Run (env : Env) : Machine → List Sys → Machine → Prop where
  | ret {m} (v : AV) (h : m.phase = .running) : Run env m [] { m with phase := .returned v }
  | stop {m e} (h : m.phase = .failed e) : Run env m [] m
  | step {m m' m'' sc scs} (h : Step env m sc m') (r : Run env m' scs m'') : Run env m (sc :: scs) m''

/-- What an invocation leaves behind: on failure, the initial state (everything reverts). -/
def commit (init final : Machine) : Machine :=
  match final.phase with
  | .failed e => { init with phase := .failed e }
  | _ => final

/-! ## Basic facts -/

/-- A failed invocation changes no balances, storage, auths or flows. -/
theorem commit_failed {init final : Machine} {e : Err} (h : final.phase = .failed e) :
    (commit init final).bal = init.bal ∧ (commit init final).storage = init.storage ∧
    (commit init final).flows = init.flows ∧ (commit init final).upgrade = init.upgrade := by
  simp [commit, h]

/-- Every recorded flow was allowed: nonnegative, authorized by this contract (as the
    token's direct invoker) or signed by its authorizer. -/
def FlowsAuthorized (env : Env) (m : Machine) : Prop :=
  ∀ fl ∈ m.flows, TokenOk env fl.op

theorem step_flowsAuthorized {env : Env} {m m' : Machine} {sc : Sys}
    (h : Step env m sc m') (hm : FlowsAuthorized env m) : FlowsAuthorized env m' := by
  cases h <;> first
    | exact hm
    | (intro fl hfl; simp only [Machine.fail] at hfl; exact hm fl hfl)
    | (intro fl hfl; simp only [Machine.putS] at hfl; exact hm fl hfl)
    | (rename_i hu; intro fl hfl; rw [hu.2.2.2.2.1] at hfl; exact hm fl hfl)
    | (rename_i hok _; intro fl hfl
       simp only [Machine.tokenCall, List.mem_append, List.mem_singleton] at hfl
       rcases hfl with hfl | rfl
       · exact hm fl hfl
       · exact hok)

/-- Invariant: along any run, every value movement was authorized. -/
theorem run_flowsAuthorized {env : Env} {m m' : Machine} {scs : List Sys}
    (r : Run env m scs m') (hm : FlowsAuthorized env m) : FlowsAuthorized env m' := by
  induction r with
  | ret v _ => exact hm
  | stop _ => exact hm
  | step h _ ih => exact ih (step_flowsAuthorized h hm)

/-- Only token calls and untraced calls touch balances. -/
theorem step_bal_of_not_call {env : Env} {m m' : Machine} {sc : Sys}
    (h : Step env m sc m') (hc : ∀ c f a, sc ≠ .call c f a ∧ sc ≠ .tryCall c f a) : m'.bal = m.bal := by
  cases h <;> first
    | rfl
    | exact absurd rfl (hc _ _ _).1
    | exact absurd rfl (hc _ _ _).2

end Soroban.Prove
