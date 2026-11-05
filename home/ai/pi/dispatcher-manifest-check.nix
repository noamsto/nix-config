# Coverage check for the dispatcher manifest generated in ./guards.nix (#567).
#
# Every pi handler in the locked dispatcher's hookyard.json must end up in the
# generated manifest as `dispatcher.<id>` — with the same events/match/lane/
# timeout_ms and an absolute store-path exec — unless ./guards.nix names it in
# its explicit dispatcherExcluded list. A handler that silently drops out is the
# failure #567 exists to fix, so it is a build failure here, not a missing guard
# at hook-fire time.
{
  pkgs,
  dispatcher,
}: let
  inherit (import ./guards.nix {inherit pkgs dispatcher;}) dispatcherExcluded dispatcherManifest;
in
  pkgs.runCommand "pi-dispatcher-manifest-check" {
    nativeBuildInputs = [pkgs.jq];
  } ''
    ${pkgs.jq}/bin/jq -n -e \
      --slurpfile hookyard ${dispatcher}/hookyard.json \
      --slurpfile manifest ${dispatcherManifest} \
      --argjson excluded '${builtins.toJSON dispatcherExcluded}' '
      ($hookyard[0].handlers | map(select((.engines // []) | index("pi")))) as $declared
      | ($declared | map(.id)) as $declaredIds
      | ($manifest[0].handlers | map({key: (.id | ltrimstr("dispatcher.")), value: .}) | from_entries) as $byId
      | ($declaredIds - $excluded) as $wantIds
      | {
          missing: ($wantIds | map(select($byId[.] == null))),
          unexpected: (($byId | keys) - $declaredIds),
          excluded_but_present: ($excluded | map(. as $id | select($byId[$id] != null))),
          stale_exclusions: ($excluded | map(. as $id | select($declaredIds | index($id) == null))),
          mismatched: ($declared | map(
            . as $h
            | select(($excluded | index($h.id)) == null)
            | select($byId[$h.id] != null)
            | select(
                ($byId[$h.id].events != $h.events)
                or ($byId[$h.id].engines != ["pi"])
                or (($byId[$h.id].match // []) != ($h.match // []))
                or (($byId[$h.id].timeout_ms // 0) != ($h.timeout_ms // 0))
                or (($byId[$h.id].lane // "verdict") != ($h.lane // "verdict"))
                or (($byId[$h.id].exec | type) != "string")
                or (($byId[$h.id].exec | startswith("/nix/store/")) | not))
            | $h.id))
        }
      | if ([.missing, .unexpected, .excluded_but_present, .stale_exclusions, .mismatched] | map(length) | add) == 0
        then "ok"
        else error("dispatcher manifest coverage failed: " + tostring)
        end
    ' >/dev/null
    touch $out
  ''
