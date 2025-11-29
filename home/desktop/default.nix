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
      enable = true;
      nativeMessagingHosts = [
        pkgs.kdePackages.plasma-browser-integration
      ];
      # NOTE: Command-line flags are applied via overlay in lib/overlays.nix
      # Also set via BRAVE_USER_FLAGS env var in Hyprland as a fallback
    };

    firefox = {
      enable = true;
      nativeMessagingHosts = [
        pkgs.kdePackages.plasma-browser-integration
      ];

      # Wayland and performance optimizations
      policies = {
        DisableAppUpdate = true; # Managed by Nix
        DisablePocket = true;
        DisableFirefoxStudies = true;
        DisableTelemetry = true;
        DontCheckDefaultBrowser = true;
        HardwareAcceleration = true;

        Preferences = {
          # Wayland portal integration
          "widget.use-xdg-desktop-portal.file-picker" = 1;
          "widget.use-xdg-desktop-portal.mime-handler" = 1;

          # Hardware acceleration
          "gfx.webrender.all" = true;
          "media.ffmpeg.vaapi.enabled" = true;
          "media.hardware-video-decoding.force-enabled" = true;

          # Smooth scrolling
          "general.smoothScroll" = true;
          "general.smoothScroll.msdPhysics.enabled" = true;

          # Firefox Sync
          "services.sync.engine.passwords" = true;
          "services.sync.engine.bookmarks" = true;
          "services.sync.engine.history" = true;
          "services.sync.engine.tabs" = true;
          "services.sync.engine.prefs" = true;
        };
      };
    };

    chromium = {
      enable = lib.mkIf (osConfig.profile == "work") true;
      commandLineArgs = [
        "--disable-features=WaylandWpColorManagerV1"
      ];
    };
  };
}
