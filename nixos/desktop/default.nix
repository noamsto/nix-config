{
  pkgs,
  config,
  ...
}: {
  imports = [
    ./sddm
    ./kde.nix
  ];
  services = {
    # Enable flatpak
    flatpak.enable = true;
  };

  services.xserver = {
    # Configure keymap in X11
    xkb.layout = "us,il";
    xkb.options = "compose:menu, grp:win_space_toggle";
  };
  specialisation = {
    hypr.configuration = {
      desktop.mode = "hyprland";
      services.displayManager.sddm = {
        package = pkgs.kdePackages.sddm;
        extraPackages = [pkgs.kdePackages.qt5compat];
      };
    };
  };
}
