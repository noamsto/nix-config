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
    # Keyring unlock on password logins. Note: greetd's PAM file substacks
    # `login`, so keyring/fprintd rules here apply to the greeter too — setting
    # them on the greetd service itself is a no-op.
    security.pam.services.login.enableGnomeKeyring = true;
  }
