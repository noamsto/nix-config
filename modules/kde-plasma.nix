{
  config,
  pkgs,
  ...
}: {
  imports = [
    # ./modules/home/gtk.nix  # Current conlficts with current settings. will enable in the future
    ./modules/home/terminal/term-alacritty.nix
    ./modules/home/xdg
    ./modules/home/vscode
    ./modules/home/git
    ./modules/home/kubernetes
    ./modules/home/btop
  ];
}
