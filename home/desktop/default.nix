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

    brave = {
      nativeMessagingHosts = [
        pkgs.kdePackages.plasma-browser-integration
      ];
      # NOTE: Command-line flags are applied via overlay in lib/overlays.nix
      # Also set via BRAVE_USER_FLAGS env var in Hyprland as a fallback
    };

    chromium = {
      enable = lib.mkIf (osConfig.profile == "work") true;
      commandLineArgs = [
        "--disable-accelerated-2d-canvas"
        "--disable-features=WaylandWpColorManagerV1"
      ];
    };
  };
}
