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
      # NOTE: Command-line flags are applied via overlay in lib/overlays.nix
      # Also set via BRAVE_USER_FLAGS env var in Hyprland as a fallback
    };

    firefox = {
      enable = true;
      profiles.default = {
        isDefault = true;
        settings = {
          # =======================================================================
          # PERFORMANCE & HARDWARE ACCELERATION
          # =======================================================================
          "gfx.webrender.all" = true;
          "media.ffmpeg.vaapi.enabled" = true;
          "dom.webgpu.enabled" = true;
          "layers.acceleration.disabled" = false;
          "browser.tabs.unloadOnLowMemory" = true;

          # =======================================================================
          # CLOUDFLARE COMPATIBILITY & PRIVACY BALANCE
          # =======================================================================
          # CRITICAL: Disable "Resist Fingerprinting" - causes Cloudflare loops
          "privacy.resistFingerprinting" = false;
          "browser.contentblocking.category" = "standard";
          "privacy.trackingprotection.fingerprinting.enabled" = false;
          "dom.serviceWorkers.enabled" = true;
          "dom.enable_resource_timing" = true;

          # =======================================================================
          # UI & VERTICAL TABS (Firefox 133+)
          # =======================================================================
          "sidebar.verticalTabs" = true;
          "sidebar.revamp" = true;
          "sidebar.visibility" = "expand-on-hover";
          "browser.compactmode.show" = true;
          "browser.uidensity" = 1;
          "browser.tabs.groups.enabled" = true;

          # =======================================================================
          # WAYLAND & DISPLAY
          # =======================================================================
          "widget.wayland.fractional-scale.enabled" = true;
          "widget.use-xdg-desktop-portal.file-picker" = 1;
          "widget.use-xdg-desktop-portal.mime-handler" = 1;

          # =======================================================================
          # SCROLLING & INPUT
          # =======================================================================
          "general.smoothScroll" = true;
          "general.smoothScroll.msdPhysics.enabled" = true;
          "apz.gtk.touchpad_hold.enabled" = true;

          # =======================================================================
          # SECURITY & NETWORK
          # =======================================================================
          "dom.security.https_only_mode" = true;
          "dom.security.https_only_mode.upgrade_local" = false;
          "network.trr.mode" = 0;
          "network.cookie.cookieBehavior" = 0;

          # =======================================================================
          # THEMING - Follow system color-scheme for Catppuccin adaptive mode
          # =======================================================================
          # -1 = follow system preference (from portal/dconf)
          "layout.css.prefers-color-scheme.content-override" = -1;
          # Use system theme (allows Catppuccin extension adaptive mode to work)
          "extensions.activeThemeID" = "default-theme@mozilla.org";

          # =======================================================================
          # QUALITY OF LIFE
          # =======================================================================
          "browser.urlbar.suggest.calculator" = true;
          "browser.urlbar.unitConversion.enabled" = true;
          "browser.urlbar.trimHttps" = true;
          "media.videocontrols.picture-in-picture.video-toggle.enabled" = true;
          "browser.shell.checkDefaultBrowser" = false;
          "browser.shell.didSkipDefaultBrowserCheckOnFirstRun" = true;
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
