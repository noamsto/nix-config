{
  pkgs,
  lib,
  config,
  ...
}:
lib.mkIf (config.desktop.mode == "kde") {
  environment.systemPackages = with pkgs; [
    kdePackages.kcalc
    wayland-utils
  ];
  programs.kdeconnect.enable = true;
  services.desktopManager.plasma6.enable = true;
}
