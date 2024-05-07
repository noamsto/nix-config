{pkgs, ...}: {
  imports = [
    ./sddm
  ];
  environment.systemPackages = with pkgs; [
    kdePackages.yakuake
    kdePackages.kcalc
    wayland-utils
  ];
  programs.kdeconnect.enable = true;
  # services.displayManager.defaultSession = "plasmawayland";
  services.desktopManager.plasma6.enable = true;
  services.xserver = {
    # Enable the X11 windowing system.
    enable = true;

    # Enable the KDE Plasma Desktop Environment.

    # Configure keymap in X11
    xkb.layout = "us,il";
    xkb.variant = "";
    xkb.options = "compose:menu, grp:win_space_toggle";
  };
}
