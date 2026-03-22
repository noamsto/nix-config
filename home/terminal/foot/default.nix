{
  config,
  lib,
  ...
}: let
  inherit (config.theme) palette;

  s = color: lib.removePrefix "#" color;

  mkFootTheme = p: ''
    [colors-${p.variant}]
    foreground=${s p.text}
    background=${s p.base}
    cursor=${s p.base} ${s p.rosewater}
    selection-foreground=${s p.text}
    selection-background=${s p.surface1}
    search-box-no-match=${s p.crust} ${s p.red}
    search-box-match=${s p.text} ${s p.surface0}
    jump-labels=${s p.crust} ${s p.peach}
    urls=${s p.blue}

    regular0=${s p.surface1}
    regular1=${s p.red}
    regular2=${s p.green}
    regular3=${s p.yellow}
    regular4=${s p.blue}
    regular5=${s p.pink}
    regular6=${s p.teal}
    regular7=${s p.subtext1}

    bright0=${s p.surface2}
    bright1=${s p.red}
    bright2=${s p.green}
    bright3=${s p.yellow}
    bright4=${s p.blue}
    bright5=${s p.pink}
    bright6=${s p.teal}
    bright7=${s p.subtext0}

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

      colors-dark = {
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

  xdg.configFile = {
    "foot/themes/${palette.dark.name}.ini".text = mkFootTheme palette.dark;
    "foot/themes/${palette.light.name}.ini".text = mkFootTheme palette.light;
  };
}
