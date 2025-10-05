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
    copy-command = "wl-copy"
    annotation-size-factor = 2
    output-filename = "${config.xdg.userDirs.pictures}/Screenshots/satty-%Y-%m-%d_%H-%M-%S.png"

    [font]
    family = "Roboto"
  '';
}
