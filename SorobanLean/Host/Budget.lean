/-
The host budget (src: vendor/rs-soroban-env/soroban-env-host/src/budget.rs,
budget/{dimension.rs,model.rs,limits.rs}).

Shadow-mode accounting (used only for diagnostics, budget.rs:1418-1460) is not
observable and is not modelled.
-/
import SorobanLean.Xdr.Codec
import SorobanLean.Val
import SorobanLean.Wasm.Compile

namespace Soroban

/-- u64 saturating arithmetic (Rust `saturating_*`). -/
def U64MAX : Nat := 2^64 - 1
@[inline] def satAdd (a b : Nat) : Nat := min (a + b) U64MAX
@[inline] def satMul (a b : Nat) : Nat := min (a * b) U64MAX
@[inline] def satSub (a b : Nat) : Nat := a - b   -- Nat truncation = saturating_sub at 0

/-- src: budget/model.rs:14-15 (COST_MODEL_LIN_TERM_SCALE_BITS = 7). -/
def LIN_TERM_SCALE_BITS : Nat := 7

/-- src: budget/model.rs `MeteredCostComponent` (const_term, lin_term scaled by 2^7). -/
structure CostModel where
  constTerm : Nat := 0
  linTerm : Nat := 0   -- ScaledU64 raw value
  deriving Repr, Inhabited, DecidableEq

/-- src: budget/model.rs `impl HostCostModel for MeteredCostComponent::evaluate`. -/
def CostModel.evaluate (cm : CostModel) (iterations : Nat) (input : Option Nat) : Nat :=
  let constTerm := satMul cm.constTerm iterations
  match input with
  | none => constTerm
  | some i =>
    if cm.linTerm = 0 then constTerm
    else satAdd constTerm ((satMul (satMul cm.linTerm i) iterations) >>> LIN_TERM_SCALE_BITS)

/-- src: budget/model.rs `TryFrom<&ContractCostParamEntry>`: negative terms → (Context, InvalidInput). -/
def CostModel.ofEntry (e : Xdr.ContractCostParamEntry) : Option CostModel :=
  if e.constTerm < 0 || e.linearTerm < 0 then none
  else some { constTerm := e.constTerm.toInt.toNat, linTerm := e.linearTerm.toInt.toNat }

/-- One budget dimension (src: budget/dimension.rs `BudgetDimension`). -/
structure Dimension where
  models : Array CostModel
  limit : Nat
  netCount : Nat := 0
  peakCount : Nat := 0
  deriving Repr, Inhabited

/-- Per cost-type reporting tracker (src: budget.rs:27-32 `CostTracker`). Not
    observable by contracts; kept so differential tests can localise mismatches. -/
structure CostTracker where
  iterations : Nat := 0
  inputs : Option Nat := none
  cpu : Nat := 0
  mem : Nat := 0
  deriving Repr, Inhabited

structure Budget where
  cpu : Dimension
  mem : Dimension
  trackers : Array CostTracker
  /-- `depth_limit` (src: budget/limits.rs:17 DEFAULT_HOST_DEPTH_LIMIT = 100). -/
  depthLimit : Nat := 100
  /-- wasmi fuel costs (src: budget/wasmi_helper.rs:126-134). -/
  fuelCosts : Wasm.FuelCosts := Wasm.sorobanFuelCosts
  /-- Differential-testing aid: when `tracing`, every charge is appended to `log`
      (mirrors the `CHARGE ty it input` lines of the patched oracle). Not observable. -/
  tracing : Bool := false
  /-- `false` = the unmetered model used for functional proofs: every charge is a no-op
      and the limits read by the VM (fuel, memory growth) are unbounded. The metered
      model (`true`, the default) is the one differentially tested against the host. -/
  metered : Bool := true
  log : Array (Xdr.ContractCostType × Nat × Option Nat) := #[]
  deriving Inhabited

def numCostTypes : Nat := 95  -- ContractCostType::variants().len() in stellar-xdr 30.0.0 (xdr.json member count)

def costIdx (t : Xdr.ContractCostType) : Nat := t.toI32.toInt.toNat

/-- Tracker inputs start as `Some(0)` exactly for these types (src: budget.rs:55-171,
    generated from the source match by script). -/
def inputIsSome : Xdr.ContractCostType → Bool
  | .MemAlloc => true
  | .MemCpy => true
  | .MemCmp => true
  | .ValSer => true
  | .ValDeser => true
  | .ComputeSha256Hash => true
  | .VerifyEd25519Sig => true
  | .VmInstantiation => true
  | .VmCachedInstantiation => true
  | .ComputeKeccak256Hash => true
  | .ChaCha20DrawBytes => true
  | .ParseWasmInstructions => true
  | .ParseWasmFunctions => true
  | .ParseWasmGlobals => true
  | .ParseWasmTableEntries => true
  | .ParseWasmTypes => true
  | .ParseWasmDataSegments => true
  | .ParseWasmElemSegments => true
  | .ParseWasmImports => true
  | .ParseWasmExports => true
  | .ParseWasmDataSegmentBytes => true
  | .InstantiateWasmFunctions => true
  | .InstantiateWasmGlobals => true
  | .InstantiateWasmTableEntries => true
  | .InstantiateWasmDataSegments => true
  | .InstantiateWasmElemSegments => true
  | .InstantiateWasmImports => true
  | .InstantiateWasmExports => true
  | .InstantiateWasmDataSegmentBytes => true
  | .Bls12381G1Msm => true
  | .Bls12381HashToG1 => true
  | .Bls12381G2Msm => true
  | .Bls12381HashToG2 => true
  | .Bls12381Pairing => true
  | .Bls12381FrPow => true
  | .Bn254G1Msm => true
  | .Bn254Pairing => true
  | .Bn254FrPow => true
  | .VerifyMlDsa44Sig => true
  | .VerifyMlDsa65Sig => true
  | .VerifyMlDsa87Sig => true
  | _ => false

