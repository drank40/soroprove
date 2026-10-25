import Lake
open Lake DSL

package prove

-- Trusted: emitted model (stellar-diver) and the locked spec (developer).
lean_lib Gen where globs := #[.submodules `Gen]
lean_lib Spec where globs := #[.submodules `Spec]
-- Untrusted: the agent's proofs.
lean_lib Solution
-- The checker comparing Solution against Spec.Invariants.
lean_exe check where
  root := `Check
  supportInterpreter := true
