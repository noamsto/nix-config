{pkgs, ...}: {
  imports = [
    ./blueman
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
    kitty

    # Network applet
    networkmanagerapplet
  ];
  programs.hyprland.enable = true;
  services.xserver.displayManager.sddm.enable = true;
  services.xserver.enable = true;
}
