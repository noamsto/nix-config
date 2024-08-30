{
  pkgs,
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
    # ./xdg.nix
    ./pywal
    ./settings
    ./matugen.nix
    ./utils
  ];

  # Theme related
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

  home.packages = with pkgs; [
    playerctl
    papirus-icon-theme
    bibata-cursors
    # (callPackage ./bibata-hyprcursor {})
    kdePackages.dolphin
    xfce.thunar

    inputs.hyprland-contrib.packages.${pkgs.system}.grimblast
  ];

  # make stuff work on wayland
  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland";
    SDL_VIDEODRIVER = "wayland";
    XDG_SESSION_TYPE = "wayland";
  };
}
