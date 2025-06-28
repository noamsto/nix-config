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

    # NOTE: Manage $XDG_CONFIG_HOME/mimeapps.list
    # xdg search all desktop entries from $XDG_DATA_DIRS, check it by command:
    # the system-level desktop entries can be list by command:
    #  echo $XDG_DATA_DIRS
    #   ls -l /run/current-system/sw/share/applications/
    # the user-level desktop entries can be list by command(user noams):
    #  ls /etc/profiles/per-user/noams/share/applications/
    mimeApps = {
      enable = true;
      defaultApplications = let
        browser = ["brave.desktop"];
      in {
        "application/json" = browser;
        "application/pdf" = "evince.desktop";

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
