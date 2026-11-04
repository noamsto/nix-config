{
  pkgs,
  lib,
  config,
  ...
}: let
  isHypr = config.desktop.isHyprland;

  # Strip the plain hyprland.desktop so display managers (noctalia-greeter, sddm, gdm)
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
  imports = [./gnome-services.nix ./keyring-tpm-unlock.nix ./greetd-pam.nix];
  config = lib.mkIf isHypr {
    programs = {
      hyprland = {
        withUWSM = true;
        enable = true;
        package = hyprlandUwsmOnly;
      };

      # Register xfconfd as a D-Bus service so Thunar's xfconf settings persist.
      # Without this, the session bus can't auto-activate xfconfd and Thunar
      # falls back to in-memory defaults (wrong view, wrong sort order, etc.).
      xfconf.enable = true;
    };

    services.displayManager = {
      defaultSession = "hyprland-uwsm";

      noctalia-greeter = {
        enable = true;
        # Lets noctalia's Auto-Sync push wallpaper and palette without a prompt.
        passwordlessSyncUsers = [config.username];
        cursorTheme = {
          package = pkgs.bibata-cursors;
          name = "Bibata-Modern-Ice";
        };
        settings = {
          session.default = "hyprland-uwsm";
          user.default = config.username;
          cursor.size = 20;
          # An empty submit starts the fingerprint scan (greetd-pam.nix); a typed
          # password never waits on the reader. request_timeout = 0 because three
          # 30 s fprintd tries can outlast the greeter's 60 s reply watchdog.
          auth = {
            allow_empty_password = true;
            request_timeout = 0;
          };
        };
      };
    };
    # Ensure video group permissions for backlight control
    users.users.${config.username}.extraGroups = ["video" "i2c"];
    hardware.i2c.enable = true;
    boot.kernelModules = ["i2c_dev" "uinput"];

    environment.systemPackages = with pkgs; [
      pavucontrol
      # Valent - lightweight KDE Connect protocol implementation (GTK-based)
      # Replaced KDE Connect which pulled heavy KDE dependencies
      valent
    ];
  };
}
