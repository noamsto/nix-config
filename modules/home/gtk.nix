{
  config,
  pkgs,
  ...
}: {
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
    cursorTheme = {
      size = 24;
      name = "breeze_cursors";
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
      gtk-menu-images=1
      gtk-button-images=1
      gtk-enable-animations=1
      gtk-primary-button-warps-slider=0
      gtk-toolbar-style=3
    '';
  };
}
