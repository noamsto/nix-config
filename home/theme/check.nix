# Direct bats regression suite for the shared theme-apply library: overlapping
# runs must not empty app configs, btop keeps its settings when replacing a
# read-only file, and theme_apply_lock serialises runs.
{pkgs}:
pkgs.runCommand "theme-apply-check" {
  nativeBuildInputs = with pkgs; [
    bats
    bash
    jq
    flock
    gnugrep
    gnused
    gawk
    coreutils
  ];
} ''
  export HOME=$TMPDIR
  export THEME_APPLY_LIB=${./lib/theme-apply.sh}
  bats --tap ${./tests/theme-apply.bats}
  touch $out
''
