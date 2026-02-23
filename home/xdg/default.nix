# XDG stands for "Cross-Desktop Group", with X used to mean "cross".
# It's a bunch of specifications from freedesktop.org intended to standardize desktops and
# other GUI applications on various systems (primarily Unix-like) to be interoperable:
#   https://www.freedesktop.org/wiki/Specifications/
{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    xdg-utils # provides cli tools such as `xdg-mime` `xdg-open`
    xdg-user-dirs
  ];

  xdg = {
    enable = true;
    cacheHome = config.home.homeDirectory + "/.local/cache";
    systemDirs.data = ["${config.home.homeDirectory}/.local/share/flatpak/exports/share/" "/var/lib/flatpak/exports/share/"];

    mimeApps = {
      enable = true;
      defaultApplications = let
        browser = ["firefox-workspace-switch.desktop"];
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
        "x-scheme-handler/http" = browser;
        "x-scheme-handler/https" = browser;
        "x-scheme-handler/slack" = "slack.desktop";
        "x-scheme-handler/unknown" = browser;
      };

      associations.added = {
        "x-scheme-handler/slack" = "slack.desktop;Slack.desktop;";

        # Browsers - Firefox with workspace switcher primary, plain Firefox and Brave as fallbacks
        "text/html" = "firefox-workspace-switch.desktop;firefox.desktop;brave-browser.desktop;";
        "x-scheme-handler/http" = "firefox-workspace-switch.desktop;firefox.desktop;brave-browser.desktop;";
        "x-scheme-handler/https" = "firefox-workspace-switch.desktop;firefox.desktop;brave-browser.desktop;";
        "application/xhtml+xml" = "firefox-workspace-switch.desktop;firefox.desktop;brave-browser.desktop;";

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

    userDirs = {
      enable = true;
      createDirectories = true;
      extraConfig = {
        SCREENSHOTS = "${config.xdg.userDirs.pictures}/Screenshots";
      };
    };
  };
}
