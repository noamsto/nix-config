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

    # Create workspace first, then move it
    ${hyprctl} dispatch workspace 1
    ${hyprctl} dispatch moveworkspacetomonitor 1 eDP-1
    launch-dock &
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

    # Create workspaces first, then move them
    # Left monitor (DP-8): workspaces 1-4
    ${hyprctl} dispatch workspace 1 && ${hyprctl} dispatch moveworkspacetomonitor 1 ${home-ext-left} || true
    ${hyprctl} dispatch workspace 2 && ${hyprctl} dispatch moveworkspacetomonitor 2 ${home-ext-left} || true
    ${hyprctl} dispatch workspace 3 && ${hyprctl} dispatch moveworkspacetomonitor 3 ${home-ext-left} || true
    ${hyprctl} dispatch workspace 4 && ${hyprctl} dispatch moveworkspacetomonitor 4 ${home-ext-left} || true
    # Right monitor (DP-7): workspaces 5-8
    ${hyprctl} dispatch workspace 5 && ${hyprctl} dispatch moveworkspacetomonitor 5 ${home-ext-right} || true
    ${hyprctl} dispatch workspace 6 && ${hyprctl} dispatch moveworkspacetomonitor 6 ${home-ext-right} || true
    ${hyprctl} dispatch workspace 7 && ${hyprctl} dispatch moveworkspacetomonitor 7 ${home-ext-right} || true
    ${hyprctl} dispatch workspace 8 && ${hyprctl} dispatch moveworkspacetomonitor 8 ${home-ext-right} || true
    # Laptop screen: workspace 9
    ${hyprctl} dispatch workspace 9 && ${hyprctl} dispatch moveworkspacetomonitor 9 eDP-1 || true
    launch-dock &
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

    # Create workspaces first, then move them
    # Left monitor (ext left): workspaces 1-4
    ${hyprctl} dispatch workspace 1 && ${hyprctl} dispatch moveworkspacetomonitor 1 ${home-ext-left} || true
    ${hyprctl} dispatch workspace 2 && ${hyprctl} dispatch moveworkspacetomonitor 2 ${home-ext-left} || true
    ${hyprctl} dispatch workspace 3 && ${hyprctl} dispatch moveworkspacetomonitor 3 ${home-ext-left} || true
    ${hyprctl} dispatch workspace 4 && ${hyprctl} dispatch moveworkspacetomonitor 4 ${home-ext-left} || true
    # Right monitor (ext right): workspaces 5-8
    ${hyprctl} dispatch workspace 5 && ${hyprctl} dispatch moveworkspacetomonitor 5 ${home-ext-right} || true
    ${hyprctl} dispatch workspace 6 && ${hyprctl} dispatch moveworkspacetomonitor 6 ${home-ext-right} || true
    ${hyprctl} dispatch workspace 7 && ${hyprctl} dispatch moveworkspacetomonitor 7 ${home-ext-right} || true
    ${hyprctl} dispatch workspace 8 && ${hyprctl} dispatch moveworkspacetomonitor 8 ${home-ext-right} || true
    launch-dock &
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

    # Create workspaces first, then move them
    # Left monitor (work left): workspaces 1-4
    ${hyprctl} dispatch workspace 1 && ${hyprctl} dispatch moveworkspacetomonitor 1 ${work-ext-left} || true
    ${hyprctl} dispatch workspace 2 && ${hyprctl} dispatch moveworkspacetomonitor 2 ${work-ext-left} || true
    ${hyprctl} dispatch workspace 3 && ${hyprctl} dispatch moveworkspacetomonitor 3 ${work-ext-left} || true
    ${hyprctl} dispatch workspace 4 && ${hyprctl} dispatch moveworkspacetomonitor 4 ${work-ext-left} || true
    # Right monitor (work right): workspaces 5-8
    ${hyprctl} dispatch workspace 5 && ${hyprctl} dispatch moveworkspacetomonitor 5 ${work-ext-right} || true
    ${hyprctl} dispatch workspace 6 && ${hyprctl} dispatch moveworkspacetomonitor 6 ${work-ext-right} || true
    ${hyprctl} dispatch workspace 7 && ${hyprctl} dispatch moveworkspacetomonitor 7 ${work-ext-right} || true
    ${hyprctl} dispatch workspace 8 && ${hyprctl} dispatch moveworkspacetomonitor 8 ${work-ext-right} || true
    # Laptop screen: workspace 9 for entertainment
    ${hyprctl} dispatch workspace 9 && ${hyprctl} dispatch moveworkspacetomonitor 9 eDP-1 || true
    launch-dock &
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

    # Create workspaces first, then move them
    # Left monitor (work left): workspaces 1-4
    ${hyprctl} dispatch workspace 1 && ${hyprctl} dispatch moveworkspacetomonitor 1 ${work-ext-left} || true
    ${hyprctl} dispatch workspace 2 && ${hyprctl} dispatch moveworkspacetomonitor 2 ${work-ext-left} || true
    ${hyprctl} dispatch workspace 3 && ${hyprctl} dispatch moveworkspacetomonitor 3 ${work-ext-left} || true
    ${hyprctl} dispatch workspace 4 && ${hyprctl} dispatch moveworkspacetomonitor 4 ${work-ext-left} || true
    # Right monitor (work right): workspaces 5-8
    ${hyprctl} dispatch workspace 5 && ${hyprctl} dispatch moveworkspacetomonitor 5 ${work-ext-right} || true
    ${hyprctl} dispatch workspace 6 && ${hyprctl} dispatch moveworkspacetomonitor 6 ${work-ext-right} || true
    ${hyprctl} dispatch workspace 7 && ${hyprctl} dispatch moveworkspacetomonitor 7 ${work-ext-right} || true
    ${hyprctl} dispatch workspace 8 && ${hyprctl} dispatch moveworkspacetomonitor 8 ${work-ext-right} || true
    launch-dock &
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
