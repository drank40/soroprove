import SorobanLean.Env.HostFns
open Soroban.Env

/-- The table has every env.json function. -/
example : HostFn.all.size = 202 := by decide +kernel

/-- Import resolution is the inverse of (module, export) for every host fn. -/
example : HostFn.all.all (fun f => HostFn.resolve f.module.exportName f.exportName == some f) = true := by decide +kernel

/-- Spot checks against env.json (context module "x", int module "i"). -/
example : HostFn.resolve "x" "_" = some .log_from_linear_memory := by decide +kernel
example : HostFn.log_from_linear_memory.arity = 4 := by decide +kernel
