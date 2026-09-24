# Prints the day's report for a scout job (`scout-relay watch`), or one line
# saying why there is none, with a non-zero exit so Hermes alerts on it.
{
  pkgs,
  lib,
  reportDir,
}:
pkgs.writeShellApplication {
  name = "scout-relay";
  runtimeInputs = [pkgs.jq pkgs.coreutils];
  text = ''
    job="''${1:?usage: scout-relay <job>}"
    dir=${lib.escapeShellArg reportDir}
    today="$(TZ=Asia/Jerusalem date +%F)"
    case "$job" in
      crowd) label="Scout digest" ;;
      *) label="Scout $job" ;;
    esac
    if [ ! -r "$dir/status.json" ]; then
      echo "⚠️ **$label**: no status file, the $job timer has never run"
      exit 1
    fi
    if ! jq -e --arg j "$job" --arg d "$today" '.[$j].ok == true and .[$j].date == $d' "$dir/status.json" >/dev/null; then
      # An error is today's news only if it carries today's date; an older one
      # means today's run never happened.
      reason="$(jq -r --arg j "$job" --arg d "$today" '
        if .[$j].date == $d and .[$j].running == true then "still running (started \(.[$j].startedAt // "?"))"
        elif .[$j].date == $d then (.[$j].error // "unknown error")
        else "no run today (last run \(.[$j].date // "never"))" end' "$dir/status.json")"
      echo "⚠️ **$label**: $reason"
      exit 1
    fi
    case "$job" in
      crowd) report="$dir/crowd.md" ;;
      *) report="$dir/$job.txt" ;;
    esac
    cat "$report"
  '';
}
