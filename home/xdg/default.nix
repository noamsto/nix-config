# XDG stands for "Cross-Desktop Group", with X used to mean "cross".
# It's a bunch of specifications from freedesktop.org intended to standardize desktops and
# other GUI applications on various systems (primarily Unix-like) to be interoperable:
#   https://www.freedesktop.org/wiki/Specifications/
{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}: let
  # The profile the primary Firefox entry launches. Both the MIME default and
  # the router derive from this one binding so they cannot drift.
  firefoxProfile =
    if osConfig.profile == "work"
    then "work"
    else "personal";
  primaryBrowser = "firefox-${firefoxProfile}.desktop";
  inherit (pkgs.stdenv.hostPlatform) isLinux;

  # Routes Meet links to Brave and every other link to the primary Firefox.
  # Both launchers come from the packages the MIME entries already use, so the
  # per-profile Firefox and the Wayland flags on Brave keep applying.
  browserRouter = pkgs.writeShellApplication {
    name = "browser-router";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      brave=${lib.getExe config.programs.brave.finalPackage}
      firefox=${lib.getExe config.programs.firefox.finalPackage}
      firefox_profile=(-P ${firefoxProfile})

      if [ "$#" -eq 0 ]; then
        exec "$firefox" "''${firefox_profile[@]}"
      fi

      meet_urls=()
      other_urls=()
      for url in "$@"; do
        # Pull the host out of the URL without shelling out to a URL parser:
        # strip scheme, userinfo, port, path, query and fragment.
        host=''${url#*://}
        host=''${host%%/*}
        host=''${host##*@}
        host=''${host%%:*}
        host=''${host%%\?*}
        host=''${host%%#*}
        host=''${host,,}
        if [ "$host" = "meet.google.com" ]; then
          meet_urls+=("$url")
        else
          other_urls+=("$url")
        fi
      done

      # Detach so the router exits immediately, as a MIME handler should.
      if [ "''${#meet_urls[@]}" -gt 0 ]; then
        nohup "$brave" "''${meet_urls[@]}" >/dev/null 2>&1 &
      fi
      if [ "''${#other_urls[@]}" -gt 0 ]; then
        nohup "$firefox" "''${firefox_profile[@]}" "''${other_urls[@]}" >/dev/null 2>&1 &
      fi
    '';
  };

  # Only desktop hosts install the browsers the router needs; elsewhere the
  # scheme handlers stay on the primary Firefox entry.
  routerEnabled = isLinux && osConfig.desktop.isEnabled;
  urlHandler =
    if routerEnabled
    then "browser-router.desktop"
    else primaryBrowser;
in {
  # xdg-utils / xdg-user-dirs are freedesktop (Linux) tools.
  home.packages = lib.optionals isLinux (with pkgs; [
    xdg-utils # provides cli tools such as `xdg-mime` `xdg-open`
    xdg-user-dirs
  ]);

  # xdg.enable / cacheHome are cross-platform. systemDirs, mimeApps and userDirs
  # are Linux-only HM modules (their meta.platforms is linux-only) — gate each
  # with mkIf so they stay un-enabled (and thus inert) on darwin.
  xdg = {
    enable = true;
    cacheHome = config.home.homeDirectory + "/.local/cache";

    systemDirs.data = lib.mkIf isLinux ["${config.home.homeDirectory}/.local/share/flatpak/exports/share/" "/var/lib/flatpak/exports/share/"];

    desktopEntries = lib.mkIf routerEnabled {
      browser-router = {
        name = "Browser Router";
        genericName = "Web Browser";
        exec = "${browserRouter}/bin/browser-router %U";
        icon = "firefox";
        terminal = false;
        mimeType = ["x-scheme-handler/http" "x-scheme-handler/https"];
        categories = ["Network" "WebBrowser"];
      };
    };

    mimeApps = lib.mkIf isLinux {
      enable = true;
      defaultApplications = let
        browser = [primaryBrowser];
      in {
        "application/json" = browser;
        "application/pdf" = "org.gnome.Evince.desktop";

        # Archives - missing critical mime types
        "application/zip" = "org.gnome.FileRoller.desktop";
        "application/x-tar" = "org.gnome.FileRoller.desktop";
        "application/x-compressed-tar" = "org.gnome.FileRoller.desktop";
        "application/x-7z-compressed" = "org.gnome.FileRoller.desktop";
        "application/x-rar" = "org.gnome.FileRoller.desktop";

        # Text files - missing important ones
        "text/plain" = "nvim.desktop";
        "text/markdown" = "nvim.desktop";
        "application/x-shellscript" = "nvim.desktop";

        # Directories
        "inode/directory" = "thunar.desktop";

        # Video files - critical missing
        "video/mp4" = "mpv.desktop";
        "video/x-matroska" = "mpv.desktop";
        "video/webm" = "mpv.desktop";

        # Audio files - critical missing
        "audio/mpeg" = "mpv.desktop";
        "audio/ogg" = "mpv.desktop";
        "audio/flac" = "mpv.desktop";

        # Image types - eog for viewing, gimp for editing
        "image/jpeg" = "org.gnome.eog.desktop";
        "image/jpg" = "org.gnome.eog.desktop";
        "image/png" = "org.gnome.eog.desktop";
        "image/gif" = "org.gnome.eog.desktop";
        "image/webp" = "org.gnome.eog.desktop";
        "image/tiff" = "org.gnome.eog.desktop";
        "image/bmp" = "org.gnome.eog.desktop";
        "image/svg+xml" = "org.gnome.eog.desktop";

        "text/html" = browser;
        "text/xml" = browser;
        "application/xml" = browser;
        "application/xhtml+xml" = browser;
        "application/xhtml_xml" = browser;
        "application/rdf+xml" = browser;
        "application/rss+xml" = browser;
        "application/x-extension-htm" = browser;
        "application/x-extension-html" = browser;
        "application/x-extension-shtml" = browser;
        "application/x-extension-xht" = browser;
        "application/x-extension-xhtml" = browser;

        # Calendar
        "x-scheme-handler/webcal" = "org.gnome.Calendar.desktop";
        "x-scheme-handler/webcals" = "org.gnome.Calendar.desktop";
        "text/calendar" = "org.gnome.Calendar.desktop";

        "x-scheme-handler/about" = browser;
        "x-scheme-handler/ftp" = browser;
        "x-scheme-handler/http" = [urlHandler];
        "x-scheme-handler/https" = [urlHandler];
        "x-scheme-handler/slack" = "slack.desktop";
        "x-scheme-handler/unknown" = browser;

        # Roblox Studio browser-login callback (Vinegar)
        "x-scheme-handler/roblox-studio-auth" = "org.vinegarhq.Vinegar.desktop";
      };

      associations.added = {
        "x-scheme-handler/slack" = "slack.desktop;Slack.desktop;";
        "x-scheme-handler/roblox-studio-auth" = "org.vinegarhq.Vinegar.desktop;";

        # Browsers - profile-specific Firefox primary, plain Firefox and Brave as fallbacks
        "text/html" = "${primaryBrowser};firefox.desktop;brave-browser.desktop;";
        "x-scheme-handler/http" = "${primaryBrowser};firefox.desktop;brave-browser.desktop;";
        "x-scheme-handler/https" = "${primaryBrowser};firefox.desktop;brave-browser.desktop;";
        "application/xhtml+xml" = "${primaryBrowser};firefox.desktop;brave-browser.desktop;";

        # Image editing - add GIMP as alternative
        "image/jpeg" = "org.gnome.eog.desktop;gimp.desktop;";
        "image/png" = "org.gnome.eog.desktop;gimp.desktop;";
        "image/gif" = "org.gnome.eog.desktop;gimp.desktop;";
        "image/webp" = "org.gnome.eog.desktop;gimp.desktop;";
        "image/tiff" = "org.gnome.eog.desktop;gimp.desktop;";
        "image/bmp" = "org.gnome.eog.desktop;gimp.desktop;";
        "image/svg+xml" = "org.gnome.eog.desktop;gimp.desktop;";
      };
    };

    userDirs = lib.mkIf isLinux {
      enable = true;
      createDirectories = true;
      setSessionVariables = true;
      extraConfig = {
        SCREENSHOTS = "${config.xdg.userDirs.pictures}/Screenshots";
      };
    };
  };
}
