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
      ./claude-code
    ]
    ++ lib.optionals (osConfig.desktop.mode != "none") [
      ./desktop
    ]
    ++ lib.optionals (osConfig.profile == "work") [
      ./kubernetes
    ];

  home = {
    username = osConfig.username;
    homeDirectory = "/home/${osConfig.username}";
    stateVersion = "23.05";
  };

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}
