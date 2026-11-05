{pkgs, ...}: let
  brightness-control = pkgs.writeShellScriptBin "brightness-control" (builtins.readFile ./brightness-control.sh);
in {
  home.packages = [brightness-control];
}
