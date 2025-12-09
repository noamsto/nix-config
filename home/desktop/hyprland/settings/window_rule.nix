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
        "vicinae"
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
      "ignorealpha 0, vicinae" # Vicinae-specific: more aggressive alpha ignore (per docs)
      "ignorealpha 0.5, ${toRegex (highopacity ++ ["music"])}"
      "ignorealpha 0.2, ${toRegex lowopacity}"
      "noanim, vicinae" # Vicinae-specific: disable fade animations for snappier feel (per docs)
    ];

    # window rules
    windowrulev2 = [
      "suppressevent maximize, class:.*"

      # === VICINAE ===
      "pin, title:^(Vicinae Launcher)$"
      "plugin:hyprbars:nobar, title:^(Vicinae Launcher)$"
      "size 900 700, title:^(Vicinae Launcher)$"

      # telegram media viewer
      "float, title:^(Media viewer)$"

      # gnome calculator
      "float, class:^(org.gnome.Calculator)$"
      "size 360 490, class:^(org.gnome.Calculator)$"

      # === ENHANCED FLOATING WINDOWS ===
      "float, class:^(pavucontrol)$"
      "float, class:^(nm-connection-editor)$"
      "float, class:^(blueman-manager)$"
      "float, class:^(file-roller)$"

      # 1Password
      "float, class:^(1Password|1password|com.1password.1Password)$"
      "center, class:^(1Password|1password|com.1password.1Password)$"
      "immediate, class:^(1Password|1password|com.1password.1Password)$"

      # 1Password Quick Access
      "float, class:^(1Password|1password|com.1password.1Password)$,title:^(Quick Access)$"
      "center, class:^(1Password|1password|com.1password.1Password)$,title:^(Quick Access)$"
      "size 400 500, class:^(1Password|1password|com.1password.1Password)$,title:^(Quick Access)$"

      # 1Password unlock/authentication/lock screen windows
      "float, class:^(1Password|1password|com.1password.1Password)$,title:.*(Password|Lock).*"
      "center, class:^(1Password|1password|com.1password.1Password)$,title:.*(Password|Lock).*"
      "size 900 600, class:^(1Password|1password|com.1password.1Password)$,title:.*(Password|Lock).*"

      # 1Password main window with generic title
      "size 500 600, class:^(1Password|1password|com.1password.1Password)$,title:^(1Password)$"

      # 1Password menus and popups
      "float, class:^(1Password|1password|com.1password.1Password)$,title:^$"
      "immediate, class:^(1Password|1password|com.1password.1Password)$,title:^$"
      "noborder, class:^(1Password|1password|com.1password.1Password)$,title:^$"
      "noshadow, class:^(1Password|1password|com.1password.1Password)$,title:^$"
      "pin, class:^(1Password|1password|com.1password.1Password)$,title:^$"

      # Size dialogs appropriately
      "size 800 600, class:^(pavucontrol)$"
      "size 600 500, class:^(nm-connection-editor)$"
      "size 500 600, class:^(blueman-manager)$"

      # Bluetooth pairing dialogs
      "float, class:^(blueman-agent|blueman-applet)$"
      "center, class:^(blueman-agent|blueman-applet)$"
      "dimaround, class:^(blueman-agent|blueman-applet)$"

      "float, title:^(Bluetooth)$"
      "center, title:^(Bluetooth)$"
      "dimaround, title:^(Bluetooth)$"

      "float, title:^(.*[Bb]luetooth.*(Pairing|Authentication)).*$"
      "center, title:^(.*[Bb]luetooth.*(Pairing|Authentication)).*$"
      "dimaround, title:^(.*[Bb]luetooth.*(Pairing|Authentication)).*$"

      # === PICTURE-IN-PICTURE RULES ===
      # Firefox PiP window
      "float, title:^(Picture-in-Picture)$"
      "pin, title:^(Picture-in-Picture)$"
      "noinitialfocus, title:^(Picture-in-Picture)$"

      # Brave Browser PiP
      "float, class:^(Brave-browser|brave-browser)$,title:^(Picture-in-Picture)$"
      "noinitialfocus, class:^(Brave-browser|brave-browser)$,title:^(Picture-in-Picture)$"
      "size 400 225, class:^(Brave-browser|brave-browser)$,title:^(Picture-in-Picture)$"
      "move 100%-420 100%-245, class:^(Brave-browser|brave-browser)$,title:^(Picture-in-Picture)$"

      # Additional PiP patterns
      "float, class:^(Brave-browser|brave-browser)$,title:^(.*Picture.in.Picture.*)$"
      "noinitialfocus, class:^(Brave-browser|brave-browser)$,title:^(.*Picture.in.Picture.*)$"

      # Google Meet specific
      "float, class:^(Brave-browser|brave-browser)$,title:^(.*meet\.google\.com.*)$"

      "float, class:^(chromium)$,title:^(Picture-in-Picture)$"
      "pin, class:^(chromium)$,title:^(Picture-in-Picture)$"
      "noinitialfocus, class:^(chromium)$,title:^(Picture-in-Picture)$"

      # throw sharing indicators away
      "workspace special silent, title:^(Firefox — Sharing Indicator)$"
      "workspace special silent, title:^(.*is sharing (your screen|a window)\\.)$"
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
      "float, class:^(thunar|Thunar)$,title:^(Progress Dialog)$"
      "float, class:^(thunar|Thunar)$,title:^(Copying)$"
      "float, class:^(thunar|Thunar)$,title:^(File Operation Progress)$"

      # Dragon drop - moves to active workspace, allows focus below
      "float, class:^(dragon|dragon-drop)$"
      "pin, class:^(dragon|dragon-drop)$"
      "noinitialfocus, class:^(dragon|dragon-drop)$"
      "size 400 300, class:^(dragon|dragon-drop)$"

      # === SMART WORKSPACE ASSIGNMENTS ===
      # Note: Use workspace IDs, not names. Named workspaces create dynamic WS with negative IDs.
      # The HDM profiles define names for display only (waybar shows them).

      # Development - workspace 1 (named "dev" in HDM profiles)
      "workspace 1 silent, class:^(kitty)$"

      # Web browsers - workspace 2 (named "web" in HDM profiles)
      # Firefox without silent - clicking links switches to browser workspace
      # Brave/Chromium with silent - only initial placement, no auto-switch
      "workspace 2, class:^(firefox)$"
      "workspace 2 silent, class:^(brave-browser)$, initialTitle:.*"
      "workspace 2 silent, class:^(chromium)$"

      # Communication - workspace 5 (named "comms" in HDM profiles)
      "workspace 5, class:^(slack)$"
      "workspace 5, class:^(Slack)$"
      "workspace 5 silent, class:^(ferdium)$"
      "workspace 5, class:^(zoom)$"

      # Media - workspace 9 (named "media" in HDM profiles)
      "workspace 9 silent, class:^(com.github.th_ch.youtube_music)$"
      "workspace 9 silent, class:^(spotify)$"

      # vlc/mpv - floating (not assigned to media workspace)
      "float, class:^(vlc)$"
      "float, class:^(mpv)$"

      # Zoom
      "float, class:^(zoom)$,title:^(Zoom Meeting)$"
      "idleinhibit focus, class:^(zoom)$"

      # Zoom menu fixes
      "float, class:^(zoom)$,title:^$"
      "pin, class:^(zoom)$,title:^$"
      "noborder, class:^(zoom)$,title:^$"
      "noshadow, class:^(zoom)$,title:^$"
      "minsize 1 1, class:^(zoom)$,title:^$"
      "maxsize 800 600, class:^(zoom)$,title:^$"

      # Zoom general window handling
      "immediate, class:^(zoom)$"

      # Alternative Zoom class names
      "float, class:^(Zoom)$"
      "immediate, class:^(Zoom)$"

      # XWayland-specific fix for Zoom
      "rounding 0, class:^(zoom)$,xwayland:1"

      "dimaround, class:^(gcr-prompter)$"

      # === GENERAL MENU AND POPUP FIXES ===
      # Removed overly broad rules that were pinning all menus with empty titles

      # Fix oversized menu windows
      "maxsize 1200 900, floating:1,title:^$"
      "minsize 1 1, floating:1,title:^$"

      # Common menu patterns
      "stayfocused, title:^(Menu)$"
      "stayfocused, title:^(.*menu.*)$"
      "stayfocused, title:^(.*dropdown.*)$"
      "stayfocused, title:^(.*popup.*)$"

      # === SYSTEM DIALOGS ===
      # File picker dialogs
      "dimaround, class:^(xdg-desktop-portal-gtk)$"
      "float, class:^(xdg-desktop-portal-gtk)$"
      "immediate, class:^(xdg-desktop-portal-gtk)$"

      # Other desktop portal dialogs
      "dimaround, class:^(xdg-desktop-portal-kde)$"
      "float, class:^(xdg-desktop-portal-kde)$"
      "pin, class:^(xdg-desktop-portal-kde)$"
      "immediate, class:^(xdg-desktop-portal-kde)$"

      "dimaround, class:^(xdg-desktop-portal-wlr)$"
      "float, class:^(xdg-desktop-portal-wlr)$"
      "pin, class:^(xdg-desktop-portal-wlr)$"
      "immediate, class:^(xdg-desktop-portal-wlr)$"

      # Print dialogs
      "dimaround, title:^(Print)$"
      "float, title:^(Print)$"
      "pin, title:^(Print)$"
      "immediate, title:^(Print)$"

      "dimaround, title:^(Print Document)$"
      "float, title:^(Print Document)$"
      "pin, title:^(Print Document)$"
      "immediate, title:^(Print Document)$"

      "dimaround, class:^(gtk3-print-backends)$"
      "float, class:^(gtk3-print-backends)$"
      "pin, class:^(gtk3-print-backends)$"
      "immediate, class:^(gtk3-print-backends)$"

      # Authentication dialogs
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
      "immediate, title:^(.*(Screen|Desktop) (Share|Capture|Record)).*$"

      # Screen sharing picker dialog
      "dimaround, title:^(Select what to share)$"
      "float, title:^(Select what to share)$"
      "pin, title:^(Select what to share)$"
      "stayfocused, title:^(Select what to share)$"
      "immediate, title:^(Select what to share)$"

      # Permission dialogs
      "dimaround, title:^(.*Permission.*)$"
      "float, title:^(.*Permission.*)$"
      "pin, title:^(.*Permission.*)$"
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
      "immediate, title:^(Confirm)$"
      "dimaround, class:^(hyprpolkitagent)$"

      # fix xwayland apps
      "rounding 0, xwayland:1"
      "immediate, xwayland:1,floating:1"
      "center, class:^(.*jetbrains.*)$, title:^(Confirm Exit|Open Project|win424|win201|splash)$"
      "size 640 400, class:^(.*jetbrains.*)$, title:^(splash)$"

      # don't render hyprbars on tiling windows
      "plugin:hyprbars:nobar, floating:0"

      # Fullscreen focus mode rules
      "noborder, fullscreen:1"
      "noshadow, fullscreen:1"
      "rounding 0, fullscreen:1"
      "opacity 0.95, fullscreen:1"
      "plugin:hyprbars:nobar, fullscreen:1"

      # Visual indicator for pinned windows - yellow border (catppuccin mocha)
      "bordercolor rgb(f9e2af) rgb(f1fa8c), pinned:1"

      # Override vicinae border to normal blue (must come after pinned rule)
      "bordercolor rgb(89b4fa) rgb(74c7ec), title:^(Vicinae Launcher)$"
    ];
  };
}
