{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    joplin-desktop
    logseq
    vlc
    lazygit
    solaar
  ];
}
