{
  lib,
  osConfig,
  ...
}: {
  imports =
    [
      ./packages.nix
      ./terminal
      ./xdg
      ./git
      ./direnv
      ./ssh
      ./nvim
      ./ipython
    ]
    ++ lib.optionals (osConfig.desktop.mode != "none") [
      ./browsers
      ./obs-studio
      ./easyeffects
      ./vscode
      ./gtk
    ]
    ++ lib.optionals (osConfig.desktop.mode == "kde") [
      ./plasma-manager
    ]
    ++ lib.optionals (osConfig.desktop.mode == "hyprland") [
      ./hyprland
    ]
    ++ lib.optionals (osConfig.profile == "work") [
      ./kubernetes
      ./zoom
    ];

  home = {
    username = osConfig.username;
    homeDirectory = "/home/${osConfig.username}";
    stateVersion = "23.05";
  };

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}
