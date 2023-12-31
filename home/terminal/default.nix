{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./alacritty
    ./zsh
    ./starship
    ./tmux
    ./zellij
    ./btop
    ./bat
    ./fzf
  ];
}
