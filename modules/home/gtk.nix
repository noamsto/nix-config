{
  config,
  pkgs,
  ...
}: {
  # home.pointerCursor = {
  #   package = pkgs.bibata-cursors;
  #   name = "Bibata-Modern-Classic";
  #   size = 24;
  #   gtk.enable = true;
  #   x11.enable = true;
  # };

  # # set dpi for 4k monitor
  # xresources.properties = {
  #   # dpi for Xorg's font
  #   "Xft.dpi" = 162;
  #   # or set a generic dpi
  #   "*.dpi" = 162;
  # };

  gtk = rec {
    enable = true;
    iconTheme = {
      package = pkgs.breeze-icons;
      name = "breeze-dark";
    };
    theme = {
      package = pkgs.breeze-gtk;
      name = "breeze-dark";
    };
    font = {
      name = "Noto Sans";
      size = 10;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-decoration-layout = "icon:minimize,maximize,close";
      gtk-modules = "colorreload-gtk-module";
      gtk-enable-animations = true;
      gtk-primary-button-warps-slider = false;
      gtk-xft-dpi = 98304;
    };
    gtk3.extraConfig =
      gtk4.extraConfig
      // {
        gtk-menu-images = true;
        gtk-toolbar-style = 3;
        gtk-button-images = true;
      };
    gtk2.extraConfig = ''
      gtk-font-name="Noto Sans,  10"
      gtk-icon-theme-name="breeze-dark"
      gtk-menu-images=1
      gtk-button-images=1
      gtk-enable-animations=1
      gtk-primary-button-warps-slider=0
      gtk-toolbar-style=3
    '';
    gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
  };
}
