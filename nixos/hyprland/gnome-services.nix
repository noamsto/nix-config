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
    security.pam.services = {
      # Enable keyring unlock during actual login process
      login.enableGnomeKeyring = true;
      # greetd bypass - may not work reliably for keyring unlocking
      greetd.enableGnomeKeyring = true;
      # Disable fingerprint for greetd to ensure keyring unlocking works
      greetd.fprintAuth = false;
    };
  }
