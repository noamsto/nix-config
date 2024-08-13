{
  pkgs,
  config,
  ...
}: let
  # variant = "dark";
  # c = config.programs.matugen.theme.colors.colors.${variant};
  terminal = "alacritty";
  fileManager = "thunar";
  browser = "firefox";
  pointer = config.home.pointerCursor;
  cursorName = "Bibata-Modern-Ice";
in {
  # xdg.configFile."hypr/hyprland.conf".source = config.lib.file.mkOutOfStoreSymlink "/home/noams/nix-config/home/hyprland/hyprland.conf";
  imports = [
    ./gtk.nix
  ];
  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      monitor = [
        # "eDP-1,1920x1080,0x0,1.3"
        "desc:Samsung Electric Company S27H85x H4ZM300138,2560x1440,-2860x1080,1" # Left External Monitor
        "desc:Samsung Electric Company S27H85x H4ZKB00167,2560x1440,-360x1080,1" # Right External Monitor Home
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
      ];

      "$mainMod" = "SUPER";
      bind = [
        "$mainMod, Q, exec, ${terminal}"
        "$mainMod, E, exec, ${fileManager}"
        "$mainMod, F, exec, ${browser}"
        "$mainMod, C, killactive"
        "$mainMod, M, exit"
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
}
