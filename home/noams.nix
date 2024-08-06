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
      ./vscode
      ./git
      ./kubernetes
      ./direnv
      ./zoom
      ./ssh
      ./nvim
      ./browsers
      ./obs-studio
      ./easyeffects
    ]
    ++ lib.optionals (osConfig.desktop.mode == "kde") [
      ./plasma-manager
    ];

  home = {
    username = osConfig.username;
    homeDirectory = "/home/${osConfig.username}";
    stateVersion = "23.05";
  };

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}
