{pkgs, ...}: {
  imports = [
    ./sddm
  ];
  environment.systemPackages = with pkgs; [
    yakuake
    kcalc
    plasma5Packages.polonium
    wayland-utils
    catppuccin-kde
  ];
  programs.kdeconnect.enable = true;
  services.xserver = {
    # Enable the X11 windowing system.
    enable = true;

    # Enable the KDE Plasma Desktop Environment.
    desktopManager.plasma5.enable = true;
    displayManager.defaultSession = "plasmawayland";

    # Configure keymap in X11
    layout = "us,il";
    xkbVariant = "";
    xkbOptions = "compose:menu, grp:win_space_toggle";
  };
}
