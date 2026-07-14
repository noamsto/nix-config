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
