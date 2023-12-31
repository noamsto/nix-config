{
  config,
  pkgs,
  ...
}: {
  xdg.configFile."foot/foot.ini".source = config.lib.file.mkOutOfStoreSymlink "/home/noams/nix-config/home/terminal/foot/foot.ini";
  home.packages = with pkgs; [
    libsixel
    # for displaying images
  ];
  programs.foot = {
    enable = true;
  };
}
