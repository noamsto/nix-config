{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  # Firefox settings - injected as user.js into existing profile
  # This avoids conflicts with Firefox managing its own profiles.ini
  firefoxSettings = {
    # === Vertical Tabs (Firefox 133+) ===
    "sidebar.verticalTabs" = true;
    "sidebar.revamp" = true;
    "sidebar.visibility" = "expand-on-hover";

    # === Tab Groups (Firefox 131+) ===
    "browser.tabs.groups.enabled" = true;

    # === UI Improvements ===
    "browser.compactmode.show" = true;
    "browser.uidensity" = 1; # 0=normal, 1=compact, 2=touch
    "browser.tabs.tabmanager.enabled" = true;

    # === Privacy & Security ===
    "dom.security.https_only_mode" = true;
    "dom.security.https_only_mode.upgrade_local" = false; # Allow local HTTP (naspi)
    "network.trr.mode" = 2; # DNS-over-HTTPS (2=preferred)
    "privacy.trackingprotection.enabled" = true;
    "privacy.trackingprotection.socialtracking.enabled" = true;
    "privacy.trackingprotection.cryptomining.enabled" = true;
    "privacy.trackingprotection.fingerprinting.enabled" = true;

    # === Container Tabs ===
    "privacy.userContext.enabled" = true;
    "privacy.userContext.ui.enabled" = true;

    # === Performance ===
    "browser.tabs.unloadOnLowMemory" = true;
    "dom.webgpu.enabled" = true;
    "media.av1.enabled" = true;
    "gfx.webrender.all" = true;
    "media.ffmpeg.vaapi.enabled" = true;
    "media.hardware-video-decoding.force-enabled" = true;

    # === Quality of Life ===
    "browser.urlbar.suggest.calculator" = true;
    "browser.urlbar.unitConversion.enabled" = true;
    "browser.urlbar.trimHttps" = true;
    "browser.tabs.hoverPreview.enabled" = true;
    "findbar.highlightAll" = true;
    "reader.parse-on-load.enabled" = true;

    # === Wayland & Display ===
    "widget.wayland.fractional-scale.enabled" = true;
    "widget.use-xdg-desktop-portal.file-picker" = 1;
    "widget.use-xdg-desktop-portal.mime-handler" = 1;
    "layout.frame_rate" = 120;

    # === Scrolling ===
    "general.smoothScroll" = true;
    "general.smoothScroll.msdPhysics.enabled" = true;
    "apz.gtk.pangesture.page_delta_mode_multiplier" = 0.4;
    "apz.gtk.touchpad_hold.enabled" = true;

    # === Media ===
    "media.videocontrols.picture-in-picture.video-toggle.enabled" = true;

    # === Disable Annoyances ===
    "browser.shell.checkDefaultBrowser" = false;
    "browser.shell.didSkipDefaultBrowserCheckOnFirstRun" = true;
    "browser.aboutConfig.showWarning" = false;
  };

  # Convert settings attrset to user.js format
  mkUserJs = settings:
    lib.concatStringsSep "\n" (lib.mapAttrsToList (
        name: value: "user_pref(${builtins.toJSON name}, ${builtins.toJSON value});"
      )
      settings);
in {
  imports =
    [
      ./theme
      ./easyeffects
    ]
    ++ lib.optionals (osConfig.desktop.mode == "hyprland") [
      ./hyprland
    ];

  # Inject user.js directly into Firefox profile (avoids profiles.ini conflicts)
  home.file.".mozilla/firefox/mp41xmce.default/user.js" = {
    text = mkUserJs firefoxSettings;
  };

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
      # Don't manage profiles.ini - let Firefox handle it
      # Settings are injected via home.file above
    };

    chromium = {
      enable = lib.mkIf (osConfig.profile == "work") true;
      commandLineArgs = [
        "--disable-features=WaylandWpColorManagerV1"
      ];
    };
  };
}
