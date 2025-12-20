{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  # Firefox settings - injected as user.js into existing profile
  # This avoids conflicts with Firefox managing its own profiles.ini
  firefoxSettings = {
    # =========================================================================
    # PERFORMANCE & HARDWARE ACCELERATION (The "Fix")
    # =========================================================================
    # Enable the modern GPU-based rendering engine (WebRender)
    "gfx.webrender.all" = true;

    # Enable Hardware Video Acceleration (VA-API)
    # Reduces CPU usage significantly during video playback
    "media.ffmpeg.vaapi.enabled" = true;

    # Enable WebGPU (Required for some modern sites & Cloudflare challenges)
    "dom.webgpu.enabled" = true;

    # Ensure layers acceleration is NOT disabled
    "layers.acceleration.disabled" = false;

    # Unload tabs to save RAM, but keep enough for the challenges to run
    "browser.tabs.unloadOnLowMemory" = true;

    # =========================================================================
    # CLOUDFLARE COMPATIBILITY & PRIVACY BALANCE
    # =========================================================================
    # CRITICAL: Disable "Resist Fingerprinting"
    # When true, this fakes your timezone to UTC and window size, causing immediate Cloudflare loops.
    "privacy.resistFingerprinting" = false;

    # Standard tracking protection (Blocks trackers, but allows Cloudflare scripts)
    "browser.contentblocking.category" = "standard";

    # Disable specific fingerprinting blocking that breaks verification
    "privacy.trackingprotection.fingerprinting.enabled" = false;

    # Allow service workers (Cloudflare uses these for background tokens)
    "dom.serviceWorkers.enabled" = true;

    # Enable Resource Timing (Required for bot detection analysis)
    "dom.enable_resource_timing" = true;

    # =========================================================================
    # UI & VERTICAL TABS (Firefox 133+)
    # =========================================================================
    "sidebar.verticalTabs" = true;
    "sidebar.revamp" = true;
    "sidebar.visibility" = "expand-on-hover";
    "browser.compactmode.show" = true;
    "browser.uidensity" = 1; # Compact mode

    # Tab Groups (Firefox 131+)
    "browser.tabs.groups.enabled" = true;

    # =========================================================================
    # WAYLAND & DISPLAY
    # =========================================================================
    # Better scaling on high-DPI screens under Hyprland
    "widget.wayland.fractional-scale.enabled" = true;

    # Use native file pickers (looks better in KDE/Hyprland)
    "widget.use-xdg-desktop-portal.file-picker" = 1;
    "widget.use-xdg-desktop-portal.mime-handler" = 1;

    # Let Firefox auto-detect refresh rate from Hyprland rather than forcing 120Hz
    # (Prevents timing mismatches that trigger bot detection)
    # "layout.frame_rate" = 120;

    # =========================================================================
    # SCROLLING & INPUT
    # =========================================================================
    "general.smoothScroll" = true;
    "general.smoothScroll.msdPhysics.enabled" = true;
    "apz.gtk.touchpad_hold.enabled" = true; # Better touchpad gestures

    # =========================================================================
    # SECURITY & NETWORK
    # =========================================================================
    "dom.security.https_only_mode" = true;
    "dom.security.https_only_mode.upgrade_local" = false; # Helpful for local NAS/Home Assistant

    # Use system DNS (0). If loops persist, try changing to 2 (DNS over HTTPS)
    "network.trr.mode" = 0;

    # Accept cookies (Balanced approach for compatibility)
    "network.cookie.cookieBehavior" = 0;

    # =========================================================================
    # QUALITY OF LIFE
    # =========================================================================
    "browser.urlbar.suggest.calculator" = true;
    "browser.urlbar.unitConversion.enabled" = true;
    "browser.urlbar.trimHttps" = true;
    "media.videocontrols.picture-in-picture.video-toggle.enabled" = true;

    # Disable "Default Browser" checks and warnings
    "browser.shell.checkDefaultBrowser" = false;
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
