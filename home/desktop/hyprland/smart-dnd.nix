{
  config,
  lib,
  pkgs,
  ...
}: let
  smart-dnd-audio = pkgs.writeShellScriptBin "smart-dnd-audio" (builtins.readFile ./scripts/smart-dnd-audio.sh);
in {
  # Make the script available
  home.packages = [smart-dnd-audio];

  # Create systemd service to run the monitor
  systemd.user.services.smart-dnd-audio = {
    Unit = {
      Description = "Smart DND Audio Sync - Mutes apps during DND except during calls";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };

    Service = {
      Type = "simple";
      ExecStart = "${smart-dnd-audio}/bin/smart-dnd-audio monitor";
      Restart = "on-failure";
      RestartSec = 5;
      # Prevent shutdown hang
      TimeoutStopSec = "3s";

      # Dependencies
      Environment = [
        "PATH=${lib.makeBinPath [pkgs.coreutils pkgs.pulseaudio pkgs.jq pkgs.libnotify pkgs.hyprland]}"
      ];
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };

  # Add keybindings for manual control
  wayland.windowManager.hyprland.settings = {
    bind = [
      # Manual override toggle
      "SUPER SHIFT, F1, exec, ${smart-dnd-audio}/bin/smart-dnd-audio override"
      "SUPER SHIFT, F2, exec, ${smart-dnd-audio}/bin/smart-dnd-audio unoverride"
    ];
  };
}
