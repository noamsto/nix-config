{pkgs, ...}: {
  imports = [
    ./blueman
    ./sddm
  ];
  environment.systemPackages = with pkgs; [
    # Top bar
    waybar
    # Notificationr
    dunst
    libnotify
    # Wallpaper
    swww
    # App launcher
    rofi-wayland

    # Network applet
    networkmanagerapplet

    # audio stuff
    pavucontrol
    swayosd
    playerctl

    bc
  ];
  programs.hyprland.enable = true;
  services.xserver.enable = true;
  programs.light.enable = true; # Brightness control
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
    ];
  };
}
