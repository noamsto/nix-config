{pkgs, ...}: let
  script-name = "code-shell";
  code-shell-src = builtins.readFile ./code-shell;
  code-shell = (pkgs.writeScriptBin script-name code-shell-src).overrideAttrs (old: {
    buildCommand = "${old.buildCommand}\n patchShebangs $out";
  });
in {
  home.packages = [code-shell];
}
