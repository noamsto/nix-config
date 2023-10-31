{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    joplin-desktop
    # logseq
    google-chrome
    vlc
    lazygit
    solaar
    jetbrains.pycharm-professional
  ];
}
