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
    ./home/bottom
    ./home/dev
    ./home/zoom
    ./home/ssh
    ./home/packages.nix
    ./home/nvim-astro
    ./home/bat
    ./home/fzf
    ./home/firefox
    # ./home/emacs
  ];
}
