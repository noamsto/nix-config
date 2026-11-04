{
  pkgs,
  lib,
  config,
  ...
}: let
  isHypr = config.desktop.isHyprland;
in
  lib.mkIf isHypr {
    services = {
      # needed for GNOME services outside of GNOME Desktop
      dbus.packages = [pkgs.gnome-settings-daemon];
      gnome = {
        gnome-keyring.enable = true;
        gcr-ssh-agent.enable = true; # Explicitly enable GCR SSH agent
      };
      gvfs.enable = true;
    };

    programs.seahorse.enable = true;
    # Keyring unlock on password logins. greetd's auth chain copies this rule
    # (greetd-pam.nix), and greetd's session stack still includes login.
    security.pam.services.login.enableGnomeKeyring = true;
  }
