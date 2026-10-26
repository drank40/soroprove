import Lake
open Lake DSL

package «soroban-lean» where
  leanOptions := #[⟨`autoImplicit, false⟩]

@[default_target]
lean_lib SorobanLean where

lean_lib Proofs where
  globs := #[.submodules `Proofs]

lean_lib Tests where
  globs := #[.submodules `Tests]

lean_exe sl where
  root := `Main
