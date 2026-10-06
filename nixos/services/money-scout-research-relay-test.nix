# Relays new research reports and errors once each, and prints nothing when
# there is nothing new.
{pkgs}: let
  relay = import ./money-scout-research-relay.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    reportDir = "scout";
  };
in
  pkgs.runCommand "money-scout-research-relay-test" {} ''
    set -euo pipefail
    mkdir -p scout/research home
    export HERMES_HOME=$PWD/home
    echo "**AVGO — NOT NOW**" > scout/research/20261006T101500-ticker-AVGO.md
    echo "timeout after 10 min" > scout/research/20261006T110000-review.error
    echo "{}" > scout/research/20261006T101500-ticker-AVGO.json
    first="$(${relay}/bin/scout-relay-research)"
    echo "$first" | grep -q "AVGO — NOT NOW"
    echo "$first" | grep -q "Research failed.*review.*timeout after 10 min"
    second="$(${relay}/bin/scout-relay-research)"
    [ -z "$second" ] || { echo "FAIL: relayed twice: $second"; exit 1; }

    # A request the runner never claimed alerts once, and only past 10 minutes.
    mkdir scout/requests
    echo "{}" > scout/requests/20261006T120000-review.json
    fresh="$(${relay}/bin/scout-relay-research)"
    [ -z "$fresh" ] || { echo "FAIL: alerted on a fresh request: $fresh"; exit 1; }
    touch -d '20 min ago' scout/requests/20261006T120000-review.json
    echo "{}" > scout/requests/20261006T120500-review.json.tmp
    touch -d '20 min ago' scout/requests/20261006T120500-review.json.tmp
    alert="$(${relay}/bin/scout-relay-research)"
    echo "$alert" | grep -q "request 20261006T120000-review is still waiting"
    [ "$(echo "$alert" | grep -c waiting)" = 1 ] || { echo "FAIL: expected one alert: $alert"; exit 1; }
    again="$(${relay}/bin/scout-relay-research)"
    [ -z "$again" ] || { echo "FAIL: alerted twice: $again"; exit 1; }
    touch $out
  ''
