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
      gnome.gcr-ssh-agent.enable = true; # Explicitly enable GCR SSH agent
      gnome.evolution-data-server.enable = true; # Calendar support for Noctalia
      gnome.gnome-online-accounts.enable = true; # Google Calendar OAuth via gnome-control-center
      gvfs.enable = true;
    };

    # Required for gnome-online-accounts OAuth to work on NixOS
    # WebKit sandboxing breaks with NixOS filesystem structure
    environment.variables.WEBKIT_FORCE_SANDBOX = "0";

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
