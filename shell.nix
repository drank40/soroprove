{ pkgs ? import <nixpkgs> { } }:

let
  llvm = pkgs.llvmPackages_18.llvm;
in
pkgs.mkShell {
  # llvm-config, found by llvm-sys via LLVM_SYS_181_PREFIX.
  nativeBuildInputs = [ llvm.dev ];
  # inkwell's build.rs links libffi unconditionally on Linux.
  buildInputs = [ pkgs.libffi ];

  LLVM_SYS_181_PREFIX = llvm.dev;
}
