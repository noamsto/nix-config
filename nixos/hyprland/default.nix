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

    # smooth backlight control
    hardware.brillo.enable = true;

    environment.systemPackages = with pkgs; [
      pavucontrol

      # QML Language Server for development
      kdePackages.qttools # Provides qmlls
      kdePackages.qtdeclarative

      # Quickshell for QML-based desktop shell
      inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default

      # Quickshell recommended packages for full functionality
      qt6.qtsvg # SVG image loading support
      qt6.qtimageformats # WEBP and less common image formats
      qt6.qtmultimedia # Video/audio support
      qt6.qt5compat # Visual effects (gaussian blur)
    ];
  };
}
