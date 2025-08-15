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
        browser = ["brave-browser.desktop"];
      in {
        "application/json" = browser;
        "application/pdf" = "evince.desktop";

        # Archives - missing critical mime types
        "application/zip" = "org.kde.ark.desktop";
        "application/x-tar" = "org.kde.ark.desktop";
        "application/x-compressed-tar" = "org.kde.ark.desktop";
        "application/x-7z-compressed" = "org.kde.ark.desktop";
        "application/x-rar" = "org.kde.ark.desktop";

        # Text files - missing important ones
        "text/plain" = "nvim.desktop";
        "text/markdown" = "nvim.desktop";
        "application/x-shellscript" = "nvim.desktop";

        # Video files - critical missing
        "video/mp4" = "mpv.desktop";
        "video/x-matroska" = "mpv.desktop";
        "video/webm" = "mpv.desktop";

        # Audio files - critical missing
        "audio/mpeg" = "mpv.desktop";
        "audio/ogg" = "mpv.desktop";
        "audio/flac" = "mpv.desktop";

        # Image types - gwenview for viewing, gimp for editing
        "image/jpeg" = "org.kde.gwenview.desktop";
        "image/jpg" = "org.kde.gwenview.desktop";
        "image/png" = "org.kde.gwenview.desktop";
        "image/gif" = "org.kde.gwenview.desktop";
        "image/webp" = "org.kde.gwenview.desktop";
        "image/tiff" = "org.kde.gwenview.desktop";
        "image/bmp" = "org.kde.gwenview.desktop";
        "image/svg+xml" = "org.kde.gwenview.desktop";

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

        "x-scheme-handler/about" = browser;
        "x-scheme-handler/ftp" = browser;
        "x-scheme-handler/http" = browser;
        "x-scheme-handler/https" = browser;
        "x-scheme-handler/slack" = "slack.desktop";
        "x-scheme-handler/unknown" = browser;
      };

      associations.added = {
        "x-scheme-handler/slack" = "slack.desktop;Slack.desktop;";

        # Image editing - add GIMP as alternative
        "image/jpeg" = "org.kde.gwenview.desktop;gimp.desktop;";
        "image/png" = "org.kde.gwenview.desktop;gimp.desktop;";
        "image/gif" = "org.kde.gwenview.desktop;gimp.desktop;";
        "image/webp" = "org.kde.gwenview.desktop;gimp.desktop;";
        "image/tiff" = "org.kde.gwenview.desktop;gimp.desktop;";
        "image/bmp" = "org.kde.gwenview.desktop;gimp.desktop;";
        "image/svg+xml" = "org.kde.gwenview.desktop;gimp.desktop;";
      };
      associations.removed = let
        browser = ["google-chrome.desktop"];
      in {
        "text/html" = browser;
        "text/xml" = browser;
        "application/xml" = browser;
        "application/xhtml+xml" = browser;
        "application/xhtml_xml" = browser;
        "application/rdf+xml" = browser;
        "application/rss+xml" = browser;
        "image/gif" = browser;
        "image/jpeg" = browser;
        "image/png" = browser;
        "image/webp" = browser;
        "x-scheme-handler/http" = browser;
        "x-scheme-handler/https" = browser;
        "application/pdf" = browser;
      };
    };

    userDirs = {
      enable = true;
      createDirectories = true;
      extraConfig = {
        XDG_SCREENSHOTS_DIR = "${config.xdg.userDirs.pictures}/Screenshots";
      };
    };
  };
}
