{
  config,
  lib,
  ...
}: let
  inherit (config.theme) palette;

  # Strip # from hex colors for foot format
  s = color: lib.removePrefix "#" color;

  # Generate foot theme from palette
  # Foot uses lowercase hex without # prefix
  mkFootTheme = p: ''
    [colors]
    foreground=${s p.text}
    background=${s p.base}

    # Cursor: background foreground
    cursor=${s p.base} ${s p.rosewater}

    # Selection
    selection-foreground=${s p.text}
    selection-background=${s p.surface1}

    # Search
    search-box-no-match=${s p.crust} ${s p.red}
    search-box-match=${s p.text} ${s p.surface0}

    # Jump labels and URLs
    jump-labels=${s p.crust} ${s p.peach}
    urls=${s p.blue}

    # Regular colors (0-7)
    regular0=${s p.surface1}
    regular1=${s p.red}
    regular2=${s p.green}
    regular3=${s p.yellow}
    regular4=${s p.blue}
    regular5=${s p.pink}
    regular6=${s p.teal}
    regular7=${s p.subtext1}

    # Bright colors (8-15)
    bright0=${s p.surface2}
    bright1=${s p.red}
    bright2=${s p.green}
    bright3=${s p.yellow}
    bright4=${s p.blue}
    bright5=${s p.pink}
    bright6=${s p.teal}
    bright7=${s p.subtext0}

    # Extended colors (16-17 for 256-color support)
    16=${s p.peach}
    17=${s p.rosewater}
  '';
in {
  programs.foot = {
    enable = true;
    settings = {
      main = {
        font = "Fira Code Nerd Font:size=11, Noto Color Emoji:size=11";
        dpi-aware = "yes";
      };

      colors = {
        alpha = "0.9";
      };

      text-bindings = {
        "\\x1b[72;6u" = "Control+Shift+h";
        "\\x1b[74;6u" = "Control+Shift+j";
        "\\x1b[75;6u" = "Control+Shift+k";
        "\\x1b[76;6u" = "Control+Shift+l";

        "\\x1b[105;5u" = "Control+i";

        "\\x1b[46;5u" = "Control+period";
        "\\x1b[44;5u" = "Control+comma";
        "\\x1b[59;5u" = "Control+semicolon";

        "\\x1b[13;2u" = "Shift+Return";
      };

      mouse = {
        hide-when-typing = "yes";
      };
    };
  };

  # Generated foot theme files (used by theme-toggle)
  xdg.configFile = {
    "foot/themes/${palette.dark.name}.ini".text = mkFootTheme palette.dark;
    "foot/themes/${palette.light.name}.ini".text = mkFootTheme palette.light;
  };
}
