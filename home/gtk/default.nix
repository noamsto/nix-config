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
    x11.enable = true;
  };
  gtk = {
    enable = true;

    font = {
      name = "Ubuntu Nerd Font";
      size = 14;
    };

    theme = {
      name = "Breeze";
      package = pkgs.kdePackages.breeze-gtk;
    };

    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };

    gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
    gtk2.extraConfig = ''
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
    };

    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-enable-animations = true;
      gtk-overlay-scrolling = true;
    };
  };
}
