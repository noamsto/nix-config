{
  lib,
  config,
  ...
}: {
  options = {
    server.enable = lib.mkEnableOption "server"; #NOTE: This might be useless
    desktop.mode = lib.mkOption {
      type = lib.types.enum ["none" "kde" "hyprland"];
      default = "none";
      description = "Desktop mode";
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