/-- src: budget/dimension.rs `try_from_config`: one model per provided param entry,
    remaining types default to zero. -/
def Dimension.ofParams (ps : Array Xdr.ContractCostParamEntry) (limit : Nat) : Option Dimension := do
  let mut models := Array.replicate numCostTypes ({} : CostModel)
  for h : i in [0:ps.size] do
    let m ← CostModel.ofEntry ps[i]
    if i < models.size then models := models.set! i m
  pure { models, limit }

def Budget.ofConfigs (cpuLimit memLimit : Nat) (cpuParams memParams : Array Xdr.ContractCostParamEntry) : Option Budget := do
  pure { cpu := ← Dimension.ofParams cpuParams cpuLimit, mem := ← Dimension.ofParams memParams memLimit,
         trackers := (Array.range numCostTypes).map fun i =>
           { inputs := if (Xdr.ContractCostType.ofI32? (Int32.ofNat i)).any inputIsSome then some 0 else none } }

/-- The budget-exceeded error (src: budget/dimension.rs `check_budget_limit`). -/
def budgetExceeded : Val := Val.fromError .Budget .ExceededLimit

/-- `BudgetDimension::charge` then `check_budget_limit` (dimension.rs). Returns the
    amount charged. -/
def Dimension.charge (d : Dimension) (ty : Nat) (iterations : Nat) (input : Option Nat) :
    Nat × Dimension :=
  let amount := (d.models[ty]?.getD default).evaluate iterations input
  let net := satAdd d.netCount amount
  (amount, { d with netCount := net, peakCount := max d.peakCount net })

def Dimension.overLimit (d : Dimension) : Bool := d.netCount > d.limit
def Dimension.remaining (d : Dimension) : Nat := satSub d.limit d.netCount

/-- `BudgetImpl::charge` (budget.rs:246-295): tracker, then CPU charge + check,
    then memory charge + check. The mutated budget is returned together with the
    error, if any: on a CPU overrun the CPU counters are already bumped and the
    memory dimension is untouched; on a memory overrun both are bumped. -/
def Budget.charge (b : Budget) (ty : Xdr.ContractCostType) (iterations : Nat) (input : Option Nat) :
    Budget × Option Val :=
  if !b.metered then (b, none) else
  let b := if b.tracing then { b with log := b.log.push (ty, iterations, input) } else b
  let i := costIdx ty
  let tr := b.trackers[i]?.getD default
  let tr := { tr with iterations := satAdd tr.iterations iterations }
  let inputs? : Option (Option Nat) := match tr.inputs, input with
    | none, none => some none
    | some t, some x => some (some (satAdd t (satMul x iterations)))
    | _, _ => none
  match inputs? with
  | none => ({ b with trackers := b.trackers.set! i tr }, some (Val.fromError .Budget .InternalError))
  | some inputs =>
  let tr := { tr with inputs }
  let (cpuAmt, cpu) := b.cpu.charge i iterations input
  let tr := { tr with cpu := satAdd tr.cpu cpuAmt }
  let b := { b with cpu, trackers := b.trackers.set! i tr }
  if cpu.overLimit then (b, some budgetExceeded) else
  let (memAmt, mem) := b.mem.charge i iterations input
  let tr := { tr with mem := satAdd tr.mem memAmt }
  let b := { b with mem, trackers := b.trackers.set! i tr }
  if mem.overLimit then (b, some budgetExceeded) else (b, none)

/-- `get_wasmi_fuel_remaining` (budget.rs:296-312): cpu remaining / max(1, WasmInsnExec const). -/
def Budget.wasmiFuelRemaining (b : Budget) : Nat :=
  if !b.metered then U64MAX else
  let cpf := max 1 ((b.cpu.models[0]?.getD default).constTerm)
  b.cpu.remaining / cpf

/-- `get_memory_cost` (budget.rs:1408-1416 → dimension evaluate, no charge). -/
def Budget.memoryCost (b : Budget) (ty : Xdr.ContractCostType) (input : Option Nat) : Nat :=
  (b.mem.models[costIdx ty]?.getD default).evaluate 1 input

/-- Memory refund (dimension.rs `refund`): net decreases (saturating), peak unchanged. -/
def Budget.refundMem (b : Budget) (amount : Nat) : Budget :=
  { b with mem := { b.mem with netCount := satSub b.mem.netCount amount } }

end Soroban
