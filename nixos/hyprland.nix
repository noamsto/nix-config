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
    fuzzel

    # Network applet
    networkmanagerapplet
  ];
  programs.hyprland.enable = true;
  services.xserver.enable = true;
}
