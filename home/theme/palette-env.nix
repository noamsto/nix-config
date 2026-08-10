# Reusable palette → shell-env-var injection, shared by the Linux theme-toggle
# wrapper and the macOS theme-apply-macos driver. Pure data — no platform deps.
{
  pkgs,
  config,
  lib,
}: let
  inherit (config.theme.palette) dark light;
  stripHash = color: lib.removePrefix "#" color;

  catppuccin-lazygit = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "lazygit";
    rev = "v2.0.0";
    sha256 = "sha256-gM0HplHhcpvtpmIVdlX/p59h0v+ihKEidS1imqPYlBg=";
  };
  catppuccin-yazi = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "yazi";
    rev = "fc69d6472d29b823c4980d23186c9c120a0ad32c";
    sha256 = "sha256-Og33IGS9pTim6LEH33CO102wpGnPomiperFbqfgrJjw=";
  };
in {
  # Core runtime tools every platform's updaters need. kitty is deliberately
  # excluded: Linux uses nixpkgs kitty, darwin uses the Homebrew cask (its TCC
  # grants survive version bumps — see home/terminal/kitty/default.nix), so
  # each platform's own wrapper contributes its own kitty client instead.
  coreRuntimeInputs = with pkgs; [
    coreutils
    gnugrep
    gnused
    gawk
    findutils
    jq
    tmux
    fish
  ];

  # Shell snippet exporting palette colors + theme paths. Prepend to the script
  # text before sourcing theme-apply.sh.
  exports = ''
    export LAZYGIT_THEMES_PATH="${catppuccin-lazygit}/themes"
    export YAZI_THEMES_PATH="${catppuccin-yazi}/themes"
    export XDG_CONFIG_HOME="${config.xdg.configHome}"
    export DARK_THEME_NAME="${dark.name}"
    export LIGHT_THEME_NAME="${light.name}"

    # Dark palette
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

    # Light palette
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

    # Without # prefix (rgba usage)
    export DARK_BLUE_RAW="${stripHash dark.blue}"
    export DARK_LAVENDER_RAW="${stripHash dark.lavender}"
    export LIGHT_BLUE_RAW="${stripHash light.blue}"
    export LIGHT_LAVENDER_RAW="${stripHash light.lavender}"
  '';

  libScript = ./lib/theme-apply.sh;
}
