{
  pkgs,
  lib,
  ...
}: let
  keyboard-layout = pkgs.writeShellScriptBin "keyboard-layout" ''
    export PATH="${lib.makeBinPath [pkgs.jq pkgs.socat]}:$PATH"
    ${builtins.readFile ./keyboard-layout.sh}
  '';
in {
  home.packages = [keyboard-layout];
}
