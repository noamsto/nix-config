{
  config,
  lib,
  pkgs,
  ...
}: {
  options = {
    desktop = {
      mode = lib.mkOption {
        type = lib.types.enum ["none" "hyprland"];
        default = "none";
        description = "Desktop mode";
      };
      isEnabled = lib.mkOption {
        type = lib.types.bool;
        default = config.desktop.mode != "none";
        readOnly = true;
      };
      isHyprland = lib.mkOption {
        type = lib.types.bool;
        default = config.desktop.mode == "hyprland";
        readOnly = true;
      };
    };
    # Deliberately NOT a `desktop.mode` value. `desktop.mode` governs whether
    # *this user* gets a desktop and drives the `home/desktop` import in
    # home/noams.nix; the console session runs as a separate account, so none of
    # that should change. Orthogonal axis, not a fourth enum member.
    steamConsole = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Run Steam Gaming Mode (Jovian) as a dedicated console user.";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "steam";
        description = ''
          Unprivileged account the console session runs as. Deliberately not
          `username`: autologin means whoever holds the TV remote is logged in,
          and that must not be the account with SSH keys, sudo and agent access.
        '';
      };
      start = lib.mkOption {
        type = lib.types.enum ["boot" "manual" "controller"];
        default = "boot";
        description = ''
          How Gaming Mode's display manager gets started:
          - `boot`: started at boot, as usual.
          - `manual`: installed but not booted; start it from the couch or
            over ssh with `systemctl start display-manager`.
          - `controller`: like `manual`, plus a controller Home-button press
            starts it, and Steam's own idle sleep or the TV going off stops
            it. Never stops while a game is running.
        '';
      };
    };
    machine = {
      type = lib.mkOption {
        type = lib.types.enum ["server" "desktop" "laptop"];
        default = "server";
        description = "Machine type";
      };
      isLaptop = lib.mkOption {
        type = lib.types.bool;
        default = config.machine.type == "laptop";
        readOnly = true;
      };
      isPC = lib.mkOption {
        type = lib.types.bool;
        default = config.machine.type == "laptop" || config.machine.type == "desktop";
        readOnly = true;
      };
      serverMode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run this host as an always-on headless server: disable autonomous
          suspend (lid-close fallback timer and idle suspend) so SSH/tmux
          sessions survive a closed lid. Thermal emergency suspend stays active.
          Flip back to false to restore normal laptop power behavior.
        '';
      };
    };
    profile = lib.mkOption {
      type = lib.types.enum ["personal" "work"];
      default = "personal";
      description = "Work or Personal";
    };
    username = lib.mkOption {
      type = lib.types.str;
      default = "noams";
    };
    user-full-name = lib.mkOption {
      type = lib.types.str;
      default = "Noam Stolero";
      readOnly = true;
    };
    email = lib.mkOption {
      type = lib.types.str;
      default = "noamstolero@gmail.com";
    };
    hostname = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
    };
    laptop-scale = lib.mkOption {
      type = lib.types.str;
      default = "1.25";
      description = "Laptop display scale";
    };
    flakePath = lib.mkOption {
      type = lib.types.str;
      default =
        if pkgs.stdenv.hostPlatform.isDarwin
        then "/Users/${config.username}/nix-config"
        else "/home/${config.username}/nix-config";
      readOnly = true;
    };
  };
}
