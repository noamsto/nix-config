# Direct regression suites for the helpers: the deslop push guard
# (../claude-code/deslop-guard.sh) — its non-source short-circuit, tag-only push
# exemption and nothing-to-push case, plus the retained deny path — the caller
# --settings merge (settings-merge.sh) and the wrapper's --settings argument
# scan (wrapper-args.sh). The hookyard routing that installs the guard is
# covered separately by ../claude-code/default.nix.
{pkgs}:
pkgs.runCommand "deslop-guard-check" {
  nativeBuildInputs = with pkgs; [bats bash jq gnugrep gnused coreutils git findutils];
} ''
  export HOME=$TMPDIR
  GUARD=${./deslop-guard.sh} bats --tap ${./tests/deslop-guard.bats}
  MERGE=${./settings-merge.sh} bats --tap ${./tests/settings-merge.bats}
  ARGS_LIB=${./wrapper-args.sh} bats --tap ${./tests/wrapper-args.bats}
  SCRIPT=${./status-line.sh} bats --tap ${./tests/status-line.bats}
  touch $out
''
