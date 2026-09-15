{pkgs, ...}: let
  aegis-lock-recover = pkgs.writeShellScriptBin "aegis-lock-recover" (builtins.readFile ./aegis-lock-recover.sh);
in {
  home.packages = [aegis-lock-recover];
}
