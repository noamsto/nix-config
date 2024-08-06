{
  pkgs,
  config,
  lib,
  ...
}:
lib.mkIf (config.desktop.mode != "none") {
  # install theme and cursor
  environment.systemPackages = with pkgs; [
    bibata-cursors
    (where-is-my-sddm-theme.override {
      themeConfig.General = {
        background = toString ./tree.png;
        backgroundMode = "fill";
        # value "1" is all display width, "0.5" is a half of display width etc.
        passwordInputWidth = 0.25;
        # Background color of password input
        passwordInputBackground = "#60ffffff";
        # Radius of password input corners
        passwordInputRadius = 10;
        # "true" for visible cursor, "false" for invisible
        passwordInputCursorVisible = true;
        # Font size of password (in points)
        passwordFontSize = 28;
        passwordCursorColor = "#ffffff";

        # Show or not users choose label
        showUsersByDefault = true;
        # Font size of users choose label (in points)
        usersFontSize = 32;
        # Default text color for all labels
        basicTextColor = "#ffffff";
      };
    })
  ];
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "where_is_my_sddm_theme";
    settings = {
      Theme = {
        CursorTheme = "Bibata-Modern-Ice";
      };
    };
  };
}
