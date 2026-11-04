# Regression suite for aegis-lock-guard: runs the shipped text (state lib plus
# guard) against stubbed systemctl/journalctl/aegis-lock and a dummy client.
{pkgs}: let
  guard = import ./scripts/aegis-lock-scripts.nix {inherit pkgs;} "aegis-lock-guard";
in
  pkgs.runCommand "aegis-lock-guard-check" {
    nativeBuildInputs = with pkgs; [
      bats
      bash
      coreutils
      procps
      gnugrep
    ];
  } ''
    export GUARD=${guard}/bin/aegis-lock-guard
    bats --tap ${./tests/aegis-lock-guard.bats}
    touch $out
  ''
