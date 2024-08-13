{
  pkgs,
  config,
  lib,
  ...
}: let
  # variant = "dark";
  # c = config.programs.matugen.theme.colors.colors.${variant};
  terminal = "alacritty";
  fileManager = "thunar";
  browser = "firefox";
  pointer = config.home.pointerCursor;
  cursorName = "Bibata-Modern-Ice";

  toggle = program: service: let
    prog = builtins.substring 0 14 program;
    runserv = lib.optionalString service "run-as-service";
  in "pkill ${prog} || ${runserv} ${program}";
in {
  # xdg.configFile."hypr/hyprland.conf".source = config.lib.file.mkOutOfStoreSymlink "/home/noams/nix-config/home/hyprland/hyprland.conf";
  imports = [
    ./gtk.nix
    ./anyrun
    ./terminal
  ];
  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      monitor = [
        # "eDP-1,1920x1080,0x0,1.3"
        "desc:Samsung Electric Company S27H85x H4ZM300138,2560x1440,0x0,1" # Left External Monitor
        "desc:Samsung Electric Company S27H85x H4ZKB00167,2560x1440, 2560x0,1" # Right External Monitor Home
        "desc:Samsung Display Corp. 0x4193,2880x1800, 3000x1440,1" # Laptop Monitor
        ",preferred,auto,auto"
      ];

      env = [
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
        "HYPRCURSOR_THEME,${cursorName}"
        "HYPRCURSOR_SIZE,${toString pointer.size}"
      ];

      exec-once = [
        # set cursor for HL itself
        "hyprctl setcursor ${cursorName} ${toString pointer.size}"
        "hyprlock"

        # Tmux wayland integration
        "tmux setenv -g HYPRLAND_INSTANCE_SIGNATURE \"$HYPRLAND_INSTANCE_SIGNATURE\""
        "tmux setenv -g WAYLAND_DISPLAY \"$WAYLAND_DISPLAY\""
        "tmux setenv -g XDG_RUNTIME_DIR \"$XDG_RUNTIME_DIR\""
      ];

      "$mainMod" = "SUPER";
      bind = [
        "$mainMod, Q, exec, ${terminal}"
        "$mainMod, E, exec, ${fileManager}"
        "$mainMod, F, exec, ${browser}"
        "$mainMod, C, killactive"
        "$mainMod, M, exit"

        # Move focus with SUPER+hjkl
        "$mainMod, H, movefocus, l"
        "$mainMod, L, movefocus, r"
        "$mainMod, K, movefocus, u"
        "$mainMod, J, movefocus, d"
      ];

      bindr = [
        # launcher
        "$mainMod, SUPER_L, exec, ${toggle "anyrun" true}"
      ];
    };

    # plugins = with inputs.hyprland-plugins.packages.${pkgs.system}; [
    #   hyprbars
    #   hyprexpo
    # ];

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
