{
  pkgs,
  username,
  ...
}: {
  imports = [
    ../../home/git
    ../../home/terminal/bat
    ../../home/terminal/btop
    ../../home/terminal/fzf
    ../../home/terminal/zsh
    ../../home/terminal/starship
    ../../home/terminal/tmux
    ../../home/xdg
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";

  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
