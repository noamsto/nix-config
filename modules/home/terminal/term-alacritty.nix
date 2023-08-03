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
  ];
}
