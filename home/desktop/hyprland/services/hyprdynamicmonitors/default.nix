{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  # Create workspace-manager script with proper dependencies
  workspaceManager = pkgs.writeShellApplication {
    name = "workspace-manager";
    runtimeInputs = with pkgs; [
      glib # provides gdbus for lid state checking
    ];
    text = builtins.readFile ./scripts/workspace-manager.sh;
  };

  # Use config.toml directly (workspace-manager is in PATH, no substitutions needed)
  configFile = ./config.toml;
in {
  imports = [inputs.hyprdynamicmonitors.homeManagerModules.default];

  # Configure hyprdynamicmonitors with systemd integration
  home.hyprdynamicmonitors = {
    inherit configFile;
    enable = true;
    extraFlags = ["--enable-lid-events"];
  };

  # Deploy profiles
  xdg.configFile = {
    "hyprdynamicmonitors/profiles".source = ./profiles;
  };

  # Add scripts to PATH
  home.packages = [workspaceManager];

  # Add upower to hyprdynamicmonitors-prepare PATH to fix "upower not found" warning
  systemd.user.services.hyprdynamicmonitors-prepare.Service.Environment = [
    "PATH=${lib.makeBinPath [pkgs.upower]}:$PATH"
  ];

  # NOTE: HDM restart on resume is handled by the system-level service in
  # nixos/laptop/suspend-handling.nix (hyprdynamicmonitors-resume).
  # That service also handles phantom monitor cleanup, eDP-1 enable, and DPMS.
  # Having a duplicate user-level service caused race conditions.
}
