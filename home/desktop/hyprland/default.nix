{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.hyprland.homeManagerModules.default

    ./gtk.nix
    ./walker
    ./terminal
    ./services
    ./media
    ./utils
    ./settings
    ./waybar
    ./swaync.nix
    ./scripts/screenshot-utils.nix
    ./scripts/brightness-control.nix
    ./scripts/keyboard-layout.nix
    ./smart-dnd.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    plugins = with inputs.hyprland-plugins.packages.${pkgs.system}; [
      hyprbars
      hyprexpo
    ];
    systemd.enable = false;
  };

  home.packages = with pkgs; [
    papirus-icon-theme
    bibata-cursors
    kdePackages.dolphin

    # Screenshot and recording tools
    grimblast
    wl-screenrec
    slurp # Area selection for screenshots/recording
    ffmpeg # Video/GIF conversion
    wl-clipboard
    jq # JSON parsing for smart selection
  ];

  # make stuff work on wayland
  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    XDG_SESSION_TYPE = "wayland";
  };
}
