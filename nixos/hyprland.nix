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
  ];
  programs.hyprland.enable = true;
  displayManager.sddm.enable = true;
}
