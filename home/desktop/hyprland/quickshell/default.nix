{
  config,
  pkgs,
  inputs,
  ...
}: {
  # Home Manager's XDG config to place quickshell files in the right location
  xdg.configFile."quickshell" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/desktop/hyprland/quickshell";
    recursive = true;
  };

  # QML development tools for QuickShell development
  home.packages = with pkgs; [
    # Additional QML development tools
    kdePackages.qttools # Provides qml, qmlformat, qmlimportscanner

    # Shell/Desktop environment
    hyprland-qtutils
  ];

  # Enable quickshell through home packages (already added in packages.nix)
  # The package will be available through inputs.quickshell.packages."${pkgs.system}".default
}
