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

      # Existing profiles - Home Manager manages profiles.ini
      profiles.default = {
        id = 0;
        path = "mtmhnnfc.default";
        isDefault = false;
      };

      profiles.Factify = {
        id = 1;
        path = "ag39huod.Factify";
        isDefault = true;

        settings = {
          # Wayland scaling - fix for multi-monitor with different scales
          "widget.wayland.fractional-scale.enabled" = true;

          # Wayland portal integration (native file pickers, screen sharing)
          "widget.use-xdg-desktop-portal.file-picker" = 1;
          "widget.use-xdg-desktop-portal.mime-handler" = 1;

          # Hardware acceleration (VA-API)
          "gfx.webrender.all" = true;
          "media.ffmpeg.vaapi.enabled" = true;
          "media.hardware-video-decoding.force-enabled" = true;

          # Match frame rate to 120Hz display
          "layout.frame_rate" = 120;

          # Smooth scrolling with physics-based momentum
          "general.smoothScroll" = true;
          "general.smoothScroll.msdPhysics.enabled" = true;

          # Touchpad scrolling - reduce sensitivity (default too fast on Wayland)
          "apz.gtk.pangesture.page_delta_mode_multiplier" = 0.4;

          # Touchpad hold gesture (Firefox 134+)
          "apz.gtk.touchpad_hold.enabled" = true;

          # Picture-in-Picture
          "media.videocontrols.picture-in-picture.video-toggle.enabled" = true;

          # Privacy: Block cryptominers and fingerprinters
          "privacy.trackingprotection.cryptomining.enabled" = true;
          "privacy.trackingprotection.fingerprinting.enabled" = true;

          # Stop asking to be default browser
          "browser.shell.checkDefaultBrowser" = false;
          "browser.shell.didSkipDefaultBrowserCheckOnFirstRun" = true;

          # Disable annoyances
          "browser.aboutConfig.showWarning" = false;
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
