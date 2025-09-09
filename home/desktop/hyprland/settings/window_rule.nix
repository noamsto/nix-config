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

      # === ENHANCED FLOATING WINDOWS ===
      "float, class:^(pavucontrol)$"
      "float, class:^(nm-connection-editor)$"
      "float, class:^(blueman-manager)$"
      "float, class:^(file-roller)$" # GNOME Archive Manager
      "float, class:^(org.gnome.Nautilus)$,title:^(Properties)$"

      # Application preferences/settings
      "float, class:^(slack)$,title:^(Preferences)$"
      "float, class:^(brave-browser)$,title:^(Settings)$"
      "float, class:^(spotify)$,title:^(.*Settings.*)$"
      "float, class:^(obsidian)$,title:^(Settings)$"

      # === 1PASSWORD FIXES ===
      # Main 1Password window
      "float, class:^(1Password)$"
      "center, class:^(1Password)$"
      "size 1000 700, class:^(1Password)$"
      "immediate, class:^(1Password)$"

      # 1Password Quick Access
      "float, class:^(1Password)$,title:^(Quick Access)$"
      "center, class:^(1Password)$,title:^(Quick Access)$"
      "size 400 500, class:^(1Password)$,title:^(Quick Access)$"
      "stayfocused, class:^(1Password)$,title:^(Quick Access)$"

      # 1Password hamburger menu and dropdowns - FIX SCALING AND POSITIONING
      "float, class:^(1Password)$,title:^$"
      "immediate, class:^(1Password)$,title:^$"
      "noborder, class:^(1Password)$,title:^$"
      "noshadow, class:^(1Password)$,title:^$"
      "pin, class:^(1Password)$,title:^$" # Keep menu on top
      "stayfocused, class:^(1Password)$,title:^$" # Don't steal focus but stay visible

      # 1Password popup menus, context menus, and zero-size windows
      "float, class:^(1Password)$,size:(0,0)"
      "immediate, class:^(1Password)$,size:(0,0)"
      "noborder, class:^(1Password)$,size:(0,0)"
      "noshadow, class:^(1Password)$,size:(0,0)"
      "pin, class:^(1Password)$,size:(0,0)" # Keep popup on top
      "stayfocused, class:^(1Password)$,size:(0,0)"

      # Small 1Password windows (likely menus/popups)
      "float, class:^(1Password)$,size:(1,1)"
      "immediate, class:^(1Password)$,size:(1,1)"
      "noborder, class:^(1Password)$,size:(1,1)"
      "noshadow, class:^(1Password)$,size:(1,1)"
      "pin, class:^(1Password)$,size:(1,1)"

      # Alternative class names for 1Password
      "float, class:^(1password)$"
      "immediate, class:^(1password)$"
      "float, class:^(com.1password.1Password)$"
      "immediate, class:^(com.1password.1Password)$"

      # Apply hamburger menu fixes to alternative class names too
      "float, class:^(1password)$,title:^$"
      "immediate, class:^(1password)$,title:^$"
      "pin, class:^(1password)$,title:^$"
      "float, class:^(com.1password.1Password)$,title:^$"
      "immediate, class:^(com.1password.1Password)$,title:^$"
      "pin, class:^(com.1password.1Password)$,title:^$"

      # Size dialogs appropriately
      "size 800 600, class:^(pavucontrol)$"
      "size 600 500, class:^(nm-connection-editor)$"
      "size 500 600, class:^(blueman-manager)$"

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
      "float, class:^(thunar)$,title:^(Progress Dialog)$"
      "float, class:^(thunar)$,title:^(Copying)$"
      "float, class:^(thunar)$,title:^(File Operation Progress)$"
      "float, class:^(thunar)$,title:^(Properties)$"

      # === SMART WORKSPACE ASSIGNMENTS ===
      # Web browsers - workspace 1
      "workspace 1 silent, class:^(Brave-browser)$"
      "workspace 1 silent, class:^(brave-browser)$"
      "workspace 1 silent, class:^(chromium)$"

      # Development - workspace 2
      "workspace 2 silent, class:^(code|codium|code-oss|claude-code)$"
      "workspace 2 silent, class:^(jetbrains-.*)$"

      # Productivity and notes - workspace 3
      "workspace 3 silent, class:^(obsidian)$"
      "workspace 3 silent, class:^(Obsidian)$"

      # Communication - workspace 4
      "workspace 4 silent, class:^(slack)$"
      "workspace 4 silent, class:^(Slack)$"
      "workspace 4 silent, class:^(ferdium)$"
      "workspace 4 silent, class:^(zoom)$"

      # Database/API tools - workspace 5
      "workspace 5 silent, class:^(dbeaver)$"
      "workspace 5 silent, class:^(postman)$"

      # Media - workspace 9
      "workspace 9 silent, title:^(YouTube Music)$"
      "workspace 9 silent, class:^(YouTube Music)$"
      "workspace 9 silent, class:^(spotify)$"
      "workspace 9 silent, class:^(vlc)$"
      "workspace 9 silent, class:^(mpv)$"

      # Zoom
      "float, class:^(zoom)$,title:^(Zoom Meeting)$"
      "idleinhibit focus, class:^(zoom)$"

      "dimaround, class:^(gcr-prompter)$"
      # === SYSTEM DIALOGS - ENSURE THEY APPEAR ON TOP OF FULLSCREEN APPS ===
      # File picker dialogs
      "dimaround, class:^(xdg-desktop-portal-gtk)$"
      "float, class:^(xdg-desktop-portal-gtk)$"
      "pin, class:^(xdg-desktop-portal-gtk)$"
      "stayfocused, class:^(xdg-desktop-portal-gtk)$"
      "immediate, class:^(xdg-desktop-portal-gtk)$"

      # Other desktop portal dialogs (KDE, wlroots, etc.)
      "dimaround, class:^(xdg-desktop-portal-kde)$"
      "float, class:^(xdg-desktop-portal-kde)$"
      "pin, class:^(xdg-desktop-portal-kde)$"
      "stayfocused, class:^(xdg-desktop-portal-kde)$"
      "immediate, class:^(xdg-desktop-portal-kde)$"

      "dimaround, class:^(xdg-desktop-portal-wlr)$"
      "float, class:^(xdg-desktop-portal-wlr)$"
      "pin, class:^(xdg-desktop-portal-wlr)$"
      "stayfocused, class:^(xdg-desktop-portal-wlr)$"
      "immediate, class:^(xdg-desktop-portal-wlr)$"

      # Print dialogs
      "dimaround, title:^(Print)$"
      "float, title:^(Print)$"
      "pin, title:^(Print)$"
      "stayfocused, title:^(Print)$"
      "immediate, title:^(Print)$"

      "dimaround, title:^(Print Document)$"
      "float, title:^(Print Document)$"
      "pin, title:^(Print Document)$"
      "stayfocused, title:^(Print Document)$"
      "immediate, title:^(Print Document)$"

      "dimaround, class:^(gtk3-print-backends)$"
      "float, class:^(gtk3-print-backends)$"
      "pin, class:^(gtk3-print-backends)$"
      "stayfocused, class:^(gtk3-print-backends)$"
      "immediate, class:^(gtk3-print-backends)$"

      # Authentication dialogs (polkit, keyring)
      "dimaround, class:^(polkit-gnome-authentication-agent-1)$"
      "float, class:^(polkit-gnome-authentication-agent-1)$"
      "pin, class:^(polkit-gnome-authentication-agent-1)$"
      "stayfocused, class:^(polkit-gnome-authentication-agent-1)$"
      "immediate, class:^(polkit-gnome-authentication-agent-1)$"

      "dimaround, class:^(gnome-keyring-prompt)$"
      "float, class:^(gnome-keyring-prompt)$"
      "pin, class:^(gnome-keyring-prompt)$"
      "stayfocused, class:^(gnome-keyring-prompt)$"
      "immediate, class:^(gnome-keyring-prompt)$"

      # Screenshot/screen capture permission dialogs
      "dimaround, title:^(.*(Screen|Desktop) (Share|Capture|Record)).*$"
      "float, title:^(.*(Screen|Desktop) (Share|Capture|Record)).*$"
      "pin, title:^(.*(Screen|Desktop) (Share|Capture|Record)).*$"
      "stayfocused, title:^(.*(Screen|Desktop) (Share|Capture|Record)).*$"
      "immediate, title:^(.*(Screen|Desktop) (Share|Capture|Record)).*$"

      # Permission dialogs (notifications, microphone, camera, etc.)
      "dimaround, title:^(.*Permission.*)$"
      "float, title:^(.*Permission.*)$"
      "pin, title:^(.*Permission.*)$"
      "stayfocused, title:^(.*Permission.*)$"
      "immediate, title:^(.*Permission.*)$"

      # General system modal dialogs
      "dimaround, title:^(Authentication Required)$"
      "float, title:^(Authentication Required)$"
      "pin, title:^(Authentication Required)$"
      "stayfocused, title:^(Authentication Required)$"
      "immediate, title:^(Authentication Required)$"

      "dimaround, title:^(Confirm)$"
      "float, title:^(Confirm)$"
      "pin, title:^(Confirm)$"
      "stayfocused, title:^(Confirm)$"
      "immediate, title:^(Confirm)$"
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
