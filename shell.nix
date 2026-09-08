{ pkgs ? import <nixpkgs> { } }:

let
  llvm = pkgs.llvmPackages_18.llvm;

  # The cargo-installed `stellar` CLI is built against gcc 14's libstdc++ and
  # wants CXXABI_1.3.15. nix-ld only offers gcc 13's, so `stellar contract
  # build` dies with:
  #   libstdc++.so.6: version `CXXABI_1.3.15' not found
  # Putting gcc 14's lib on the search path fixes it. libstdc++ is backward
  # compatible, so shadowing the older one is safe for everything else here.
  stdcxx = pkgs.lib.makeLibraryPath [ pkgs.gcc14.cc.lib ];
in
pkgs.mkShell {
  # llvm-config, found by llvm-sys via LLVM_SYS_181_PREFIX.
  nativeBuildInputs = [ llvm.dev ];
  # inkwell's build.rs links libffi unconditionally on Linux.
  buildInputs = [ pkgs.libffi ];

  LLVM_SYS_181_PREFIX = llvm.dev;

  shellHook = ''
    export LD_LIBRARY_PATH="${stdcxx}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';
}
