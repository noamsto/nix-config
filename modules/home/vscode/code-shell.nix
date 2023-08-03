{
  config,
  lib,
  flake-utils,
  pkgs,
  ...
}:
#   description = "A better version";
#   inputs.flake-utils.url = "github:numtide/flake-utils";
let
  script-name = "code-shell";
  code-shell-src = builtins.readFile ./code-shell;
  code-shell = (pkgs.writeScriptBin script-name code-shell-src).overrideAttrs (old: {
    buildCommand = "${old.buildCommand}\n patchShebangs $out";
  });
in {
  home.packages = with pkgs; [code-shell];
}
