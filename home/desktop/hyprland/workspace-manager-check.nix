# Regression suite for workspace-manager: runs the shipped script against a
# stub hyprctl, with no noctalia process (the state after a resume crash).
{pkgs}: let
  workspaceManager = import ./services/hyprdynamicmonitors/workspace-manager.nix {inherit pkgs;};
in
  pkgs.runCommand "workspace-manager-check" {
    nativeBuildInputs = with pkgs; [
      bats
      bash
      coreutils
      gnugrep
    ];
  } ''
    export WORKSPACE_MANAGER=${workspaceManager}/bin/workspace-manager
    bats --tap ${./tests/workspace-manager.bats}
    touch $out
  ''
