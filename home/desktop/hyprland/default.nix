{
  pkgs,
  config,
  lib,
  osConfig,
  ...
}: {
  imports = [
    ./gtk.nix
    ./vicinae
    ./terminal
    ./services
    ./media
    ./utils
    ./settings
    ./scripts/screenshot-utils.nix
    ./scripts/brightness-control.nix
    ./scripts/keyboard-layout.nix
    ./scripts/volume-control.nix
    ./scripts/sounds.nix
    ./scripts/window-resize.nix
    ./scripts/sesh-launcher.nix
    ./scripts/theme-toggle.nix
    ./scripts/recording-post-processor.nix
    ./scripts/accessibility-tools.nix
    ./scripts/system-awake.nix
    ./scripts/system-awake-thermal-guard.nix
    ./scripts/aegis-lock-recover.nix
    ./smart-dnd.nix
    ./xresources.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    systemd.enable = false;
  };

  home = {
    packages = with pkgs; [
      papirus-icon-theme
      bibata-cursors
      thunar
      thunar-volman # Volume manager for thunar
      thunar-archive-plugin # Archive support
      tumbler # Thumbnail service for image previews
      xfconf # Provides xfconfd D-Bus service so Thunar settings persist

      # XWayland HiDPI support
      xrdb # X resources database for XWayland scaling

      # Screenshot and recording tools
      grim # High-quality Wayland screenshot tool
      grimblast # Backup screenshot tool
      satty # Screenshot editor (modern alternative to swappy)
      wl-screenrec
      slurp # Area selection for screenshots/recording
      ffmpeg # Video/GIF conversion
      wl-clipboard
      jq # JSON parsing for smart selection
      hyprpicker # Required for grimblast --freeze functionality

      # Notification support
      libnotify # For notify-send in scripts

      # Sound theme support
      sound-theme-freedesktop # Provides standard system sounds
      libcanberra # Sound theme support library

      # Image editing and viewing
      gimp # Full-featured image editor
      eog # GNOME image viewer
    ];

    # make stuff work on wayland
    sessionVariables = {
      QT_QPA_PLATFORM = "wayland";
      SDL_VIDEODRIVER = "wayland";
      XDG_SESSION_TYPE = "wayland";
      GRIMBLAST_EDITOR = "satty";
    };

    # Satty configuration for high-quality screenshot editing
    file.".config/satty/config.toml".text = ''
      [general]
      early-exit = true
      copy-command = "satty-copy-path"
      annotation-size-factor = 2
      output-filename = "${config.xdg.userDirs.pictures}/Screenshots/satty-%Y-%m-%d_%H-%M-%S.png"
      disable-notifications = true

      [font]
      family = "Roboto"
    '';
  };

  # Per-profile launchers (right-click "Open with…" or app menus).
  # Workspace-follow is handled by Hyprland's misc.focus_on_activate via
  # the xdg-activation protocol, not a wrapper script.
  xdg.desktopEntries = {
    firefox-personal = {
      name = "Firefox (Personal)";
      genericName = "Web Browser";
      exec = "${lib.getExe pkgs.firefox} -P personal %U";
      icon = "firefox";
      terminal = false;
      mimeType = ["x-scheme-handler/http" "x-scheme-handler/https" "text/html"];
      categories = ["Network" "WebBrowser"];
    };

    # Automation profile with Marionette active for the firefox-devtools MCP.
    # No mimeType: it's a launcher entry, not a default-browser handler.
    firefox-marionette = {
      name = "Firefox (Marionette)";
      genericName = "Web Browser";
      exec = "${lib.getExe pkgs.firefox} -P automation --marionette --remote-debugging-port=9222 %U";
      icon = "firefox";
      terminal = false;
      categories = ["Network" "WebBrowser"];
    };
  };

  # Thunar settings — written to xfconf at HM activation.
  # Thunar 4.20 reads its preferences from xfconf (channel "thunar").
  # The legacy thunarrc seed only runs on first launch, so we configure
  # xfconf directly to make settings deterministic across rebuilds.
  xfconf.settings.thunar = {
    "last-view" = "ThunarDetailsView";
    "last-sort-column" = "THUNAR_COLUMN_DATE_MODIFIED";
    "last-sort-order" = "GTK_SORT_DESCENDING";
    "last-show-hidden" = false;
    "misc-thumbnail-mode" = "THUNAR_THUMBNAIL_MODE_ALWAYS";
    "misc-folders-first" = true;
    "misc-date-style" = "THUNAR_DATE_STYLE_SHORT";
    "misc-date-custom-style" = "%Y-%m-%d %H:%M";
    "misc-file-size-binary" = false;
    "misc-single-click" = false;
  };

  # xdg-terminal-exec (installed by the foot module) cds into --dir itself,
  # since foot.desktop has no X-TerminalArgDir. Called by name, not store path:
  # the long-lived Thunar daemon would keep a path that GC can remove.
  xdg.configFile."Thunar/uca.xml".text = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <actions>
    <action>
    	<icon>utilities-terminal</icon>
    	<name>Open Terminal Here</name>
    	<submenu></submenu>
    	<unique-id>1727610268729651-1</unique-id>
    	<command>xdg-terminal-exec --dir=%f</command>
    	<description>Open the default terminal in this folder</description>
    	<range></range>
    	<patterns>*</patterns>
    	<startup-notify/>
    	<directories/>
    </action>
    </actions>
  '';

  # Sidebar bookmarks (shows in Thunar and other GTK file dialogs).
  # Data bookmarks only on hosts that mount /home/$USER/Data.
  gtk.gtk3.bookmarks = let
    home = config.home.homeDirectory;
    hasDataMount = osConfig.nix-config.desktop.dataMount;
  in
    [
      "file://${home}/Documents"
      "file://${home}/Downloads"
      "file://${home}/Pictures"
      "file://${home}/Videos"
      "file://${home}/git git"
    ]
    ++ lib.optionals hasDataMount [
      "file://${home}/Data Data"
    ];
}
