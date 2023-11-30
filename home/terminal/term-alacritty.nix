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
    ./btop
    ./bat
    ./fzf
  ];
}
