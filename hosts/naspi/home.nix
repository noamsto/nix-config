{
  pkgs,
  username,
  ...
}: {
  imports = [
    ../../home/git
    ../../home/terminal/minimal.nix
    ../../home/xdg
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
