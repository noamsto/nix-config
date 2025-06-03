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

  home.packages = [
    pkgs.kdePackages.breeze-gtk
  ];

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
      gtk-theme-name="Breeze-Dark"
      gtk-button-images=1
      gtk-menu-images=1
      gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ
    '';

    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-button-images = 1;
      gtk-menu-images = 1;
      gtk-toolbar-style = "GTK_TOOLBAR_BOTH_HORIZ";
      gtk-primary-button-warps-slider = 0;
      gtk-decoration-layout = "menu:close";
      gtk-enable-animations = true;
      gtk-overlay-scrolling = true;
      gtk-theme-name = "Breeze";
    };

    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-enable-animations = true;
      gtk-overlay-scrolling = true;
      gtk-theme-name = "Breeze";
    };
  };
}
