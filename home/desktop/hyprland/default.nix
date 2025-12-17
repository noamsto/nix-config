{
  pkgs,
  config,
  ...
}: {
  imports = [
    ./gtk.nix
    ./walker
    ./vicinae
    ./terminal
    ./services
    ./media
    ./utils
    ./settings
    ./waybar
    ./swaync
    ./nwg-dock
    ./scripts/screenshot-utils.nix
    ./scripts/brightness-control.nix
    ./scripts/keyboard-layout.nix
    ./scripts/volume-control.nix
    ./scripts/sounds.nix
    ./scripts/window-resize.nix
    ./scripts/sesh-launcher.nix
    ./scripts/theme-toggle.nix
    ./smart-dnd.nix
    ./xresources.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    plugins = with pkgs.hyprlandPlugins; [
      hyprbars
      hyprexpo
    ];
    systemd.enable = false;
  };

  home.packages = with pkgs; [
    papirus-icon-theme
    bibata-cursors
    xfce.thunar
    xfce.thunar-volman # Volume manager for thunar
    xfce.thunar-archive-plugin # Archive support
    xfce.tumbler # Thumbnail service for image previews

    # Dock
    nwg-dock-hyprland # Dock for Hyprland

    # XWayland HiDPI support
    xorg.xrdb # X resources database for XWayland scaling

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
  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    XDG_SESSION_TYPE = "wayland";
    GRIMBLAST_EDITOR = "satty";
  };

  # Satty configuration for high-quality screenshot editing
  home.file.".config/satty/config.toml".text = ''
    [general]
    early-exit = true
    copy-command = "satty-copy-path"
    annotation-size-factor = 2
    output-filename = "${config.xdg.userDirs.pictures}/Screenshots/satty-%Y-%m-%d_%H-%M-%S.png"
    disable-notifications = true

    [font]
    family = "Roboto"
  '';

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

  # Thunar settings - xfconf requires xfconfd running, so use config file
  # These are set when Thunar first runs. User can change in preferences.
  xdg.configFile."Thunar/thunarrc".text = ''
    [Configuration]
    LastView=ThunarDetailsView
    MiscThumbnailMode=THUNAR_THUMBNAIL_MODE_ALWAYS
    MiscShowHidden=FALSE
    MiscFoldersFirst=TRUE
    MiscDateStyle=THUNAR_DATE_STYLE_SHORT
  '';
}
