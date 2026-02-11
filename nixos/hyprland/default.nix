{
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
    };

    # Custom UWSM session that directly invokes start-hyprland
    # instead of referencing hyprland.desktop (which we want to hide from greeter)
    # See: https://github.com/NixOS/nixpkgs/issues/471800
    # See: https://github.com/hyprwm/Hyprland/discussions/12661
    services.displayManager.sessionPackages = lib.mkForce [
      (pkgs.runCommand "hyprland-uwsm-only" {
          passthru.providedSessions = ["hyprland-uwsm"];
        } ''
                  mkdir -p $out/share/wayland-sessions
                  cat > $out/share/wayland-sessions/hyprland-uwsm.desktop << EOF
          [Desktop Entry]
          Name=Hyprland (uwsm-managed)
          Comment=An intelligent dynamic tiling Wayland compositor
          Exec=uwsm start -e -D Hyprland -F -- ${pkgs.hyprland}/bin/start-hyprland
          Type=Application
          DesktopNames=Hyprland
          EOF
        '')
    ];

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
