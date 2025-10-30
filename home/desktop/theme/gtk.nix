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
    pkgs.kdePackages.breeze # Breeze theme for KDE apps (includes dark mode)
  ];

  # Qt theming - use KDE platform with Breeze for proper dark theme
  qt = {
    enable = true;
    platformTheme.name = "kde";
    style = {
      name = "breeze";
      package = pkgs.kdePackages.breeze;
    };
  };

  # Link official Breeze Dark color scheme file
  xdg.dataFile."color-schemes/BreezeDark.colors".source = "${pkgs.kdePackages.breeze}/share/color-schemes/BreezeDark.colors";

  # KDE configuration - use complete Breeze Dark color scheme with custom fonts/icons
  xdg.configFile."kdeglobals" = {
    force = true;
    text = let
      # Read complete official BreezeDark color scheme (all 8 [Colors:*] sections)
      breezeColors = builtins.readFile "${pkgs.kdePackages.breeze}/share/color-schemes/BreezeDark.colors";

      # Custom fonts and icon theme
      customSettings = ''

        [General]
        fixed=FiraCode Nerd Font,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
        font=Inter Nerd Font,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1

        [Icons]
        Theme=Papirus-Dark

        [KDE]
        LookAndFeelPackage=org.kde.breezedark.desktop
        widgetStyle=Breeze
      '';
    in
      breezeColors + customSettings;
  };

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
      gtk-theme-name="Adwaita-dark"
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
      gtk-theme-name = "Adwaita-dark";
    };

    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-enable-animations = true;
      gtk-overlay-scrolling = true;
      gtk-theme-name = "Adwaita-dark";
    };
  };
}
