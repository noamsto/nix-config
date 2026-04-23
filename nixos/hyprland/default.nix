{
  pkgs,
  lib,
  config,
  ...
}: let
  isHypr = config.desktop.isHyprland;

  # Strip the plain hyprland.desktop so display managers (tuigreet, sddm, gdm)
  # only offer hyprland-uwsm. symlinkJoin wraps the upstream package without
  # rebuilding — $out is a tree of symlinks to the real hyprland outputs, and
  # we remove just the one .desktop symlink. `override` is preserved (and
  # re-wraps) so programs.hyprland's genFinalPackage keeps working.
  hyprlandUwsmOnly = let
    wrap = base:
      (pkgs.symlinkJoin {
        name = "hyprland-uwsm-only-${base.version}";
        # Merge all outputs (out, man) that profiles will try to install;
        # symlinkJoin only emits $out, so they all land there.
        paths = map (o: base.${o}) (base.meta.outputsToInstall or ["out"]);
        postBuild = ''
          rm -f $out/share/wayland-sessions/hyprland.desktop
        '';
        passthru =
          (base.passthru or {})
          // {
            providedSessions = ["hyprland-uwsm"];
          };
        meta = base.meta // {outputsToInstall = ["out"];};
        inherit (base) version;
      })
      // {override = args: wrap (base.override args);};
  in
    wrap pkgs.hyprland;
in {
  imports = [./gnome-services.nix];
  config = lib.mkIf isHypr {
    programs.hyprland = {
      withUWSM = true;
      enable = true;
      package = hyprlandUwsmOnly;
    };

    services = {
      displayManager.defaultSession = "hyprland-uwsm";

      greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --time --time-format '%I:%M %p | %a • %h %d %Y' --theme border=magenta;text=cyan;prompt=cyan;time=white;action=blue;button=yellow;container=black;input=gray --asterisks --greeting 'Welcome to NixOS' --width 80 --container-padding 2 --prompt-padding 1 --remember --remember-user-session --user-menu";
          };
        };
      };

      blueman.enable = true;
    };
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
