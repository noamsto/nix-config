{lib, ...}: {
  options = {
    kde.enable = lib.mkEnableOption "kde";
    desktop.enable = lib.mkEnableOption "desktop";
    server.enable = lib.mkEnableOption "server";
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
