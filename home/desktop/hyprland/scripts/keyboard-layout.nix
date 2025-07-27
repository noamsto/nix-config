{
  pkgs,
  lib,
  ...
}: let
  keyboard-layout = pkgs.writeShellScriptBin "keyboard-layout" (builtins.readFile ./keyboard-layout.sh);
in {
  home.packages = [keyboard-layout];
}
