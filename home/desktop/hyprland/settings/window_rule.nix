{lib, ...}: {
  wayland.windowManager.hyprland.settings = {
    # layer rules - Hyprland 0.53+ syntax
    layerrule = let
      mkLayerRules = rules: namespaces:
        lib.flatten (map (ns: map (rule: "${rule}, match:namespace ${ns}") rules) namespaces);

      lowopacity = ["bar" "calendar" "notifications" "system-menu"];
      highopacity = ["vicinae" "osd" "logout_dialog"];
      blurred = lib.concatLists [lowopacity highopacity];
      sensitive = ["gnome-keyring-prompt" "polkit" "hyprpolkitagent" "gcr-prompter"];
    in
      (mkLayerRules ["blur on"] blurred)
      ++ (mkLayerRules ["xray on"] ["bar"])
      ++ (mkLayerRules ["ignore_alpha 0"] ["vicinae"])
      ++ (mkLayerRules ["ignore_alpha 0.5"] (highopacity ++ ["music"]))
      ++ (mkLayerRules ["ignore_alpha 0.2"] lowopacity)
      ++ (mkLayerRules ["no_anim on"] ["vicinae"])
      ++ (mkLayerRules ["no_screen_share on"] sensitive);

    # window rules - Hyprland 0.53+ syntax
    # Format: "effect value, match:prop value"
    windowrule = [
      "suppress_event maximize, match:class .*"

      # === VICINAE ===
      "pin on, match:title ^(Vicinae Launcher)$"
      # "hyprbars:no_bar 1, match:title ^(Vicinae Launcher)$" # disabled: hyprbars plugin not loaded
      "size 900 700, match:title ^(Vicinae Launcher)$"

      # telegram media viewer
      "float on, match:title ^(Media viewer)$"

      # gnome calculator
      "float on, match:class ^(org.gnome.Calculator)$"
      "size 360 490, match:class ^(org.gnome.Calculator)$"

      # === ENHANCED FLOATING WINDOWS ===
      "float on, match:class ^(pavucontrol)$"
      "float on, match:class ^(nm-connection-editor)$"
      "float on, match:class ^(blueman-manager)$"
      "float on, match:class ^(file-roller)$"

      # 1Password
      "float on, match:class ^(1Password|1password|com.1password.1Password)$"
      "center on, match:class ^(1Password|1password|com.1password.1Password)$"
      "immediate on, match:class ^(1Password|1password|com.1password.1Password)$"

      # 1Password Quick Access
      "float on, match:class ^(1Password|1password|com.1password.1Password)$, match:title ^(Quick Access)$"
      "center on, match:class ^(1Password|1password|com.1password.1Password)$, match:title ^(Quick Access)$"
      "size 400 500, match:class ^(1Password|1password|com.1password.1Password)$, match:title ^(Quick Access)$"

      # 1Password unlock/authentication/lock screen windows
      "float on, match:class ^(1Password|1password|com.1password.1Password)$, match:title .*(Password|Lock).*"
      "center on, match:class ^(1Password|1password|com.1password.1Password)$, match:title .*(Password|Lock).*"
      "size 900 600, match:class ^(1Password|1password|com.1password.1Password)$, match:title .*(Password|Lock).*"

      # 1Password main window with generic title
      "size 500 600, match:class ^(1Password|1password|com.1password.1Password)$, match:title ^(1Password)$"

      # 1Password menus and popups
      "float on, match:class ^(1Password|1password|com.1password.1Password)$, match:title ^$"
      "immediate on, match:class ^(1Password|1password|com.1password.1Password)$, match:title ^$"
      "decorate off, match:class ^(1Password|1password|com.1password.1Password)$, match:title ^$"
      "no_shadow on, match:class ^(1Password|1password|com.1password.1Password)$, match:title ^$"
      "pin on, match:class ^(1Password|1password|com.1password.1Password)$, match:title ^$"

      # Size dialogs appropriately
      "size 800 600, match:class ^(pavucontrol)$"
      "size 600 500, match:class ^(nm-connection-editor)$"
      "size 500 600, match:class ^(blueman-manager)$"

      # Valent (KDE Connect alternative)
      "float on, match:class ^(ca.andyholmes.Valent)$"
      "center on, match:class ^(ca.andyholmes.Valent)$"
      "size 800 600, match:class ^(ca.andyholmes.Valent)$"

      # Bluetooth pairing dialogs
      "float on, match:class ^(blueman-agent|blueman-applet)$"
      "center on, match:class ^(blueman-agent|blueman-applet)$"
      "dim_around on, match:class ^(blueman-agent|blueman-applet)$"

      "float on, match:title ^(Bluetooth)$"
      "center on, match:title ^(Bluetooth)$"
      "dim_around on, match:title ^(Bluetooth)$"

      "float on, match:title ^(.*[Bb]luetooth.*(Pairing|Authentication)).*$"
      "center on, match:title ^(.*[Bb]luetooth.*(Pairing|Authentication)).*$"
      "dim_around on, match:title ^(.*[Bb]luetooth.*(Pairing|Authentication)).*$"

      # === PICTURE-IN-PICTURE RULES ===
      # Generic PiP (Firefox and others)
      "float on, match:title ^(Picture-in-Picture)$"
      "pin on, match:title ^(Picture-in-Picture)$"
      "no_initial_focus on, match:title ^(Picture-in-Picture)$"

      # Brave Browser PiP
      "float on, match:class ^(Brave-browser|brave-browser)$, match:title ^(Picture-in-Picture)$"
      "no_initial_focus on, match:class ^(Brave-browser|brave-browser)$, match:title ^(Picture-in-Picture)$"
      "size 400 225, match:class ^(Brave-browser|brave-browser)$, match:title ^(Picture-in-Picture)$"
      "move 100%-420 100%-245, match:class ^(Brave-browser|brave-browser)$, match:title ^(Picture-in-Picture)$"

      # Additional PiP patterns
      "float on, match:class ^(Brave-browser|brave-browser)$, match:title ^(.*Picture.in.Picture.*)$"
      "no_initial_focus on, match:class ^(Brave-browser|brave-browser)$, match:title ^(.*Picture.in.Picture.*)$"

      # Google Meet specific
      "float on, match:class ^(Brave-browser|brave-browser)$, match:title ^(.*meet\\.google\\.com.*)$"

      # Chromium PiP
      "float on, match:class ^(chromium)$, match:title ^(Picture-in-Picture)$"
      "pin on, match:class ^(chromium)$, match:title ^(Picture-in-Picture)$"
      "no_initial_focus on, match:class ^(chromium)$, match:title ^(Picture-in-Picture)$"

      # throw sharing indicators away
      "workspace special silent, match:title ^(Firefox — Sharing Indicator)$"
      "workspace special silent, match:title ^(.*is sharing (your screen|a window)\\.)$"
      "workspace special silent, match:title ^(.*Sharing Indicator)$"

      # better screen sharing window handling
      "float on, match:title ^(.*is sharing (your screen|a window).*)$"
      "size 800 600, match:title ^(Volume Control)$"

      # Media players
      "float on, match:class ^(vlc)$"
      "idle_inhibit focus, match:class ^(vlc)$"
      "float on, match:class ^(mpv)$"
      "idle_inhibit focus, match:class ^(mpv|.+exe|celluloid)$"

      # === BROWSER RULES ===
      # Prevent accidental close (2s protection after tab opens)
      "no_close_for 2000, match:class ^(firefox)$"
      "no_close_for 2000, match:class ^(Brave-browser|brave-browser)$"
      "no_close_for 2000, match:class ^(chromium)$"

      # Browser idle inhibit
      "idle_inhibit focus, match:class ^(firefox)$, match:title ^(.*YouTube.*)$"
      "idle_inhibit fullscreen, match:class ^(firefox)$"
      "idle_inhibit focus, match:class ^(Brave-browser)$, match:title ^(.*YouTube.*)$"
      "idle_inhibit fullscreen, match:class ^(Brave-browser)$"
      "idle_inhibit focus, match:class ^(chromium)$, match:title ^(.*YouTube.*)$"
      "idle_inhibit fullscreen, match:class ^(chromium)$"

      # File manager progress dialogs
      "float on, match:class ^(thunar|Thunar)$, match:title ^(Progress Dialog|Copying|File Operation Progress)$"

      # Dragon drop
      "float on, match:class ^(dragon|dragon-drop)$"
      "pin on, match:class ^(dragon|dragon-drop)$"
      "no_initial_focus on, match:class ^(dragon|dragon-drop)$"
      "size 400 300, match:class ^(dragon|dragon-drop)$"

      # === SMART WORKSPACE ASSIGNMENTS ===
      "workspace 1 silent, match:class ^(kitty)$"
      "workspace 2, match:class ^(firefox)$"
      "workspace 2 silent, match:class ^(brave-browser)$, match:initial_title .*"
      "workspace 2 silent, match:class ^(chromium)$"
      "workspace 5, match:class ^(slack|Slack)$"
      "workspace 5 silent, match:class ^(ferdium)$"
      "workspace 5, match:class ^(zoom)$"
      "workspace 9 silent, match:class ^(com.github.th_ch.youtube_music|spotify)$"

      # Zoom
      "float on, match:class ^(zoom|Zoom)$"
      "idle_inhibit focus, match:class ^(zoom)$"
      "immediate on, match:class ^(zoom|Zoom)$"
      "float on, match:class ^(zoom)$, match:title ^(Zoom Meeting)$"

      # Zoom menu fixes
      "float on, match:class ^(zoom)$, match:title ^$"
      "pin on, match:class ^(zoom)$, match:title ^$"
      "decorate off, match:class ^(zoom)$, match:title ^$"
      "no_shadow on, match:class ^(zoom)$, match:title ^$"
      "min_size 1 1, match:class ^(zoom)$, match:title ^$"
      "max_size 800 600, match:class ^(zoom)$, match:title ^$"

      # XWayland-specific fix for Zoom
      "rounding 0, match:class ^(zoom)$, match:xwayland true"

      "dim_around on, match:class ^(gcr-prompter)$"

      # === GENERAL MENU AND POPUP FIXES ===
      "max_size 1200 900, match:float true, match:title ^$"
      "min_size 1 1, match:float true, match:title ^$"

      # Common menu patterns
      "stay_focused on, match:title ^(Menu|.*menu.*|.*dropdown.*|.*popup.*)$"

      # === SYSTEM DIALOGS ===
      # File picker dialogs
      "dim_around on, match:class ^(xdg-desktop-portal-gtk)$"
      "float on, match:class ^(xdg-desktop-portal-gtk)$"
      "immediate on, match:class ^(xdg-desktop-portal-gtk)$"

      "dim_around on, match:class ^(xdg-desktop-portal-kde|xdg-desktop-portal-wlr)$"
      "float on, match:class ^(xdg-desktop-portal-kde|xdg-desktop-portal-wlr)$"
      "pin on, match:class ^(xdg-desktop-portal-kde|xdg-desktop-portal-wlr)$"
      "immediate on, match:class ^(xdg-desktop-portal-kde|xdg-desktop-portal-wlr)$"

      # Print dialogs
      "dim_around on, match:title ^(Print|Print Document)$"
      "float on, match:title ^(Print|Print Document)$"
      "pin on, match:title ^(Print|Print Document)$"
      "immediate on, match:title ^(Print|Print Document)$"

      "dim_around on, match:class ^(gtk3-print-backends)$"
      "float on, match:class ^(gtk3-print-backends)$"
      "pin on, match:class ^(gtk3-print-backends)$"
      "immediate on, match:class ^(gtk3-print-backends)$"

      # Authentication dialogs
      "dim_around on, match:class ^(polkit-gnome-authentication-agent-1|gnome-keyring-prompt|hyprpolkitagent)$"
      "float on, match:class ^(polkit-gnome-authentication-agent-1|gnome-keyring-prompt|hyprpolkitagent)$"
      "pin on, match:class ^(polkit-gnome-authentication-agent-1|gnome-keyring-prompt|hyprpolkitagent)$"
      "stay_focused on, match:class ^(polkit-gnome-authentication-agent-1|gnome-keyring-prompt|hyprpolkitagent)$"
      "immediate on, match:class ^(polkit-gnome-authentication-agent-1|gnome-keyring-prompt|hyprpolkitagent)$"

      # Screenshot/screen capture permission dialogs
      "dim_around on, match:title ^(.*(Screen|Desktop) (Share|Capture|Record)).*$"
      "float on, match:title ^(.*(Screen|Desktop) (Share|Capture|Record)).*$"
      "pin on, match:title ^(.*(Screen|Desktop) (Share|Capture|Record)).*$"
      "immediate on, match:title ^(.*(Screen|Desktop) (Share|Capture|Record)).*$"

      # Screen sharing picker dialog
      "dim_around on, match:title ^(Select what to share)$"
      "float on, match:title ^(Select what to share)$"
      "pin on, match:title ^(Select what to share)$"
      "stay_focused on, match:title ^(Select what to share)$"
      "immediate on, match:title ^(Select what to share)$"

      # Permission dialogs
      "dim_around on, match:title ^(.*Permission.*)$"
      "float on, match:title ^(.*Permission.*)$"
      "pin on, match:title ^(.*Permission.*)$"
      "immediate on, match:title ^(.*Permission.*)$"

      # General system modal dialogs
      "dim_around on, match:title ^(Authentication Required)$"
      "float on, match:title ^(Authentication Required)$"
      "pin on, match:title ^(Authentication Required)$"
      "stay_focused on, match:title ^(Authentication Required)$"
      "immediate on, match:title ^(Authentication Required)$"

      "dim_around on, match:title ^(Confirm)$"
      "float on, match:title ^(Confirm)$"
      "pin on, match:title ^(Confirm)$"
      "immediate on, match:title ^(Confirm)$"

      # fix xwayland apps
      "rounding 0, match:xwayland true"
      "immediate on, match:xwayland true, match:float true"
      "center on, match:class ^(.*jetbrains.*)$, match:title ^(Confirm Exit|Open Project|win424|win201|splash)$"
      "size 640 400, match:class ^(.*jetbrains.*)$, match:title ^(splash)$"

      # hyprbars rules - disabled: hyprbars plugin not loaded
      # "hyprbars:no_bar 1, match:fullscreen false"
      # "hyprbars:no_bar 1, match:fullscreen true"
      # "hyprbars:no_bar 1, match:float false"
      # "hyprbars:no_bar 0, match:float true"

      # Fullscreen focus mode rules
      "decorate off, match:fullscreen true"
      "no_shadow on, match:fullscreen true"
      "rounding 0, match:fullscreen true"
      "opacity 0.95, match:fullscreen true"

      # Visual indicator for pinned windows - yellow border (catppuccin mocha)
      "border_color rgb(f9e2af) rgb(f1fa8c), match:pin true"

      # Override vicinae border to normal blue (must come after pinned rule)
      "border_color rgb(89b4fa) rgb(74c7ec), match:title ^(Vicinae Launcher)$"
    ];
  };
}
