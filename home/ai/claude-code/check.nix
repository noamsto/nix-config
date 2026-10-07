# Direct regression suites for two helpers: the deslop push guard
# (../claude-code/deslop-guard.sh) — its non-source short-circuit and the
# retained deny path — and the caller --settings merge
# (../claude-code/settings-merge.sh). The hookyard routing that installs the
# guard is covered separately by ../claude-code/default.nix.
{pkgs}:
pkgs.runCommand "deslop-guard-check" {
  nativeBuildInputs = with pkgs; [bats bash jq gnugrep gnused coreutils git findutils];
} ''
  export HOME=$TMPDIR
  GUARD=${./deslop-guard.sh} bats --tap ${./tests/deslop-guard.bats}
  MERGE=${./settings-merge.sh} bats --tap ${./tests/settings-merge.bats}
  touch $out
''
