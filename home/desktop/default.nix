{
  osConfig,
  lib,
  pkgs,
  ...
}: {
  imports =
    [
      ./theme
      ./easyeffects
    ]
    ++ lib.optionals (osConfig.desktop.mode == "hyprland") [
      ./hyprland
    ];
  programs = {
    obs-studio.enable = true;

    brave.nativeMessagingHosts = [
      pkgs.kdePackages.plasma-browser-integration
    ];
  };
}
