{
  pkgs,
  config,
  ...
}: let
  palette = config.theme.palette;

  # Generate k9s skin from palette
  mkK9sSkin = p: {
    k9s = {
      body = {
        fgColor = p.text;
        bgColor = p.base;
        logoColor = p.mauve;
      };
      prompt = {
        fgColor = p.text;
        bgColor = p.mantle;
        suggestColor = p.blue;
      };
      help = {
        fgColor = p.text;
        bgColor = p.base;
        sectionColor = p.green;
        keyColor = p.blue;
        numKeyColor = p.maroon;
      };
      frame = {
        title = {
          fgColor = p.teal;
          bgColor = p.base;
          highlightColor = p.pink;
          counterColor = p.yellow;
          filterColor = p.green;
        };
        border = {
          fgColor = p.mauve;
          focusColor = p.lavender;
        };
        menu = {
          fgColor = p.text;
          keyColor = p.blue;
          numKeyColor = p.maroon;
        };
        crumbs = {
          fgColor = p.base;
          bgColor = p.maroon;
          activeColor = p.flamingo;
        };
        status = {
          newColor = p.blue;
          modifyColor = p.lavender;
          addColor = p.green;
          pendingColor = p.peach;
          errorColor = p.red;
          highlightColor = p.sky;
          killColor = p.mauve;
          completedColor = p.overlay0;
        };
      };
      info = {
        fgColor = p.peach;
        sectionColor = p.text;
      };
      views = {
        table = {
          fgColor = p.text;
          bgColor = p.base;
          cursorFgColor = p.surface0;
          cursorBgColor = p.surface1;
          markColor = p.rosewater;
          header = {
            fgColor = p.yellow;
            bgColor = p.base;
            sorterColor = p.sky;
          };
        };
        xray = {
          fgColor = p.text;
          bgColor = p.base;
          cursorColor = p.surface1;
          cursorTextColor = p.base;
          graphicColor = p.pink;
        };
        charts = {
          bgColor = p.base;
          chartBgColor = p.base;
          dialBgColor = p.base;
          defaultDialColors = [p.green p.red];
          defaultChartColors = [p.green p.red];
          resourceColors = {
            cpu = [p.mauve p.blue];
            mem = [p.yellow p.peach];
          };
        };
        yaml = {
          keyColor = p.blue;
          valueColor = p.text;
          colonColor = p.subtext0;
        };
        logs = {
          fgColor = p.text;
          bgColor = p.base;
          indicator = {
            fgColor = p.lavender;
            bgColor = p.base;
            toggleOnColor = p.green;
            toggleOffColor = p.subtext0;
          };
        };
      };
      dialog = {
        fgColor = p.yellow;
        bgColor = p.overlay2;
        buttonFgColor = p.base;
        buttonBgColor = p.overlay1;
        buttonFocusFgColor = p.base;
        buttonFocusBgColor = p.pink;
        labelFgColor = p.rosewater;
        fieldFgColor = p.text;
      };
    };
  };
in {
  programs.k9s = {
    enable = true;
    settings.k9s = {
      ui = {
        enableMouse = true;
        skin = palette.dark.name; # Default, theme-toggle switches this
      };
    };
    # Generated from lib/theme-palette.nix
    skins = {
      "${palette.dark.name}" = mkK9sSkin palette.dark;
      "${palette.light.name}" = mkK9sSkin palette.light;
    };
  };

  home.packages = with pkgs; [
    kubectl
  ];
}
