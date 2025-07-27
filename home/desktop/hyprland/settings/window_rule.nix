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

      # General floating window rules - center and size when toggled to float
      "center, floating:1" # Center all floating windows
      "size 60% 70%, floating:1" # Set default size for floating windows

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

      # Bluetooth pairing dialogs
      "float, class:^(blueman-agent)$"
      "center, class:^(blueman-agent)$"
      "dimaround, class:^(blueman-agent)$"
      "stayfocused, class:^(blueman-agent)$"
      "float, class:^(blueman-applet)$,title:^(Bluetooth)$"
      "center, class:^(blueman-applet)$,title:^(Bluetooth)$"
      "dimaround, class:^(blueman-applet)$,title:^(Bluetooth)$"
      "float, title:^(Bluetooth.*[Pp]airing)$"
      "center, title:^(Bluetooth.*[Pp]airing)$"
      "dimaround, title:^(Bluetooth.*[Pp]airing)$"
      "stayfocused, title:^(Bluetooth.*[Pp]airing)$"
      "float, title:^(.*[Bb]luetooth.*[Aa]uthentication)$"
      "center, title:^(.*[Bb]luetooth.*[Aa]uthentication)$"
      "dimaround, title:^(.*[Bb]luetooth.*[Aa]uthentication)$"
      "stayfocused, title:^(.*[Bb]luetooth.*[Aa]uthentication)$"

      # Additional Bluetooth dialogs
      "float, class:^(gnome-bluetooth)$"
      "center, class:^(gnome-bluetooth)$"
      "dimaround, class:^(gnome-bluetooth)$"
      "stayfocused, class:^(gnome-bluetooth)$"
      "float, title:^(.*[Pp]airing [Rr]equest)$"
      "center, title:^(.*[Pp]airing [Rr]equest)$"
      "dimaround, title:^(.*[Pp]airing [Rr]equest)$"
      "stayfocused, title:^(.*[Pp]airing [Rr]equest)$"
      "float, title:^(.*[Bb]luetooth.*[Pp]asskey)$"
      "center, title:^(.*[Bb]luetooth.*[Pp]asskey)$"
      "dimaround, title:^(.*[Bb]luetooth.*[Pp]asskey)$"
      "stayfocused, title:^(.*[Bb]luetooth.*[Pp]asskey)$"
      "float, title:^(.*[Bb]luetooth.*[Cc]onfirm)$"
      "center, title:^(.*[Bb]luetooth.*[Cc]onfirm)$"
      "dimaround, title:^(.*[Bb]luetooth.*[Cc]onfirm)$"
      "stayfocused, title:^(.*[Bb]luetooth.*[Cc]onfirm)$"

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
      "workspace special silent, title:^(.*Sharing Indicator)$"

      # better screen sharing window handling
      "float,title:^(.*is sharing (your screen|a window).*)$"
      "size 800 600,title:^(Volume Control)$"

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

      # Productivity apps
      "workspace 3 silent, class:^(obsidian)$"
      "workspace 3 silent, class:^(Obsidian)$"

      # start youtube-music in ws9
      "workspace 9 silent, title:^(YouTube Music)$"
      "workspace 9 silent, class:^(YouTube Music)$"

      # Zoom
      "float, class:^(zoom)$,title:^(Zoom Meeting)$"
      "idleinhibit focus, class:^(zoom)$"

      "dimaround, class:^(gcr-prompter)$"
      "dimaround, class:^(xdg-desktop-portal-gtk)$"
      "dimaround, class:^(hyprpolkitagent)$"

      # fix xwayland apps
      "rounding 0, xwayland:1"
      "center, class:^(.*jetbrains.*)$, title:^(Confirm Exit|Open Project|win424|win201|splash)$"
      "size 640 400, class:^(.*jetbrains.*)$, title:^(splash)$"

      # don't render hyprbars on tiling windows
      "plugin:hyprbars:nobar, floating:0"

      # Fullscreen focus mode rules
      "noborder, fullscreen:1" # Remove borders in fullscreen
      "noshadow, fullscreen:1" # Remove shadows in fullscreen
      "rounding 0, fullscreen:1" # Remove rounding in fullscreen
      "opacity 0.95, fullscreen:1" # Keep slight transparency for focus mode
      "plugin:hyprbars:nobar, fullscreen:1" # Hide hyprbars in fullscreen
    ];

    # Fullscreen-specific rules - removed invalid rule
  };
}
