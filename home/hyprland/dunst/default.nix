{
  pkgs,
  config,
  ...
}: let
  script-name = "dunst-osd";
  dunst-osd-src = builtins.readFile ./dunst-osd.sh;
  dunst-osd = (pkgs.writeScriptBin script-name dunst-osd-src).overrideAttrs (old: {
    buildCommand = "${old.buildCommand}\n patchShebangs $out";
  });
in {
  home.packages = [dunst-osd];

  xdg.configFile."dunst/dunstrc".source = config.lib.file.mkOutOfStoreSymlink "/home/noams/nix-config/home/hyprland/dunst/dunstrc";
}
