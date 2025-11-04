{pkgs}: {
  sesh-new = pkgs.writeShellScriptBin "sesh-new" (builtins.readFile ./scripts/sesh-new.sh);
  sesh-kill = pkgs.writeShellScriptBin "sesh-kill" (builtins.readFile ./scripts/sesh-kill.sh);
  sesh-list-grouped = pkgs.writeShellScriptBin "sesh-list-grouped" (builtins.readFile ./scripts/sesh-list-grouped.sh);
  sesh-icon = pkgs.writeShellScriptBin "sesh-icon" (builtins.readFile ./scripts/sesh-icon.sh);
}
