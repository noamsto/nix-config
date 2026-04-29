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
      dbus.packages = with pkgs; [
        gcr
        gnome-settings-daemon
      ];
      gnome = {
        gnome-keyring.enable = true;
        gcr-ssh-agent.enable = true; # Explicitly enable GCR SSH agent
        evolution-data-server.enable = true; # Calendar support for Noctalia
        gnome-online-accounts.enable = true; # Google Calendar OAuth via gnome-control-center
      };
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
