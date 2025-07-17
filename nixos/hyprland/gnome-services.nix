{
  pkgs,
  lib,
  config,
  ...
}: let
  isHypr = config.desktop.mode == "hyprland";
in
  lib.mkIf isHypr {
    services = {
      # needed for GNOME services outside of GNOME Desktop
      dbus.packages = with pkgs; [
        gcr
        gnome-settings-daemon
      ];
      gnome.gnome-keyring.enable = true;

      gvfs.enable = true;
    };
    programs.seahorse.enable = true;
    security.pam.services.greetd.enableGnomeKeyring = true;
  }
