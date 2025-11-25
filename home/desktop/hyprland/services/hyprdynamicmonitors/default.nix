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

  # Create fprintd-control script for pre-hook execution
  fprintdControl = pkgs.writeShellApplication {
    name = "fprintd-control";
    runtimeInputs = with pkgs; [
      glib # provides gdbus for lid state checking
    ];
    text = builtins.readFile ./scripts/fprintd-control.sh;
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
  home.packages = [workspaceManager fprintdControl];

  # Add systemd service to restart HDM after system resume
  # This fixes the undock-while-asleep issue by re-detecting hardware state
  systemd.user.services.hyprdynamicmonitors-resume = {
    Unit = {
      Description = "Restart hyprdynamicmonitors after system resume";
      After = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl --user restart hyprdynamicmonitors.service";
    };
    Install = {
      WantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    };
  };
}
