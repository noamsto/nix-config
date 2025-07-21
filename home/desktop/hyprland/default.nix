{
  pkgs,
  lib,
  inputs,
  config,
  ...
}: let
  # variant = "dark";
  toggle = program: service: let
    prog = builtins.substring 0 14 program;
    runserv = lib.optionalString service "run-as-service";
  in "pkill ${prog} || ${runserv} ${program}";
in {
  imports = [
    inputs.hyprland.homeManagerModules.default

    ./gtk.nix
    ./walker
    ./terminal
    ./services
    # ./xdg.nix
    ./utils
    ./settings
    # ./quickshell  # Disabled in favor of waybar
    ./waybar
    ./dunst.nix
    ./scripts/screenshot-utils.nix
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
    playerctl
    papirus-icon-theme
    bibata-cursors
    kdePackages.dolphin
    xfce.thunar

    # Screenshot and recording tools (grimblast already included above)
    wl-screenrec
    wl-clipboard
    cliphist
  ];

  # make stuff work on wayland
  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    XDG_SESSION_TYPE = "wayland";
  };
}
