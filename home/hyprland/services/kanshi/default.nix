{
  lib,
  pkgs,
  ...
}: let
  hyprctl = "${lib.getExe' pkgs.hyprland "hyprctl"}";
  undocked-sh = pkgs.writeShellScript "undocked-sh" ''
    "${hyprctl} keyword workspace \"1,default:true,monitor:eDP-1,persistent:true\""
    "${hyprctl} keyword workspace \"2,monitor:eDP-1,persistent:true\""
    "${hyprctl} keyword workspace \"3,monitor:eDP-1,persistent:true\""
    "pkill ags && nohup ${pkgs.hyprpanel}/bin/hyprpanel > /dev/null 2>&1 &"
  '';
  home-docked-lid-open-sh = pkgs.writeShellScript "home-docked-lid-open-sh" ''
    "${hyprctl} keyword workspace \"1,default:true,monitor:desc:Samsung Electric Company S27H85x H4ZM300138,persistent:true\""
    "${hyprctl} keyword workspace \"2,default:true,monitor:desc:Samsung Electric Company S27H85x H4ZKB00167,persistent:true\""
    "${hyprctl} keyword workspace \"3,default:true,monitor:eDP-1,persistent:true\""
    "pkill ags && nohup ${pkgs.hyprpanel}/bin/hyprpanel > /dev/null 2>&1 &"
  '';
  home-docked-lid-close-sh = pkgs.writeShellScript "home-docked-lid-close-sh" ''
    "${hyprctl} keyword workspace \"1,default:true,monitor:desc:Samsung Electric Company S27H85x H4ZM300138,persistent:true\""
    "${hyprctl} keyword workspace \"2,default:true,monitor:desc:Samsung Electric Company S27H85x H4ZKB00167,persistent:true\""
    "${hyprctl} keyword workspace \"3,persistent:true\""
    "pkill ags && nohup ${pkgs.hyprpanel}/bin/hyprpanel > /dev/null 2>&1 &"
  '';
in {
  home.packages = [pkgs.kanshi];
  imports = [./change_profile_service.nix];
  services = {
    kanshi-lid-profile.enable = true;
    kanshi = {
      enable = true;
      systemdTarget = "hyprland-session.target";
      settings = [
        {
          output = {
            criteria = "eDP-1";
            mode = "2880x1800@90.0";
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
                scale = 1.25;
              }
              {
                criteria = "Samsung Electric Company S27H85x H4ZKB00167";
                mode = "2560x1440@59.95100";
                position = "2048,0";
                scale = 1.25;
              }
              {
                criteria = "eDP-1";
                status = "enable";
                position = "2048,1152";
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
                scale = 1.25;
              }
              {
                criteria = "Samsung Electric Company S27H85x H4ZKB00167";
                mode = "2560x1440@59.95100";
                position = "2048,0";
                scale = 1.25;
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
      ];
    };
  };
}
