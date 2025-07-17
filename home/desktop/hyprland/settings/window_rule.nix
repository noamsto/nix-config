{lib, ...}: {
  wayland.windowManager.hyprland.settings = {
    # layer rules
    layerrule = let
      toRegex = list: let
        elements = lib.concatStringsSep "|" list;
      in "^(${elements})$";

      lowopacity = [
        "bar"
        "calendar"
        "notifications"
        "system-menu"
      ];

      highopacity = [
        "walker"
        "osd"
        "logout_dialog"
      ];

      blurred = lib.concatLists [
        lowopacity
        highopacity
      ];
    in [
      "blur, ${toRegex blurred}"
      "xray 1, ${toRegex ["bar"]}"
      "ignorealpha 0.5, ${toRegex (highopacity ++ ["music"])}"
      "ignorealpha 0.2, ${toRegex lowopacity}"
    ];

    # window rules
    windowrulev2 = [
      "suppressevent maximize, class:.*"

      # telegram media viewer
      "float, title:^(Media viewer)$"

      # gnome calculator
      "float, class:^(org.gnome.Calculator)$"
      "size 360 490, class:^(org.gnome.Calculator)$"

      # Common floating windows
      "float, class:^(pavucontrol)$"
      "float, class:^(nm-connection-editor)$"
      "float, class:^(blueman-manager)$"
      "float, class:^(file-roller)$"
      "float, class:^(org.gnome.Nautilus)$,title:^(Properties)$"

      # make Firefox PiP window floating and sticky
      "float, title:^(Picture-in-Picture)$"
      "pin, title:^(Picture-in-Picture)$"

      # Browser PiP windows
      "float, class:^(Brave-browser)$,title:^(Picture-in-Picture)$"
      "pin, class:^(Brave-browser)$,title:^(Picture-in-Picture)$"
      "float, class:^(chromium)$,title:^(Picture-in-Picture)$"
      "pin, class:^(chromium)$,title:^(Picture-in-Picture)$"

      # Move browser to current workspace if not on visible workspace
      "movetoworkspace name:current, class:^(Brave-browser)$"

      # throw sharing indicators away
      "workspace special silent, title:^(Firefox — Sharing Indicator)$"
      "workspace special silent, title:^(.*is sharing (your screen|a window)\.)$"

      # Media players
      "float, class:^(vlc)$"
      "idleinhibit focus, class:^(vlc)$"
      "idleinhibit focus, class:^(mpv|.+exe|celluloid)$"

      # Browser idle inhibit
      "idleinhibit focus, class:^(firefox)$, title:^(.*YouTube.*)$"
      "idleinhibit fullscreen, class:^(firefox)$"
      "idleinhibit focus, class:^(Brave-browser)$,title:^(.*YouTube.*)$"
      "idleinhibit fullscreen, class:^(Brave-browser)$"
      "idleinhibit focus, class:^(chromium)$,title:^(.*YouTube.*)$"
      "idleinhibit fullscreen, class:^(chromium)$"

      # File manager progress dialogs
      "float, class:^(dolphin)$,title:^(Progress Dialog)$"
      "float, class:^(dolphin)$,title:^(Copying)$"
      "float, class:^(thunar)$,title:^(File Operation Progress)$"

      # Communication apps
      "workspace 5 silent, class:^(ferdium)$"
      "workspace 5 silent, class:^(slack)$"
      "workspace 5 silent, class:^(Slack)$"
      "workspace 5 silent, class:^(discord)$"
      "workspace 5 silent, class:^(Discord)$"
      "workspace 5 silent, class:^(telegram)$"
      "workspace 5 silent, class:^(Telegram)$"

      # Productivity apps
      "workspace 3 silent, class:^(obsidian)$"
      "workspace 3 silent, class:^(Obsidian)$"

      # start spotify in ws9
      "workspace 9 silent, title:^(Spotify( Premium)?)$"
      "workspace 9 silent, class:^(Spotify)$"

      # Development tools
      "workspace 2 silent, class:^(sublime_merge)$"
      "workspace 2 silent, class:^(code)$"
      "workspace 2 silent, class:^(Code)$"
      "workspace 2 silent, class:^(postman)$"
      "workspace 2 silent, class:^(Postman)$"
      "workspace 2 silent, class:^(dbeaver)$"

      # OBS Studio
      "workspace 5 silent, class:^(com.obsproject.Studio)$"
      "workspace 5 silent, class:^(obs)$"

      # Zoom
      "float, class:^(zoom)$,title:^(Zoom Meeting)$"
      "idleinhibit focus, class:^(zoom)$"

      "dimaround, class:^(gcr-prompter)$"
      "dimaround, class:^(xdg-desktop-portal-gtk)$"
      "dimaround, class:^(polkit-gnome-authentication-agent-1)$"

      # fix xwayland apps
      "rounding 0, xwayland:1"
      "center, class:^(.*jetbrains.*)$, title:^(Confirm Exit|Open Project|win424|win201|splash)$"
      "size 640 400, class:^(.*jetbrains.*)$, title:^(splash)$"

      # don't render hyprbars on tiling windows
      "plugin:hyprbars:nobar, floating:0"
    ];
  };
}
