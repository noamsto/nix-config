{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./home/gtk.nix # Current conlficts with current settings. will enable in the future
    ./home/terminal/term-alacritty.nix
    ./home/xdg
    ./home/vscode
    ./home/git
    ./home/kubernetes
    ./home/btop
    ./home/dev
    ./home/zoom
    ./home/ssh
    ./home/packages.nix
  ];
}
