{
  pkgs,
  config,
  lib,
  inputs,
  ...
}: let
  # variant = "dark";
  # c = config.programs.matugen.theme.colors.colors.${variant};
  toggle = program: service: let
    prog = builtins.substring 0 14 program;
    runserv = lib.optionalString service "run-as-service";
  in "pkill ${prog} || ${runserv} ${program}";
in {
  # xdg.configFile."hypr/hyprland.conf".source = config.lib.file.mkOutOfStoreSymlink "/home/noams/nix-config/home/hyprland/hyprland.conf";

  imports = [
    inputs.hyprland.homeManagerModules.default
    ./gtk.nix
    ./walker
    ./terminal
    ./services
    ./xdg.nix
    ./pywal
    ./settings
  ];
  wal.enable = false;
  wayland.windowManager.hyprland = {
    enable = true;
    plugins = with inputs.hyprland-plugins.packages.${pkgs.system}; [
      hyprbars
      hyprexpo
    ];

    systemd = {
      variables = ["--all"];
      extraCommands = [
        "systemctl --user stop graphical-session.target"
        "systemctl --user start hyprland-session.target"
      ];
    };
  };

  programs.hyprlock.enable = true;

  home.packages = with pkgs; [
    papirus-icon-theme
    bibata-cursors
    kdePackages.dolphin
    xfce.thunar
  ];

  # make stuff work on wayland
  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    XDG_SESSION_TYPE = "wayland";
  };
}
