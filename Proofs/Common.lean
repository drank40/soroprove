/-
Shared definitions for proofs about real contract invocations: the mainnet budget and
the host state `invoke_host_function` starts from.
-/
import Proofs.MainnetBudget

namespace Proofs
open Soroban

/-- The budget `invoke_host_function` is given in the oracle runs: mainnet cost
    parameters and per-transaction limits (difftest/src/bin/e2e_oracle.rs:14-40), from the
    literals of `MainnetBudget.lean` (`mainnet_params_eq`: equal to the decoded settings
    bytes). -/
def mainnetBudget : Budget :=
  (Budget.ofConfigs mainnetCpuLimit mainnetMemLimit mainnetCpuParams mainnetMemParams).getD default

/-- `Host::with_storage_and_budget` before any setter: an empty host around the budget. -/
def initialHost : HostState := { budget := mainnetBudget, storage := default, cells := #[] }

/-- Run `invoke_host_function` with Lean gas 1000. -/
def runE2E (inp : E2EInput) : Except HErr E2EResult × HostState :=
  runHost (invokeHostFunction 1000 inp) initialHost

def resultBytes? (inp : E2EInput) : Option ByteArray :=
  match (runE2E inp).1 with
  | .ok r => r.result.toOption
  | .error _ => none

def cpuConsumed (inp : E2EInput) : Nat := (runE2E inp).2.budget.cpu.netCount
def memConsumed (inp : E2EInput) : Nat := (runE2E inp).2.budget.mem.peakCount

/-- The unmetered model: same host, budget switched off (`Budget.metered = false`).
    Functional properties are proved on this model: behaviour assuming the invocation
    does not run out of budget. -/
def initialHostU : HostState := { initialHost with budget := { mainnetBudget with metered := false } }

def runE2EU (inp : E2EInput) : Except HErr E2EResult × HostState :=
  runHost (invokeHostFunction 1000 inp) initialHostU

def resultBytesU? (inp : E2EInput) : Option ByteArray :=
  match (runE2EU inp).1 with
  | .ok r => r.result.toOption
  | .error _ => none

end Proofs
