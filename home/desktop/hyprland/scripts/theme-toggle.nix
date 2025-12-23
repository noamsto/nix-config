{
  pkgs,
  config,
  ...
}: let
  # Fetch catppuccin-lazygit themes
  catppuccin-lazygit = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "lazygit";
    rev = "v2.0.0";
    sha256 = "sha256-gM0HplHhcpvtpmIVdlX/p59h0v+ihKEidS1imqPYlBg=";
  };

  # Fetch catppuccin-yazi themes
  catppuccin-yazi = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "yazi";
    rev = "043ffae14e7f7fcc136636d5f2c617b5bc2f5e31";
    sha256 = "sha256-zkL46h1+U9ThD4xXkv1uuddrlQviEQD3wNZFRgv7M8Y=";
  };

  # Theme source directories - injected into script as env vars
  kittyThemesPath = "${pkgs.kitty-themes}/share/kitty-themes/themes";
  lazygitThemesPath = "${catppuccin-lazygit}/themes";
  yaziThemesPath = "${catppuccin-yazi}/themes";
  nixConfigDir = "${config.home.homeDirectory}/nix-config";

  # Source theme files (read-only templates)
  waybarThemesDir = "${nixConfigDir}/home/desktop/hyprland/waybar";
  swayNcThemesDir = "${nixConfigDir}/home/desktop/hyprland/swaync";
  processComposeThemesDir = "${nixConfigDir}/home/terminal/process_compose";

  # Target directories for generated files (mutable runtime state)
  xdgConfigHome = "${config.xdg.configHome}";

  theme-toggle = pkgs.writeShellApplication {
    name = "theme-toggle";
    runtimeInputs = with pkgs; [
      dconf # dconf write for GTK settings
      libnotify # notify-send
      hyprland # hyprctl
      swaynotificationcenter # swaync-client
      procps # pkill, pgrep
      kitty # kitty @ remote control
      tmux # tmux set/run-shell
      coreutils # cp, nohup, date
      networkmanagerapplet # nm-applet
      blueman # blueman-applet
      libsForQt5.qtstyleplugin-kvantum # kvantummanager
      jq # JSON state file handling
      fish # fish theme reload
    ];
    text = ''
      # Theme source paths (read-only)
      export KITTY_THEMES_PATH="${kittyThemesPath}"
      export LAZYGIT_THEMES_PATH="${lazygitThemesPath}"
      export YAZI_THEMES_PATH="${yaziThemesPath}"
      export WAYBAR_THEMES_DIR="${waybarThemesDir}"
      export SWAYNC_THEMES_DIR="${swayNcThemesDir}"
      export PROCESS_COMPOSE_THEMES_DIR="${processComposeThemesDir}"

      # Target config directories (mutable)
      export XDG_CONFIG_HOME="${xdgConfigHome}"

      ${builtins.readFile ./sh/theme-toggle.sh}
    '';
  };
in {
  home.packages = [theme-toggle];
}
