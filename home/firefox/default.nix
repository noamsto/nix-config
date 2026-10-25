{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  # Linux hosts with desktop.mode = none stay Firefox-free; macOS gets the
  # cask-backed automation profile everywhere.
  enabled = isDarwin || osConfig.desktop.isEnabled;

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

    # Sideloaded add-ons (see meetToBraveExtensions) start disabled otherwise.
    "extensions.autoDisableScopes" = 0;

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
    # SCROLLING & INPUT
    # =======================================================================
    "general.smoothScroll" = true;
    "general.smoothScroll.msdPhysics.enabled" = true;

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

  # Wayland/GTK-only prefs; macOS Firefox ignores them.
  firefoxLinuxSettings = {
    # =======================================================================
    # WAYLAND & DISPLAY
    # =======================================================================
    "widget.wayland.fractional-scale.enabled" = true;
    "widget.use-xdg-desktop-portal.file-picker" = 1;
    "widget.use-xdg-desktop-portal.mime-handler" = 1;

    # =======================================================================
    # SCROLLING & INPUT
    # =======================================================================
    "apz.gtk.touchpad_hold.enabled" = true;
  };

  firefoxSettings = firefoxCommonSettings // lib.optionalAttrs isLinux firefoxLinuxSettings;

  # Hide the window control buttons (minimize, maximize, close) from the titlebar
  firefoxUserChrome = ''
    .titlebar-buttonbox-container {
      display: none !important;
    }
  '';

  firefoxBin =
    if isDarwin
    then "/Applications/Firefox.app/Contents/MacOS/firefox"
    else "${config.programs.firefox.finalPackage}/bin/firefox";

  # Launch the dedicated automation profile with Marionette active so the
  # firefox-devtools MCP can attach on port 2828 (see home/ai/mcp-servers.nix).
  # Marionette only turns on with the --marionette flag, so a profile alone
  # can't enable it — this wrapper is the entry point.
  firefox-marionette = pkgs.writeShellScriptBin "firefox-marionette" ''
    exec ${firefoxBin} -P automation --marionette --remote-debugging-port=9222 "$@"
  '';

  # Meet links clicked inside Firefox never reach the desktop URL handler, so
  # External Application Button redirects those navigations to a native host
  # that opens them in Brave. The add-on's own helper (com.add0n.node) is an
  # unmanaged Node install that runs arbitrary commands; this stand-in speaks
  # the same wire protocol but ignores the requested command and only ever
  # launches Brave on one validated meet.google.com URL.
  externalApplicationId = "{65b77238-bb05-470a-a445-ec0efe1d66c4}";
  # LaunchServices rather than exec'ing the app binary, so Brave (not Firefox)
  # is the responsible process for its camera/mic grants.
  braveLauncher =
    if isDarwin
    then "/usr/bin/open"
    else lib.getExe config.programs.brave.finalPackage;
  meetToBraveHost = pkgs.writers.writePython3Bin "meet-to-brave-host" {flakeIgnore = ["E501"];} ''
    import json
    import re
    import struct
    import subprocess
    import sys
    from urllib.parse import urlsplit

    BRAVE = "${braveLauncher}"


    def read_message():
        header = sys.stdin.buffer.read(4)
        if len(header) < 4:
            return None
        (length,) = struct.unpack("=I", header)
        return json.loads(sys.stdin.buffer.read(length))


    def reply(payload):
        data = json.dumps(payload).encode()
        sys.stdout.buffer.write(struct.pack("=I", len(data)) + data)
        sys.stdout.buffer.flush()


    def meet_url(args):
        if not isinstance(args, list) or len(args) != 1 or not isinstance(args[0], str):
            return None
        url = args[0]
        if not re.fullmatch(r"[!-~]+", url):
            return None
        parts = urlsplit(url)
        try:
            port = parts.port
        except ValueError:
            return None
        if parts.scheme != "https" or parts.hostname != "meet.google.com":
            return None
        if parts.username is not None or parts.password is not None or port is not None:
            return None
        return url


    msg = read_message()
    if not isinstance(msg, dict):
        sys.exit(0)
    if msg.get("cmd") == "env":
        reply({"env": {}})
    elif msg.get("cmd") == "exec":
        url = meet_url(msg.get("arguments"))
        if url is None:
            reply({"code": 1, "stdout": "", "stderr": "refused: not an https://meet.google.com URL"})
        else:
            subprocess.Popen(
                [BRAVE, ${lib.optionalString isDarwin ''"-b", "com.brave.Browser", ''}url],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            reply({"code": 0, "stdout": "", "stderr": ""})
    else:
        reply({"code": 1, "stdout": "", "stderr": "unsupported command"})
  '';
  meetToBraveManifest = pkgs.writeText "com.add0n.node.json" (builtins.toJSON {
    name = "com.add0n.node";
    description = "Open Meet links in Brave";
    path = lib.getExe meetToBraveHost;
    type = "stdio";
    allowed_extensions = [externalApplicationId];
  });
  meetToBraveNativeHost = pkgs.runCommand "meet-to-brave-native-host" {} ''
    install -Dm444 ${meetToBraveManifest} $out/lib/mozilla/native-messaging-hosts/com.add0n.node.json
  '';
  # Not configured through extensions.settings: HM then turns off IndexedDB
  # extension storage for every add-on in the profile, wiping uBlock, Dark
  # Reader and the others. The add-on's rule must also be created in its own
  # options page, which is where it asks for the host permission it needs.
  # The darwin daily profile gets no user.js, so no autoDisableScopes = 0
  # either: there the add-on must be enabled once in about:addons.
  meetToBraveExtensions.packages = [pkgs.firefox-addons.external-application];

  automationAddons = [pkgs.firefox-addons.onepassword-password-manager];
in {
  config = lib.mkIf enabled {
    programs.firefox =
      if isDarwin
      then {
        enable = true;
        # Firefox comes from the Homebrew cask.
        package = null;
        # Otherwise HM writes EnterprisePoliciesEnabled into the cask's plist.
        darwinDefaultsId = null;
        nativeMessagingHosts = [meetToBraveNativeHost];
        profiles = {
          # Existing daily profile: HM must not write user.js into it. The
          # install-locked default lives in installs.ini, which HM never touches.
          default-release = {
            id = 0;
            name = "default-release";
            path = "i2bldrhv.default-release-1780495918171";
            isDefault = true;
            extensions = meetToBraveExtensions;
          };

          automation = {
            # Firefox stops reading profiles.ini at the first missing ProfileN.
            id = 1;
            path = "automation";
            settings = firefoxSettings // {"marionette.port" = 2828;};
            extensions.packages = automationAddons;
          };
        };
      }
      else {
        enable = true;
        configPath = ".mozilla/firefox";
        nativeMessagingHosts = [meetToBraveNativeHost];
        profiles = {
          personal = {
            id = 0;
            path = "personal";
            isDefault = true;
            settings = firefoxSettings;
            userChrome = firefoxUserChrome;
            extensions = meetToBraveExtensions;
          };

          # Dedicated automation profile driven by `firefox-marionette`. Pins the
          # Marionette port to match the firefox-devtools MCP. 1Password is
          # declared here so a freshly-created profile is login-ready.
          automation = {
            id = 2;
            path = "automation";
            settings = firefoxSettings // {"marionette.port" = 2828;};
            extensions.packages = automationAddons;
          };
        };
      };

    home.packages = [firefox-marionette];
  };
}
