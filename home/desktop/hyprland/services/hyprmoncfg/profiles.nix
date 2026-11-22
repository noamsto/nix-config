{
  pkgs,
  lib,
  profiles,
}:
pkgs.runCommand "hyprmoncfg-profiles" {nativeBuildInputs = [pkgs.hyprmoncfg];} ''
  mkdir "$out"
  ${lib.concatStrings (lib.mapAttrsToList (name: value: ''
      cp ${pkgs.writeText "${name}.json" (builtins.toJSON value)} "$out/${name}.json"
    '')
    profiles)}
  # hyprmoncfgd refuses every profile when any file is invalid, so validate at build time.
  check=$(mktemp -d)
  cp -r "$out" "$check/profiles"
  chmod -R u+w "$check"
  HOME="$check" hyprmoncfg profiles --config-dir "$check"
''
