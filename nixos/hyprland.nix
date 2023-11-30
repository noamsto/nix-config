{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ./blueman
  ];
  environment.systemPackages = with pkgs; [
    (
      # Top bar
      waybar.overrideAttrs (oldAttrs: {
        mesonFlags = oldAttrs.mesonFlags ++ ["-Dexperimental=true"];
      })
      # Notifications
      dunst
      libnotify
      # Wallpaper
      swww
      # App launcher
      rofi-wayland
      kitty
    )
  ];
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
    ];
  };
}
