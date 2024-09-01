{pkgs, ...}: let
  script-name = "named-session";
  named-session-src = builtins.readFile ./named-session.sh;
  named-session = (pkgs.writeScriptBin script-name named-session-src).overrideAttrs (old: {
    buildCommand = "${old.buildCommand}\n patchShebangs $out";
  });
in {
  home.packages = [named-session];
}
