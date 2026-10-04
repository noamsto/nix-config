# Direct regression suite for the deslop push guard
# (../claude-code/deslop-guard.sh) — its non-source short-circuit and the
# retained deny path. The hookyard routing that installs it is covered
# separately by ../claude-code/default.nix.
{pkgs}:
pkgs.runCommand "deslop-guard-check" {
  nativeBuildInputs = with pkgs; [bats bash jq gnugrep gnused coreutils git findutils];
} ''
  export HOME=$TMPDIR
  GUARD=${./deslop-guard.sh} bats --tap ${./tests/deslop-guard.bats}
  touch $out
''
