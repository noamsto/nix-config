{
  pkgs,
  username,
  ...
}: {
  xdg.desktopEntries = {
    Slack-Barracuda = {
      type = "Application";
      name = "Slack-Barracuda";
      exec = "${pkgs.brave}/bin/brave --new-window --app=https://barracuda.slack.com/ %U";
      icon = "/home/${username}/.local/share/icons/hicolor/48x48/apps/slack.png";
      comment = "Launch Slack app in single site broweser using brave";
      terminal = false;
    };
  };

  home.file."slack.png" = {
    source = ./icons/slack-icon.48x48.png;
    target = ".local/share/icons/hicolor/48x48/apps/slack.png";
  };
}
