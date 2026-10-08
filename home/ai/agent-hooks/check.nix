# Direct regression suites for the secret-read, git-identity and
# pgrep-self-match guards, independent of the pi hookyard layer
# (../pi/guards-check.nix covers that routing separately).
{pkgs}:
pkgs.runCommand "agent-hooks-check" {
  nativeBuildInputs = with pkgs; [bats bash jq gnugrep gnused coreutils git];
} ''
  export HOME=$TMPDIR
  GUARD=${./secret-read-guard.sh} bats --tap ${./tests/secret-read-guard.bats}
  GUARD=${./git-identity-guard.sh} bats --tap ${./tests/git-identity-guard.bats}
  GUARD=${./pgrep-self-match-guard.sh} bats --tap ${./tests/pgrep-self-match-guard.bats}
  touch $out
''
