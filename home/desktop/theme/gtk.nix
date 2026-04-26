{
  pkgs,
  config,
  ...
}: let
  inherit (config.theme) palette;

  # Shade colors vary by theme variant
  shadeColor = p:
    if p.variant == "dark"
    then "rgba(0, 0, 0, 0.36)"
    else "rgba(0, 0, 0, 0.07)";

  # Generate GTK CSS from palette
  mkGtkCss = p: ''
    /* ${p.name} colors for GTK4/libadwaita - Generated from config.theme.palette */

    @define-color accent_color ${p.mauve};
    @define-color accent_bg_color ${p.mauve};
    @define-color accent_fg_color ${p.base};

    @define-color destructive_color ${p.red};
    @define-color destructive_bg_color ${p.red};
    @define-color destructive_fg_color ${p.base};

    @define-color success_color ${p.green};
    @define-color success_bg_color ${p.green};
    @define-color success_fg_color ${p.base};

    @define-color warning_color ${p.yellow};
    @define-color warning_bg_color ${p.yellow};
    @define-color warning_fg_color ${p.base};

    @define-color error_color ${p.red};
    @define-color error_bg_color ${p.red};
    @define-color error_fg_color ${p.base};

    @define-color window_bg_color ${p.base};
    @define-color window_fg_color ${p.text};

    @define-color view_bg_color ${p.mantle};
    @define-color view_fg_color ${p.text};

    @define-color headerbar_bg_color ${p.base};
    @define-color headerbar_fg_color ${p.text};
    @define-color headerbar_border_color ${p.surface0};
    @define-color headerbar_backdrop_color @window_bg_color;
    @define-color headerbar_shade_color ${shadeColor p};

    @define-color sidebar_bg_color ${p.mantle};
    @define-color sidebar_fg_color ${p.text};
    @define-color sidebar_backdrop_color ${p.mantle};
    @define-color sidebar_shade_color ${shadeColor p};

    @define-color secondary_sidebar_bg_color ${p.crust};
    @define-color secondary_sidebar_fg_color ${p.text};
    @define-color secondary_sidebar_backdrop_color ${p.crust};
    @define-color secondary_sidebar_shade_color ${shadeColor p};

    @define-color card_bg_color ${
      if p.variant == "dark"
      then p.surface0
      else p.mantle
    };
    @define-color card_fg_color ${p.text};
    @define-color card_shade_color ${shadeColor p};

    @define-color dialog_bg_color ${
      if p.variant == "dark"
      then p.surface0
      else p.mantle
    };
    @define-color dialog_fg_color ${p.text};

    @define-color popover_bg_color ${
      if p.variant == "dark"
      then p.surface0
      else p.mantle
    };
    @define-color popover_fg_color ${p.text};
    @define-color popover_shade_color ${shadeColor p};

    @define-color thumbnail_bg_color ${
      if p.variant == "dark"
      then p.mantle
      else p.crust
    };
    @define-color thumbnail_fg_color ${p.text};

    @define-color shade_color ${shadeColor p};
    @define-color scrollbar_outline_color ${p.surface1};

    /* Borders and separators */
    @define-color borders ${p.surface1};
    @define-color unfocused_borders ${p.surface0};

    /* Links */
    @define-color link_color ${p.blue};
    @define-color link_visited_color ${p.mauve};

    /* Selection */
    @define-color selected_bg_color ${p.blue};
    @define-color selected_fg_color ${p.base};
  '';
in {
  # System-wide cursor settings
  home.pointerCursor = {
    name = "Bibata-Modern-Ice";
    package = pkgs.bibata-cursors;
    size = 24;
    gtk.enable = true;
  };

  # Kvantum Qt style engines (catppuccin.kvantum handles theme files)
  home.packages = with pkgs; [
    libsForQt5.qtstyleplugin-kvantum # Kvantum Qt5 style engine
    kdePackages.qtstyleplugin-kvantum # Kvantum Qt6 style engine
  ];

  # Qt theming - use Kvantum for runtime theme switching
  # Kvantum theme is set dynamically by theme-toggle script
  qt = {
    enable = true;
    platformTheme.name = "kvantum";
    style.name = "kvantum";
  };

  gtk = {
    enable = true;

    font = {
      name = "Inter Nerd Font";
      size = 12;
    };

    # Icon name set dynamically by theme-toggle (Papirus-Dark/Papirus-Light)
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };

    gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
    gtk2.extraConfig = ''
      gtk-theme-name="Adwaita"
      gtk-button-images=1
      gtk-menu-images=1
      gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ
    '';

    # GTK3/4 settings are in Nix store, but gtk-application-prefer-dark-theme
    # needs to be dynamic for theme switching. The theme-toggle script handles
    # this via dconf and GTK_THEME env var. Electron apps read color-scheme
    # from the portal which is updated dynamically.

    gtk4.theme = null;
    gtk4.extraConfig = {
      gtk-enable-animations = true;
      gtk-overlay-scrolling = true;
      gtk-theme-name = "Adwaita";
    };
  };

  # Generated GTK CSS files for theme-toggle (libadwaita color overrides)
  xdg.configFile = {
    "gtk-theme/gtk-${palette.dark.name}.css".text = mkGtkCss palette.dark;
    "gtk-theme/gtk-${palette.light.name}.css".text = mkGtkCss palette.light;
  };
}
