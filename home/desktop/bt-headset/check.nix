# Regression suite for the bt-headset-mode jq filters and script control flow,
# run against a synthetic pw-dump fixture and stubbed CLIs.
{pkgs}:
pkgs.runCommand "bt-headset-mode-check" {
  nativeBuildInputs = with pkgs; [
    bats
    bash
    jq
    coreutils
    gnused
    gnugrep
  ];
} ''
  export BT_PLAN_JQ=${./plan.jq}
  export BT_NODES_JQ=${./nodes.jq}
  export BT_SCRIPT=${./bt-headset-mode.sh}
  export FIXTURE=${./tests/pw-dump-two-headsets.json}
  bats --tap ${./tests/bt-headset-mode.bats}
  touch $out
''
