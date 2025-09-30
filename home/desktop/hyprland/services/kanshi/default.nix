{
  lib,
  pkgs,
  ...
}: let
  hyprctl = "${lib.getExe' pkgs.hyprland "hyprctl"}";
  home-ext-left = "desc:Samsung Electric Company S27H85x H4ZM300138";
  home-ext-right = "desc:Samsung Electric Company S27H85x H4ZKB00167";
  work-ext-left-desc = "Dell Inc. DELL P2723DE CC7FH14";
  work-ext-left = "desc:${work-ext-left-desc}";
  work-ext-right-desc = "Dell Inc. DELL P2723DE 4C7FH14";
  work-ext-right = "desc:${work-ext-right-desc}";

  # Helper function to move workspace ranges to monitors
  moveWorkspacesToMonitor = wsRange: monitor: ''
    for ws in {${wsRange}}; do
      ${hyprctl} dispatch workspace $ws && ${hyprctl} dispatch moveworkspacetomonitor $ws ${monitor} || true
    done
  '';

  # Helper function to set workspace persistence
  setWorkspacePersistence = wsRange: persistent: ''
    for ws in {${wsRange}}; do
      ${hyprctl} keyword workspace "$ws,persistent:${
      if persistent
      then "true"
      else "false"
    }" || true
    done
  '';
  undocked-sh = pkgs.writeShellScript "undocked-sh" ''
    # Reset workspace persistence
    ${setWorkspacePersistence "5..10" false}

    # Move workspaces 1-4 to laptop screen
    ${moveWorkspacesToMonitor "1..4" "eDP-1"}

    # Focus workspace 1
    ${hyprctl} dispatch workspace 1

    launch-dock &

    # Start fingerprint daemon for undocked usage
    ${pkgs.systemd}/bin/systemctl start fprintd.service || true
  '';
  home-docked-lid-open-sh = pkgs.writeShellScript "home-docked-lid-open-sh" ''
    # Enable laptop screen for lid-open setup
    ${hyprctl} keyword monitor "eDP-1,2880x1800@120,2560x1440,2.0"

    # Make workspaces 5-8 persistent for dual monitor setup
    ${setWorkspacePersistence "5..8" true}

    # Left monitor: workspaces 1-4
    ${moveWorkspacesToMonitor "1..4" "${home-ext-left}"}

    # Right monitor: workspaces 5-8
    ${moveWorkspacesToMonitor "5..8" "${home-ext-right}"}

    # Laptop screen: workspace 9
    ${hyprctl} dispatch workspace 9 && ${hyprctl} dispatch moveworkspacetomonitor 9 eDP-1 || true

    launch-dock &

    # Start fingerprint daemon when lid is open
    ${pkgs.systemd}/bin/systemctl start fprintd.service || true
  '';
  home-docked-lid-close-sh = pkgs.writeShellScript "home-docked-lid-close-sh" ''
    # Disable laptop screen for lid-close setup
    ${hyprctl} keyword monitor "eDP-1,disable"

    # Make workspaces 5-8 persistent for dual monitor setup
    ${setWorkspacePersistence "5..8" true}

    # Left monitor: workspaces 1-4
    ${moveWorkspacesToMonitor "1..4" "${home-ext-left}"}

    # Right monitor: workspaces 5-8
    ${moveWorkspacesToMonitor "5..8" "${home-ext-right}"}

    launch-dock &

    # Stop fingerprint daemon when lid is closed
    ${pkgs.systemd}/bin/systemctl stop fprintd.service || true
  '';
  work-docked-lid-open-sh = pkgs.writeShellScript "work-docked-lid-open-sh" ''
    # Enable laptop screen for lid-open setup
    ${hyprctl} keyword monitor "eDP-1,2880x1800@120,1280x1440,2.0"

    # Make workspaces 5-8 persistent for dual monitor setup
    ${setWorkspacePersistence "5..8" true}

    # Left monitor: workspaces 1-4
    ${moveWorkspacesToMonitor "1..4" "${work-ext-left}"}

    # Right monitor: workspaces 5-8
    ${moveWorkspacesToMonitor "5..8" "${work-ext-right}"}

    # Laptop screen: workspace 9
    ${hyprctl} dispatch workspace 9 && ${hyprctl} dispatch moveworkspacetomonitor 9 eDP-1 || true

    launch-dock &

    # Start fingerprint daemon when lid is open
    ${pkgs.systemd}/bin/systemctl start fprintd.service || true
  '';
  work-docked-lid-close-sh = pkgs.writeShellScript "work-docked-lid-close-sh" ''
    # Disable laptop screen for lid-close setup
    ${hyprctl} keyword monitor "eDP-1,disable"

    # Make workspaces 5-8 persistent for dual monitor setup
    ${setWorkspacePersistence "5..8" true}

    # Left monitor: workspaces 1-4
    ${moveWorkspacesToMonitor "1..4" "${work-ext-left}"}

    # Right monitor: workspaces 5-8
    ${moveWorkspacesToMonitor "5..8" "${work-ext-right}"}

    launch-dock &

    # Stop fingerprint daemon when lid is closed
    ${pkgs.systemd}/bin/systemctl stop fprintd.service || true
  '';
