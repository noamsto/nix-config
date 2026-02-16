{
  pkgs,
  lib,
  config,
  ...
}: let
  isHypr = config.desktop.mode == "hyprland";

  # Override hyprland package to only offer the UWSM session to display managers.
  # The upstream package ships both hyprland.desktop (direct) and hyprland-uwsm.desktop
  # (UWSM-managed). Display managers like tuigreet/GDM can pick the wrong one, bypassing
  # UWSM and leaving graphical-session.target inactive — breaking all user services.
  # We replace both with a single entry that invokes start-hyprland directly via -F flag,
  # avoiding the desktop file lookup that would require the removed hyprland.desktop.
  # See: https://github.com/NixOS/nixpkgs/issues/484328
  # See: https://github.com/NixOS/nixpkgs/issues/471800
  hyprlandUwsmOnly = pkgs.hyprland.overrideAttrs (old: {
    passthru =
      (old.passthru or {})
      // {
        providedSessions = ["hyprland-uwsm"];
      };
    postInstall =
      (old.postInstall or "")
      + ''
                rm -f $out/share/wayland-sessions/hyprland.desktop
                rm -f $out/share/wayland-sessions/hyprland-uwsm.desktop
                cat > $out/share/wayland-sessions/hyprland-uwsm.desktop <<DESKTOP
        [Desktop Entry]
        Name=Hyprland (uwsm-managed)
        Comment=An intelligent dynamic tiling Wayland compositor
        Exec=uwsm start -e -D Hyprland -F -- $out/bin/start-hyprland
        Type=Application
        DesktopNames=Hyprland
        DESKTOP
      '';
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
