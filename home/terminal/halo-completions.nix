# Fish completions for `halo` (other hosts) and `halo-ops` (on halo). Input
# names come from the local flake.lock, so completion never touches ssh.
{
  pkgs,
  command,
  flake,
}: let
  isHalo = command == "halo";
  updateVerb =
    if isHalo
    then "update"
    else "update-prepare";
  subcommands =
    if isHalo
    then "rebuild update reboot status logs restart console push"
    else "rebuild update-prepare update-push reboot status logs restart console";
  fn = "__${builtins.replaceStrings ["-"] ["_"] command}";
in
  pkgs.writeText "${command}.fish" ''
    function ${fn}_inputs
      ${pkgs.jq}/bin/jq -r '.nodes[.root].inputs | keys[]' ${flake}/flake.lock 2>/dev/null
    end

    function ${fn}_updating
      set -l tokens (commandline -opc)
      test (count $tokens) -ge 2; and test "$tokens[2]" = ${updateVerb}
    end

    complete -c ${command} -f
    complete -c ${command} -n __fish_use_subcommand -a '${subcommands}'
    complete -c ${command} -n ${fn}_updating -a '(${fn}_inputs)' -d 'Flake input'
    complete -c ${command} -n ${fn}_updating -l skip -x -a '(${fn}_inputs)' -d 'Leave this input out'
    ${pkgs.lib.optionalString isHalo "complete -c ${command} -n ${fn}_updating -l switch -d 'Rebuild halo after pushing'"}
    complete -c ${command} -n '__fish_seen_subcommand_from restart' -a 'lemond ds4'
    complete -c ${command} -n '__fish_seen_subcommand_from console' -a 'on off'
    complete -c ${command} -n '__fish_seen_subcommand_from logs' -a 'halo-rebuild halo-update-prepare halo-update-push halo-reboot lemond ds4-server display-manager'
  ''
