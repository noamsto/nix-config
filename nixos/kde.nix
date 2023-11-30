{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    yakuake
    kcalc
  ];
  programs.kdeconnect.enable = true;
  services.xserver = {
    # Enable the X11 windowing system.
    enable = true;

    # Enable the KDE Plasma Desktop Environment.
    displayManager.sddm.enable = true;
    desktopManager.plasma5.enable = true;

    # Configure keymap in X11
    layout = "us,il";
    xkbVariant = "";
    xkbOptions = "compose:menu, grp:win_space_toggle";
  };
}
