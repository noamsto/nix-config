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
    # Ensure monitors are fully awake before workspace commands
    ${hyprctl} dispatch dpms on
    sleep 1

    # Wait for Hyprland to be responsive
    timeout=10
    while [ $timeout -gt 0 ] && ! ${hyprctl} monitors >/dev/null 2>&1; do
      sleep 0.5
      timeout=$((timeout - 1))
    done

    # Reset ALL workspace persistence first, then set only what we need
    ${setWorkspacePersistence "5..10" false}

    # Set persistence for undocked workspaces (only 1-4)
    ${setWorkspacePersistence "1..4" true}

    # Create and move workspaces 1-4 to laptop screen
    ${moveWorkspacesToMonitor "1..4" "eDP-1"}

    # Focus workspace 1 to ensure it's active
    ${hyprctl} dispatch workspace 1

    launch-dock &

    # Check actual lid state and control fprintd accordingly
    if grep -q "closed" /proc/acpi/button/lid/LID/state 2>/dev/null || grep -q "closed" /proc/acpi/button/lid/LID0/state 2>/dev/null; then
      ${pkgs.systemd}/bin/systemctl stop fprintd.service || true
    else
      ${pkgs.systemd}/bin/systemctl start fprintd.service || true
    fi
  '';
  home-docked-lid-open-sh = pkgs.writeShellScript "home-docked-lid-open-sh" ''
    # Ensure all monitors are fully awake and responsive
    ${hyprctl} dispatch dpms on
    sleep 2

    # Wait for Hyprland to be responsive and detect monitors
    timeout=15
    while [ $timeout -gt 0 ]; do
      if ${hyprctl} monitors | grep -q "${home-ext-left}" && ${hyprctl} monitors | grep -q "${home-ext-right}"; then
        break
      fi
      sleep 0.5
      timeout=$((timeout - 1))
    done

    # Add small delay to ensure monitors are stable
    sleep 1

    # Left monitor (ext-left): workspaces 1-4
    ${moveWorkspacesToMonitor "1..4" "${home-ext-left}"}

    # Right monitor (ext-right): workspaces 5-8
    ${moveWorkspacesToMonitor "5..8" "${home-ext-right}"}

    # Laptop screen: workspace 9
    ${hyprctl} dispatch workspace 9 && ${hyprctl} dispatch moveworkspacetomonitor 9 eDP-1 || true

    launch-dock &

    # Start fingerprint daemon when lid is open
    ${pkgs.systemd}/bin/systemctl start fprintd.service || true
  '';
  home-docked-lid-close-sh = pkgs.writeShellScript "home-docked-lid-close-sh" ''
    # Ensure all monitors are fully awake and responsive
    ${hyprctl} dispatch dpms on
    sleep 2

    # Wait for monitors to be detected
    timeout=15
    while [ $timeout -gt 0 ]; do
      if ${hyprctl} monitors | grep -q "${home-ext-left}" && ${hyprctl} monitors | grep -q "${home-ext-right}"; then
        break
      fi
      sleep 0.5
      timeout=$((timeout - 1))
    done

    sleep 1

    # Left monitor (ext left): workspaces 1-4
    ${moveWorkspacesToMonitor "1..4" "${home-ext-left}"}

    # Right monitor (ext right): workspaces 5-8
    ${moveWorkspacesToMonitor "5..8" "${home-ext-right}"}

    launch-dock &

    # Stop fingerprint daemon when lid is closed
    ${pkgs.systemd}/bin/systemctl stop fprintd.service || true
  '';
  work-docked-lid-open-sh = pkgs.writeShellScript "work-docked-lid-open-sh" ''
    # Ensure all monitors are fully awake and responsive
    ${hyprctl} dispatch dpms on
    sleep 2

    # Wait for work monitors to be detected
    timeout=15
    while [ $timeout -gt 0 ]; do
      if ${hyprctl} monitors | grep -q "${work-ext-left}" && ${hyprctl} monitors | grep -q "${work-ext-right}"; then
        break
      fi
      sleep 0.5
      timeout=$((timeout - 1))
    done

    sleep 1

    # Left monitor (work left): workspaces 1-4
    ${moveWorkspacesToMonitor "1..4" "${work-ext-left}"}

    # Right monitor (work right): workspaces 5-8
    ${moveWorkspacesToMonitor "5..8" "${work-ext-right}"}

    # Laptop screen: workspace 9 for entertainment
    ${hyprctl} dispatch workspace 9 && ${hyprctl} dispatch moveworkspacetomonitor 9 eDP-1 || true

    launch-dock &

    # Start fingerprint daemon when lid is open
    ${pkgs.systemd}/bin/systemctl start fprintd.service || true
  '';
  work-docked-lid-close-sh = pkgs.writeShellScript "work-docked-lid-close-sh" ''
    # Ensure all monitors are fully awake and responsive
    ${hyprctl} dispatch dpms on
    sleep 2

    # Wait for work monitors to be detected
    timeout=15
    while [ $timeout -gt 0 ]; do
      if ${hyprctl} monitors | grep -q "${work-ext-left}" && ${hyprctl} monitors | grep -q "${work-ext-right}"; then
        break
      fi
      sleep 0.5
      timeout=$((timeout - 1))
    done

    sleep 1

    # Left monitor (work left): workspaces 1-4
    ${moveWorkspacesToMonitor "1..4" "${work-ext-left}"}

    # Right monitor (work right): workspaces 5-8
    ${moveWorkspacesToMonitor "5..8" "${work-ext-right}"}

    launch-dock &

    # Stop fingerprint daemon when lid is closed
    ${pkgs.systemd}/bin/systemctl stop fprintd.service || true
  '';
in {
  home.packages = [pkgs.kanshi];
  imports = [./change_profile_service.nix];
  services = {
    kanshi-lid-profile.enable = true;
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
