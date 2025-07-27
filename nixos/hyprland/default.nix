{
  inputs,
  pkgs,
  lib,
  config,
  ...
}: let
  isHypr = config.desktop.mode == "hyprland";
in {
  imports = [./gnome-services.nix];
  config = lib.mkIf isHypr {
    programs.hyprland = {
      withUWSM = true;
      enable = true;
      package = pkgs.hyprland;
      portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
    };

    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --time-format '%I:%M %p | %a • %h %d %Y' --theme border=magenta;text=cyan;prompt=cyan;time=white;action=blue;button=yellow;container=black;input=gray --asterisks --greeting 'Welcome to NixOS' --width 80 --container-padding 2 --prompt-padding 1 --remember --remember-user-session --user-menu";
        };
      };
    };

    services.blueman.enable = true;
    security.pam.services.hyprlock = {};

    # Backlight control with brightnessctl
    # brightnessctl is included in desktop packages
    # Ensure video group permissions for backlight control
    users.users.${config.username}.extraGroups = ["video" "i2c"];

    # Enable i2c for ddcutil (external monitor control)
    boot.kernelModules = ["i2c-dev" "ddcci_backlight"];
    services.udev.extraRules = ''
      # Rules for ddcutil - allow i2c access for video group
      SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0660"
      KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
    '';
    environment.systemPackages = with pkgs; [
      pavucontrol
    ];
  };
}
