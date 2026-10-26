/-
Network configuration from a `ConfigUpgradeSet` (the oracle's `load_net`,
difftest/src/bin/e2e_oracle.rs:14-29) and budget construction
(`Budget::try_from_configs`, budget.rs).
-/
import SorobanLean.Host.Budget

namespace Soroban
open Xdr

def base64Decode (s : String) : Option ByteArray := Id.run do
  let alpha := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let idx (c : Char) : Option Nat := (alpha.toList.findIdx? (· == c))
  let cs := s.toList.filter (fun c => !c.isWhitespace)
  let mut out := ByteArray.empty
  let mut acc := 0
  let mut bits := 0
  for c in cs do
    if c == '=' then break
    let some v := idx c | return none
    acc := (acc <<< 6) ||| v
    bits := bits + 6
    if bits ≥ 8 then
      bits := bits - 8
      out := out.push ((acc >>> bits) % 256).toUInt8
      acc := acc % (2 ^ bits)
  return some out

structure NetConfig where
  cpu : ContractCostParams
  mem : ContractCostParams
  cpuLimit : Nat
  memLimit : Nat
  archival : StateArchivalSettings

def NetConfig.ofUpgradeSet (set : ConfigUpgradeSet) : Option NetConfig := do
  let mut cpu := none; let mut mem := none; let mut cl := 0; let mut ml := 0; let mut sa := none
  for e in set.updatedEntry do
    match e with
    | .CONFIG_SETTING_CONTRACT_COST_PARAMS_CPU_INSTRUCTIONS p => cpu := some p
    | .CONFIG_SETTING_CONTRACT_COST_PARAMS_MEMORY_BYTES p => mem := some p
    | .CONFIG_SETTING_CONTRACT_COMPUTE_V0 c => cl := c.txMaxInstructions.toInt.toNat; ml := c.txMemoryLimit.toNat
    | .CONFIG_SETTING_STATE_ARCHIVAL s => sa := some s
    | _ => pure ()
  pure { cpu := ← cpu, mem := ← mem, cpuLimit := cl, memLimit := ml, archival := ← sa }

def NetConfig.budget (n : NetConfig) : Option Budget := Budget.ofConfigs n.cpuLimit n.memLimit n.cpu n.mem

end Soroban
