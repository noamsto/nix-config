{pkgs, ...}: {
  # install theme and cursor
  environment.systemPackages = with pkgs; [
    # where-is-my-sddm-theme
    bibata-cursors
  ];
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    settings = {
      Theme = {
        CursorTheme = "Bibata-Modern-Ice";
      };
    };
  };
}
