# Prints every research report or error not yet relayed, then remembers it, and
# warns once about a request that has waited too long for the runner.
# hermes cannot write to the report dir, so the delivered ids live in its own
# home. Hermes sends nothing when a script-only cron job prints nothing and
# exits 0; a non-zero exit is relayed as a failure alert.
{
  pkgs,
  lib,
  reportDir,
}:
pkgs.writeShellApplication {
  name = "scout-relay-research";
  runtimeInputs = [pkgs.coreutils pkgs.findutils pkgs.gnugrep];
  text = ''
    dir=${lib.escapeShellArg reportDir}
    state="''${HERMES_HOME:?}/scout-research-delivered"
    alerted="''${HERMES_HOME:?}/scout-research-alerted"
    touch "$state" "$alerted"
    out=""
    delivered=""
    warned=""
    sep=$'\n\n———\n\n'
    shopt -s nullglob
    for f in "$dir"/research/*.md "$dir"/research/*.error; do
      name="$(basename "$f")"
      id="''${name%.*}"
      grep -qxF "$id" "$state" && continue
      if [[ $f == *.md ]]; then
        body="$(cat "$f")"
      else
        body="⚠️ **Research failed** ($id): $(cat "$f")"
      fi
      out+="''${out:+$sep}$body"
      delivered+="$id"$'\n'
    done
    # The runner claims a request within seconds; one still here after 10 min means it failed to start.
    for f in "$dir"/requests/*.json; do
      [ -n "$(find "$f" -mmin +10)" ] || continue
      id="$(basename "$f" .json)"
      grep -qxF "$id" "$alerted" && continue
      out+="''${out:+$sep}⚠️ **Research request $id is still waiting** after 10 min; the runner may have failed (check /scoutstatus)."
      warned+="$id"$'\n'
    done
    printf '%s' "$out"
    printf '%s' "$delivered" >> "$state"
    printf '%s' "$warned" >> "$alerted"
  '';
}
