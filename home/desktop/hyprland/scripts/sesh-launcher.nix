{pkgs, ...}: {
  home.packages = [
    (pkgs.writeShellScriptBin "sesh-launcher" (builtins.readFile ./sh/sesh-launcher.sh))
  ];
}
