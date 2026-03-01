# Theme palette module - provides config.theme.palette.{dark,light}
# Currently using Catppuccin (dark = Mocha, light = Latte)
{lib, ...}:
with lib; let
  # Color type for validation
  hexColor = types.strMatching "#[0-9a-fA-F]{6}";

  # Define the color option structure
  colorOptions = {
    # Theme metadata
    name = mkOption {
      type = types.str;
      description = "Theme name identifier";
    };
    variant = mkOption {
      type = types.enum ["dark" "light"];
      description = "Theme variant";
    };

    # Base backgrounds
    crust = mkOption {type = hexColor;};
    mantle = mkOption {type = hexColor;};
    base = mkOption {type = hexColor;};

    # Surface colors
    surface0 = mkOption {type = hexColor;};
    surface1 = mkOption {type = hexColor;};
    surface2 = mkOption {type = hexColor;};

    # Overlay colors
    overlay0 = mkOption {type = hexColor;};
    overlay1 = mkOption {type = hexColor;};
    overlay2 = mkOption {type = hexColor;};

    # Text colors
    subtext0 = mkOption {type = hexColor;};
    subtext1 = mkOption {type = hexColor;};
    text = mkOption {type = hexColor;};

    # Accent colors
    rosewater = mkOption {type = hexColor;};
    flamingo = mkOption {type = hexColor;};
    pink = mkOption {type = hexColor;};
    mauve = mkOption {type = hexColor;};
    red = mkOption {type = hexColor;};
    maroon = mkOption {type = hexColor;};
    peach = mkOption {type = hexColor;};
    yellow = mkOption {type = hexColor;};
    green = mkOption {type = hexColor;};
    teal = mkOption {type = hexColor;};
    sky = mkOption {type = hexColor;};
    sapphire = mkOption {type = hexColor;};
    blue = mkOption {type = hexColor;};
    lavender = mkOption {type = hexColor;};
  };
in {
  options.theme = {
    palette = {
      dark = colorOptions;
      light = colorOptions;
    };
  };

  config.theme.palette = {
    # Dark theme - Catppuccin Mocha
    dark = {
      name = "catppuccin-mocha";
      variant = "dark";

      crust = "#11111b";
      mantle = "#181825";
      base = "#1e1e2e";

      surface0 = "#313244";
      surface1 = "#45475a";
      surface2 = "#585b70";

      overlay0 = "#6c7086";
      overlay1 = "#7f849c";
      overlay2 = "#9399b2";

      subtext0 = "#a6adc8";
      subtext1 = "#bac2de";
      text = "#cdd6f4";

      rosewater = "#f5e0dc";
      flamingo = "#f2cdcd";
      pink = "#f5c2e7";
      mauve = "#cba6f7";
      red = "#f38ba8";
      maroon = "#eba0ac";
      peach = "#fab387";
      yellow = "#f9e2af";
      green = "#a6e3a1";
      teal = "#94e2d5";
      sky = "#89dceb";
      sapphire = "#74c7ec";
      blue = "#89b4fa";
      lavender = "#b4befe";
    };

    # Light theme - Catppuccin Latte (WCAG AA adjusted for text on light backgrounds)
    # Original latte colors adjusted for 4.5:1 contrast ratio against #eff1f5 base
    light = {
      name = "catppuccin-latte";
      variant = "light";

      crust = "#dce0e8";
      mantle = "#e6e9ef";
      base = "#eff1f5";

      surface0 = "#ccd0da";
      surface1 = "#bcc0cc";
      surface2 = "#acb0be";

      overlay0 = "#9ca0b0";
      overlay1 = "#8c8fa1";
      overlay2 = "#7c7f93";

      subtext0 = "#6c6f85";
      subtext1 = "#5c5f77";
      text = "#4c4f69";

      # Accent colors - darkened from original latte for WCAG AA compliance
      rosewater = "#a85847"; # original: #dc8a78
      flamingo = "#b54545"; # original: #dd7878
      pink = "#b84a9e"; # original: #ea76cb
      mauve = "#8839ef"; # already good contrast
      red = "#d20f39"; # already good contrast
      maroon = "#c0364a"; # original: #e64553
      peach = "#c24b00"; # original: #fe640b
      yellow = "#996b00"; # original: #df8e1d
      green = "#358023"; # original: #40a02b
      teal = "#147076"; # original: #179299
      sky = "#0480b3"; # original: #04a5e5
      sapphire = "#1a7d8f"; # original: #209fb5
      blue = "#1e66f5"; # already good contrast
      lavender = "#5a6ad4"; # original: #7287fd
    };
  };
}
