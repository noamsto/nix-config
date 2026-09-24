# Runs the scout relay against status.json fixtures: a fresh success, a stale
# error from yesterday, a run still in flight, and today's failure.
{pkgs}: let
  # Relative, so the relay reads the fixtures from the build directory.
  relay = import ./money-scout-relay.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    reportDir = "scout";
  };
in
  pkgs.runCommand "money-scout-relay-test" {
    nativeBuildInputs = [pkgs.coreutils];
    TZDIR = "${pkgs.tzdata}/share/zoneinfo";
  } ''
    set -euo pipefail
    mkdir scout
    echo "digest body" > scout/crowd.md
    today="$(TZ=Asia/Jerusalem date +%F)"
    yesterday="$(TZ=Asia/Jerusalem date -d yesterday +%F)"

    expect() {
      local want_code=$1 want_out=$2 status=$3 got code
      echo "$status" > scout/status.json
      code=0
      got="$(${relay}/bin/scout-relay crowd)" || code=$?
      echo "[$code] $got"
      if [ "$code" != "$want_code" ] || [ "$got" != "$want_out" ]; then
        echo "FAIL: want [$want_code] $want_out"
        exit 1
      fi
    }

    expect 0 "digest body" \
      '{"crowd":{"ok":true,"date":"'"$today"'","finishedAt":"t"}}'
    expect 1 "scout crowd: no run today (last run $yesterday)" \
      '{"crowd":{"ok":false,"date":"'"$yesterday"'","finishedAt":"t","error":"boom"}}'
    expect 1 "scout crowd: still running (started 05:15)" \
      '{"crowd":{"ok":false,"running":true,"date":"'"$today"'","startedAt":"05:15"}}'
    expect 1 "scout crowd: boom" \
      '{"crowd":{"ok":false,"date":"'"$today"'","finishedAt":"t","error":"boom"}}'
    touch $out
  ''
