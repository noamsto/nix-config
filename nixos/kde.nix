{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    kdePackages.yakuake
    kdePackages.kcalc
    wayland-utils
  ];
  programs.kdeconnect.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.xserver = {
    # Configure keymap in X11
    xkb.layout = "us,il";
    xkb.options = "compose:menu, grp:win_space_toggle";
  };
}