in {
  home.packages = [pkgs.kanshi];
  imports = [./change_profile_service.nix]; # Re-enabled - D-Bus lid detection
  services = {
    kanshi-lid-profile.enable = true; # Re-enabled - D-Bus lid detection
    kanshi = {
      enable = true;
      settings = [
        {
          output = {
            criteria = "eDP-1";
            mode = "2880x1800@120.00000";
            scale = 2.0;
          };
        }
        {
          profile = {
            name = "undocked";
            outputs = [
              {
                criteria = "eDP-1";
                position = "0,0";
                status = "enable";
              }
            ];
            exec = [
              undocked-sh.outPath
            ];
          };
        }
        {
          profile = {
            name = "home-docked-lid-open";
            outputs = [
              {
                criteria = "Samsung Electric Company S27H85x H4ZM300138";
                mode = "2560x1440@60";
                position = "0,0";
                scale = 1.0;
                status = "enable";
              }
              {
                criteria = "Samsung Electric Company S27H85x H4ZKB00167";
                mode = "2560x1440@60";
                position = "2560,0";
                scale = 1.0;
                status = "enable";
              }
              {
                criteria = "eDP-1";
                status = "enable";
                position = "2560,1440";
              }
            ];
            exec = [
              home-docked-lid-open-sh.outPath
            ];
          };
        }
        {
          profile = {
            name = "home-docked-lid-close";
            outputs = [
              {
                criteria = "Samsung Electric Company S27H85x H4ZM300138";
                mode = "2560x1440@60";
                position = "0,0";
                scale = 1.0;
                status = "enable";
              }
              {
                criteria = "Samsung Electric Company S27H85x H4ZKB00167";
                mode = "2560x1440@60";
                position = "2560,0";
                scale = 1.0;
                status = "enable";
              }
              {
                criteria = "eDP-1";
                status = "disable";
              }
            ];
            exec = [
              home-docked-lid-close-sh.outPath
            ];
          };
        }
        {
          profile = {
            name = "work-docked-lid-open";
            outputs = [
              {
                criteria = work-ext-left-desc;
                mode = "2560x1440@60";
                position = "0,0";
                scale = 1.0;
                status = "enable";
              }
              {
                criteria = work-ext-right-desc;
                mode = "2560x1440@60";
                position = "2560,0";
                scale = 1.0;
                status = "enable";
              }
              {
                criteria = "eDP-1";
                status = "enable";
                position = "1280,1440";
              }
            ];
            exec = [
              work-docked-lid-open-sh.outPath
            ];
          };
        }
        {
          profile = {
            name = "work-docked-lid-close";
            outputs = [
              {
                criteria = work-ext-left-desc;
                mode = "2560x1440@60";
                position = "0,0";
                scale = 1.0;
                status = "enable";
              }
              {
                criteria = work-ext-right-desc;
                mode = "2560x1440@60";
                position = "2560,0";
                scale = 1.0;
                status = "enable";
              }
              {
                criteria = "eDP-1";
                status = "disable";
              }
            ];
            exec = [
              work-docked-lid-close-sh.outPath
            ];
          };
        }
      ];
    };
  };
}
