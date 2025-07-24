{
  lib,
  pkgs,
  ...
}: let
  hyprctl = "${lib.getExe' pkgs.hyprland "hyprctl"}";
  home-ext-left = "desc:Samsung Electric Company S27H85x H4ZM300138";
  home-ext-right = "desc:Samsung Electric Company S27H85x H4ZKB00167";
  work-ext-left = "desc:Dell Inc. DELL P2723DE 4C7FH14";
  work-ext-right = "desc:Dell Inc. DELL P2723DE CC7FH14";
  undocked-sh = pkgs.writeShellScript "undocked-sh" ''
    ${hyprctl} dispatch moveworkspacetomonitor 1 eDP-1
  '';
  home-docked-lid-open-sh = pkgs.writeShellScript "home-docked-lid-open-sh" ''
    # Left monitor (DP-8): workspaces 1-4
    ${hyprctl} dispatch moveworkspacetomonitor 1 ${home-ext-left}
    ${hyprctl} dispatch moveworkspacetomonitor 2 ${home-ext-left}
    ${hyprctl} dispatch moveworkspacetomonitor 3 ${home-ext-left}
    ${hyprctl} dispatch moveworkspacetomonitor 4 ${home-ext-left}
    # Right monitor (DP-7): workspaces 5-8
    ${hyprctl} dispatch moveworkspacetomonitor 5 ${home-ext-right}
    ${hyprctl} dispatch moveworkspacetomonitor 6 ${home-ext-right}
    ${hyprctl} dispatch moveworkspacetomonitor 7 ${home-ext-right}
    ${hyprctl} dispatch moveworkspacetomonitor 8 ${home-ext-right}
    # Laptop screen: workspace 9
    ${hyprctl} dispatch moveworkspacetomonitor 9 eDP-1
  '';
  home-docked-lid-close-sh = pkgs.writeShellScript "home-docked-lid-close-sh" ''
    # Left monitor (ext left): workspaces 1-4
    ${hyprctl} dispatch moveworkspacetomonitor 1 ${home-ext-left}
    ${hyprctl} dispatch moveworkspacetomonitor 2 ${home-ext-left}
    ${hyprctl} dispatch moveworkspacetomonitor 3 ${home-ext-left}
    ${hyprctl} dispatch moveworkspacetomonitor 4 ${home-ext-left}
    # Right monitor (ext right): workspaces 5-8
    ${hyprctl} dispatch moveworkspacetomonitor 5 ${home-ext-right}
    ${hyprctl} dispatch moveworkspacetomonitor 6 ${home-ext-right}
    ${hyprctl} dispatch moveworkspacetomonitor 7 ${home-ext-right}
    ${hyprctl} dispatch moveworkspacetomonitor 8 ${home-ext-right}
  '';
  work-docked-lid-open-sh = pkgs.writeShellScript "work-docked-lid-open-sh" ''
    # Left monitor (work left): workspaces 1-4
    ${hyprctl} dispatch moveworkspacetomonitor 1 ${work-ext-left}
    ${hyprctl} dispatch moveworkspacetomonitor 2 ${work-ext-left}
    ${hyprctl} dispatch moveworkspacetomonitor 3 ${work-ext-left}
    ${hyprctl} dispatch moveworkspacetomonitor 4 ${work-ext-left}
    # Right monitor (work right): workspaces 5-8
    ${hyprctl} dispatch moveworkspacetomonitor 5 ${work-ext-right}
    ${hyprctl} dispatch moveworkspacetomonitor 6 ${work-ext-right}
    ${hyprctl} dispatch moveworkspacetomonitor 7 ${work-ext-right}
    ${hyprctl} dispatch moveworkspacetomonitor 8 ${work-ext-right}
    # Laptop screen: workspaces 9-10
    ${hyprctl} dispatch moveworkspacetomonitor 9 eDP-1
    ${hyprctl} dispatch moveworkspacetomonitor 10 eDP-1
  '';
  work-docked-lid-close-sh = pkgs.writeShellScript "work-docked-lid-close-sh" ''
    # Left monitor (work left): workspaces 1-4
    ${hyprctl} dispatch moveworkspacetomonitor 1 ${work-ext-left}
    ${hyprctl} dispatch moveworkspacetomonitor 2 ${work-ext-left}
    ${hyprctl} dispatch moveworkspacetomonitor 3 ${work-ext-left}
    ${hyprctl} dispatch moveworkspacetomonitor 4 ${work-ext-left}
    # Right monitor (work right): workspaces 5-8
    ${hyprctl} dispatch moveworkspacetomonitor 5 ${work-ext-right}
    ${hyprctl} dispatch moveworkspacetomonitor 6 ${work-ext-right}
    ${hyprctl} dispatch moveworkspacetomonitor 7 ${work-ext-right}
    ${hyprctl} dispatch moveworkspacetomonitor 8 ${work-ext-right}
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
                mode = "2560x1440@59.95100";
                position = "0,0";
                scale = 1.0;
                status = "enable";
              }
              {
                criteria = "Samsung Electric Company S27H85x H4ZKB00167";
                mode = "2560x1440@59.95100";
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
                mode = "2560x1440@59.95100";
                position = "0,0";
                scale = 1.0;
                status = "enable";
              }
              {
                criteria = "Samsung Electric Company S27H85x H4ZKB00167";
                mode = "2560x1440@59.95100";
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
                criteria = "Dell Inc. DELL P2723DE 4C7FH14";
                mode = "2560x1440@59.95100";
                position = "0,0";
                scale = 1.0;
                status = "enable";
              }
              {
                criteria = "Dell Inc. DELL P2723DE CC7FH14";
                mode = "2560x1440@59.95100";
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
                criteria = "Dell Inc. DELL P2723DE 4C7FH14";
                mode = "2560x1440@59.95100";
                position = "0,0";
                scale = 1.0;
                status = "enable";
              }
              {
                criteria = "Dell Inc. DELL P2723DE CC7FH14";
                mode = "2560x1440@59.95100";
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
