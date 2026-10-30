# Both scripts share lock_state/lock_client_pids from the state lib.
{pkgs}: name: pkgs.writeShellScriptBin name (builtins.readFile ./aegis-lock-state.sh + builtins.readFile ./${name}.sh)
