{pkgs, ...}: let
  script-name = "dunst-osd";
  dunst-osd-src = builtins.readFile ./dunst-osd.sh;
  dunst-osd = (pkgs.writeScriptBin script-name dunst-osd-src).overrideAttrs (old: {
    buildCommand = "${old.buildCommand}\n patchShebangs $out";
  });
in {
  home.packages = [dunst-osd];
  services.dunst.settings = {
    global = {
      origin = "bottom-center";
      font = "Fira Code Nerd Font";
    };
  };
}
