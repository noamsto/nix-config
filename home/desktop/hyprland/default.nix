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
    # Replaced by Noctalia Shell:
    # ./waybar
    # ./swaync
    # ./nwg-dock
    ./scripts/screenshot-utils.nix
    ./scripts/brightness-control.nix
    ./scripts/keyboard-layout.nix
    ./scripts/volume-control.nix
    ./scripts/sounds.nix
    ./scripts/window-resize.nix
    ./scripts/toggle-floating.nix
    ./scripts/sesh-launcher.nix
    ./scripts/theme-toggle.nix
    ./scripts/recording-post-processor.nix
    ./scripts/accessibility-tools.nix
    ./scripts/system-awake.nix
    ./scripts/system-awake-thermal-guard.nix
    ./smart-dnd.nix
    ./xresources.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    # plugins = with pkgs.hyprlandPlugins; [
    #   hyprbars
    #   hyprexpo
    # ];
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

      # Dock - now handled by Noctalia
      # nwg-dock-hyprland

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

  # Custom desktop entry for browser URL handler with workspace switching
  xdg.dataFile."applications/firefox-workspace-switch.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Firefox (Workspace Switcher)
    Exec=${pkgs.bash}/bin/bash ${./scripts/open-browser.sh} %u
    Icon=firefox
    Terminal=false
    MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;application/xhtml+xml;
    Categories=Network;WebBrowser;
    StartupNotify=true
  '';

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

  # Sidebar bookmarks (shows in Thunar and other GTK file dialogs).
  # Data bookmarks only on hosts that mount /home/$USER/Data.
  gtk.gtk3.bookmarks = let
    home = config.home.homeDirectory;
    hasDataMount = builtins.elem osConfig.hostname ["thinkpad-p14s" "thinkpad-p14s-g5"];
  in
    [
      "file://${home}/Documents"
      "file://${home}/Downloads"
      "file://${home}/Pictures"
      "file://${home}/Videos"
    ]
    ++ lib.optionals hasDataMount [
      "file://${home}/Data Data"
      "file://${home}/Data/git git"
    ];
}
