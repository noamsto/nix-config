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
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = true;
    };
    gtk3.extraConfig = gtk4.extraConfig;
    gtk2.extraCOnfig = {
      gtk-menu-images = 1;
      gtk-button-images = 1;
      gtk-cursor-theme-size = 24;
      gtk-cursor-theme-name = "breeze_cursors";
      gtk-font-name = "Noto Sans,  10";
      gtk-enable-animations = 1;
      gtk-primary-button-warps-slider = 0;
      gtk-toolbar-style = 3;
    };
  };
}
