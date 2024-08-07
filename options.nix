{lib, ...}: rec {
  options = {
    server.enable = lib.mkEnableOption "server"; #NOTE: This might be useless
    desktop.mode = lib.mkOption {
      type = lib.types.enum ["none" "kde" "hyprland"];
      default = "none";
      description = "Desktop mode";
    };
    machine.type = lib.mkOption {
      type = lib.types.enum ["server" "desktop" "laptop"];
      default = "server";
      description = "Machine type";
    };
    profile = lib.mkOption {
      type = lib.types.enum ["personal" "work"];
      default = "personal";
      description = "Work or Personal";
    };
    username = lib.mkOption {
      type = lib.types.str;
      default = "noams";
      readOnly = true;
    };
    user-full-name = lib.mkOption {
      type = lib.types.str;
      default = "Noam Stolero";
      readOnly = true;
    };
    email = lib.mkOption {
      type = lib.types.str;
      default = "noamstolero@gmail.com";
      readOnly = true;
    };
    hostname = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
    };
  };
}
