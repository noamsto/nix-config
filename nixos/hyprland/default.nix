{
  pkgs,
  lib,
  config,
  ...
}: let
  isHypr = config.desktop.isHyprland;

  # Restrict display managers to only show the UWSM session entry.
  # Upstream ships both hyprland.desktop and hyprland-uwsm.desktop; setting
  # passthru.providedSessions filters what programs.hyprland symlinks into
  # services.displayManager.sessionPackages. passthru does not affect the
  # derivation hash, so the cached upstream build is reused.
  # PR #508309 (merged 2026-04-09) made hyprland-uwsm.desktop use absolute
  # uwsm paths, removing the need to rewrite the file ourselves.
  hyprlandUwsmOnly = pkgs.hyprland.overrideAttrs (old: {
    passthru =
      (old.passthru or {})
      // {
        providedSessions = ["hyprland-uwsm"];
      };
  });
in {
  imports = [./gnome-services.nix];
  config = lib.mkIf isHypr {
    programs.hyprland = {
      withUWSM = true;
      enable = true;
      package = hyprlandUwsmOnly;
    };

    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --time-format '%I:%M %p | %a • %h %d %Y' --theme border=magenta;text=cyan;prompt=cyan;time=white;action=blue;button=yellow;container=black;input=gray --asterisks --greeting 'Welcome to NixOS' --width 80 --container-padding 2 --prompt-padding 1 --remember --remember-user-session --user-menu";
        };
      };
    };

    services.blueman.enable = true;
    # PAM service for Noctalia shell (GNOME keyring unlock)
    security.pam.services.noctalia-shell = {
      enableGnomeKeyring = true;
    };

    # Ensure video group permissions for backlight control
    # ydotool group for speech-to-text typing (created by programs.ydotool)
    users.users.${config.username}.extraGroups = ["video" "i2c" "ydotool"];
    hardware.i2c.enable = true;
    boot.kernelModules = ["i2c_dev" "uinput"];

    # ydotool for speech-to-text typing
    programs.ydotool.enable = true;

    environment.systemPackages = with pkgs; [
      pavucontrol
      # Valent - lightweight KDE Connect protocol implementation (GTK-based)
      # Replaced KDE Connect which pulled heavy KDE dependencies
      valent
    ];
  };
}
