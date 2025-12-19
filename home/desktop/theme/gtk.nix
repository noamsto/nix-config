{
  pkgs,
  config,
  ...
}: {
  # System-wide cursor settings
  home.pointerCursor = {
    name = "Bibata-Modern-Ice";
    package = pkgs.bibata-cursors;
    size = 24;
    gtk.enable = true;
  };

  home.packages = with pkgs; [
    catppuccin-kvantum # Catppuccin themes for Kvantum (Mocha, Latte, etc.)
    libsForQt5.qtstyleplugin-kvantum # Kvantum Qt5 style engine
    kdePackages.qtstyleplugin-kvantum # Kvantum Qt6 style engine
  ];

  # Qt theming - use Kvantum for runtime theme switching
  qt = {
    enable = true;
    platformTheme.name = "kvantum";
    style.name = "kvantum";
  };

  # Kvantum configuration is written dynamically by theme-toggle script
  # Initial setup creates the file if it doesn't exist

  gtk = {
    enable = true;

    font = {
      name = "Inter Nerd Font";
      size = 12;
    };

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

    gtk4.extraConfig = {
      gtk-enable-animations = true;
      gtk-overlay-scrolling = true;
      gtk-theme-name = "Adwaita";
    };
  };
}
