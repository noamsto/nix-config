# Direct regression suite for the secret-read guard itself, independent of the
# pi hookyard layer (../pi/guards-check.nix covers that routing separately).
{pkgs}:
pkgs.runCommand "agent-hooks-check" {
  nativeBuildInputs = with pkgs; [bats bash jq gnugrep gnused coreutils];
} ''
  export HOME=$TMPDIR
  GUARD=${./secret-read-guard.sh} bats --tap ${./tests/secret-read-guard.bats}
  touch $out
''
