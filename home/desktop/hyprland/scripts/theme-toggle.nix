{
  pkgs,
  config,
  lib,
  ...
}: let
  # Theme palette from config
  inherit (config.theme.palette) dark light;

  # Strip # from hex colors for use in rgba() and other formats
  stripHash = color: lib.removePrefix "#" color;

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
    rev = "fc69d6472d29b823c4980d23186c9c120a0ad32c";
    sha256 = "sha256-Og33IGS9pTim6LEH33CO102wpGnPomiperFbqfgrJjw=";
  };

  # Theme source directories - injected into script as env vars
  # These are Nix store paths for external theme packages (apps we don't generate themes for)
  lazygitThemesPath = "${catppuccin-lazygit}/themes";
  yaziThemesPath = "${catppuccin-yazi}/themes";

  # Absolute icon paths for notify-send. We pass paths instead of names because
  # noctalia (Qt/quickshell) has no qt5ct/XDG_ICON_THEME hint, so its icon-by-name
  # lookup falls back to a default theme that doesn't ship `weather-clear`.
  notifyIconLight = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Light/48x48/status/weather-clear.svg";
  notifyIconDark = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark/48x48/status/weather-clear-night.svg";

  # XDG config home for generated theme files
  xdgConfigHome = "${config.xdg.configHome}";

  theme-toggle = pkgs.writeShellApplication {
    name = "theme-toggle";
    runtimeInputs = with pkgs; [
      dconf # dconf write for GTK settings
      libnotify # notify-send
      hyprland # hyprctl
      procps # pkill, pgrep
      kitty # kitty @ remote control (kept alongside ghostty)
      tmux # tmux set/run-shell
      coreutils # cp, nohup, date, sort, tr
      gnugrep # grep
      gnused # sed
      gawk # awk for tmux theme variable parsing
      findutils # find for foot theme discovery
      networkmanagerapplet # nm-applet
      libsForQt5.qtstyleplugin-kvantum # kvantummanager
      jq # JSON state file handling
      fish # fish theme reload
      quickshell # qs for Noctalia IPC
    ];
    text = ''
      # Theme source paths (Nix store, read-only) - for apps we don't generate themes for
      export LAZYGIT_THEMES_PATH="${lazygitThemesPath}"
      export YAZI_THEMES_PATH="${yaziThemesPath}"

      # Absolute icon paths for notify-send (Qt-based notification daemon)
      export NOTIFY_ICON_LIGHT="${notifyIconLight}"
      export NOTIFY_ICON_DARK="${notifyIconDark}"

      # XDG config home (where Nix generates theme files from palette)
      export XDG_CONFIG_HOME="${xdgConfigHome}"

      # Theme identifiers (for file names and config values)
      export DARK_THEME_NAME="${dark.name}"
      export LIGHT_THEME_NAME="${light.name}"

      # Theme palette - Dark (${dark.name})
      export DARK_BASE="${dark.base}"
      export DARK_MANTLE="${dark.mantle}"
      export DARK_CRUST="${dark.crust}"
      export DARK_TEXT="${dark.text}"
      export DARK_SUBTEXT0="${dark.subtext0}"
      export DARK_SUBTEXT1="${dark.subtext1}"
      export DARK_SURFACE0="${dark.surface0}"
      export DARK_SURFACE1="${dark.surface1}"
      export DARK_SURFACE2="${dark.surface2}"
      export DARK_OVERLAY0="${dark.overlay0}"
      export DARK_OVERLAY1="${dark.overlay1}"
      export DARK_OVERLAY2="${dark.overlay2}"
      export DARK_BLUE="${dark.blue}"
      export DARK_LAVENDER="${dark.lavender}"
      export DARK_SAPPHIRE="${dark.sapphire}"
      export DARK_SKY="${dark.sky}"
      export DARK_TEAL="${dark.teal}"
      export DARK_GREEN="${dark.green}"
      export DARK_YELLOW="${dark.yellow}"
      export DARK_PEACH="${dark.peach}"
      export DARK_MAROON="${dark.maroon}"
      export DARK_RED="${dark.red}"
      export DARK_MAUVE="${dark.mauve}"
      export DARK_PINK="${dark.pink}"
      export DARK_FLAMINGO="${dark.flamingo}"
      export DARK_ROSEWATER="${dark.rosewater}"

      # Theme palette - Light (${light.name})
      export LIGHT_BASE="${light.base}"
      export LIGHT_MANTLE="${light.mantle}"
      export LIGHT_CRUST="${light.crust}"
      export LIGHT_TEXT="${light.text}"
      export LIGHT_SUBTEXT0="${light.subtext0}"
      export LIGHT_SUBTEXT1="${light.subtext1}"
      export LIGHT_SURFACE0="${light.surface0}"
      export LIGHT_SURFACE1="${light.surface1}"
      export LIGHT_SURFACE2="${light.surface2}"
      export LIGHT_OVERLAY0="${light.overlay0}"
      export LIGHT_OVERLAY1="${light.overlay1}"
      export LIGHT_OVERLAY2="${light.overlay2}"
      export LIGHT_BLUE="${light.blue}"
      export LIGHT_LAVENDER="${light.lavender}"
      export LIGHT_SAPPHIRE="${light.sapphire}"
      export LIGHT_SKY="${light.sky}"
      export LIGHT_TEAL="${light.teal}"
      export LIGHT_GREEN="${light.green}"
      export LIGHT_YELLOW="${light.yellow}"
      export LIGHT_PEACH="${light.peach}"
      export LIGHT_MAROON="${light.maroon}"
      export LIGHT_RED="${light.red}"
      export LIGHT_MAUVE="${light.mauve}"
      export LIGHT_PINK="${light.pink}"
      export LIGHT_FLAMINGO="${light.flamingo}"
      export LIGHT_ROSEWATER="${light.rosewater}"

      # Colors without # prefix (for rgba() usage)
      export DARK_BLUE_RAW="${stripHash dark.blue}"
      export DARK_LAVENDER_RAW="${stripHash dark.lavender}"
      export LIGHT_BLUE_RAW="${stripHash light.blue}"
      export LIGHT_LAVENDER_RAW="${stripHash light.lavender}"

      ${builtins.readFile ./sh/theme-toggle.sh}
    '';
  };
in {
  options.programs.theme-toggle = {
    package = lib.mkOption {
      type = lib.types.package;
      default = theme-toggle;
      description = "The theme-toggle package";
      readOnly = true;
    };
  };

  config.home.packages = [theme-toggle];
}
