{
  config,
  osConfig,
  lib,
  pkgs,
  ...
}: let
  firefoxCommonSettings = {
    # =======================================================================
    # PERFORMANCE & HARDWARE ACCELERATION
    # =======================================================================
    "gfx.webrender.all" = true;
    # Renamed from media.ffmpeg.vaapi.enabled in FF 116. Covers WebRTC decode
    # too; there is deliberately no encode counterpart, since FFmpegVideoEncoder
    # has no VA-API path — outgoing camera video is software-encoded whatever
    # prefs are set. https://bugzilla.mozilla.org/show_bug.cgi?id=1658900
    "media.hardware-video-decoding.enabled" = true;
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
    # NATIVE PROFILE SYSTEM (Firefox 138+) - per-profile color/avatar
    # =======================================================================
    "browser.profiles.enabled" = true;

    # =======================================================================
    # UI & VERTICAL TABS (Firefox 133+)
    # =======================================================================
    "sidebar.verticalTabs" = true;
    "sidebar.revamp" = true;
    "sidebar.visibility" = "expand-on-hover";
    "browser.compactmode.show" = true;
    "browser.uidensity" = 1;
    "browser.tabs.groups.enabled" = true;
    # Smart Tab Groups: local ML suggests tabs for a group + auto-names it.
    # Engine (smart.enabled) and runtime (browser.ml.enable) default on; optin
    # is the model-download gate, normally flipped by the in-UI prompt.
    "browser.tabs.groups.smart.optin" = true;

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
    # THEMING - Follow system color-scheme for page content
    # =======================================================================
    # -1 = follow system preference (from portal/dconf)
    "layout.css.prefers-color-scheme.content-override" = -1;

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

    # Required for userChrome.css to take effect
    "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
  };

  # Hide the window control buttons (minimize, maximize, close) from the titlebar
  firefoxUserChrome = ''
    .titlebar-buttonbox-container {
      display: none !important;
    }
  '';

  # Launch the dedicated automation profile with Marionette active so the
  # firefox-devtools MCP can attach on port 2828 (see home/ai/mcp-servers.nix).
  # Marionette only turns on with the --marionette flag, so a profile alone
  # can't enable it — this wrapper is the entry point.
  firefox-marionette = pkgs.writeShellScriptBin "firefox-marionette" ''
    exec ${config.programs.firefox.finalPackage}/bin/firefox -P automation --marionette --remote-debugging-port=9222 "$@"
  '';
in {
  imports =
    [
      ./theme
      ./easyeffects
      ./wireplumber
      ./mpv.nix
      ./kdenlive.nix
      ./obsidian.nix
    ]
    ++ lib.optionals (osConfig.desktop.mode == "hyprland") [
      ./hyprland
      ./noctalia
    ];

  # Hardware-accelerated video for Electron apps using system Electron
  # Apps with bundled Electron (Slack, etc.) get flags via overlays in lib/overlays.nix
  xdg.configFile."electron-flags.conf".text = ''
    --enable-features=VaapiVideoDecodeLinuxGL,VaapiVideoEncoder,VaapiIgnoreDriverChecks
    --enable-gpu-rasterization
    --enable-zero-copy
    --ignore-gpu-blocklist
  '';

  programs = {
    obs-studio.enable = true;

    brave = {
      enable = true;
      # NOTE: Command-line flags are applied via overlay in lib/overlays.nix
      # Also set via BRAVE_USER_FLAGS env var in Hyprland as a fallback
    };

    firefox = {
      enable = true;
      configPath = ".mozilla/firefox";
      profiles =
        {
          personal = {
            id = 0;
            path = "personal";
            isDefault = true;
            settings = firefoxCommonSettings;
            userChrome = firefoxUserChrome;
          };

          # Dedicated automation profile driven by `firefox-marionette`. Pins the
          # Marionette port to match the firefox-devtools MCP. 1Password is
          # declared here so a freshly-created profile is login-ready; the addon
          # set is Linux-only, so guard the darwin build.
          automation = {
            id = 2;
            path = "automation";
            settings = firefoxCommonSettings // {"marionette.port" = 2828;};
            extensions.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              pkgs.firefox-addons.onepassword-password-manager
            ];
          };
        }
        // lib.optionalAttrs (osConfig.profile == "work") {
          work = {
            id = 1;
            path = "work";
            settings = firefoxCommonSettings;
            userChrome = firefoxUserChrome;
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

  home.packages = [firefox-marionette];
}
