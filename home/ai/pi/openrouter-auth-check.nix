# Regression suite for openrouter-auth.sh (the pi openrouter auth.json upsert);
# the activation step that runs it is wired in ./default.nix.
{pkgs}:
pkgs.runCommand "pi-openrouter-auth-check" {
  nativeBuildInputs = with pkgs; [bats bash jq coreutils gnugrep diffutils procps];
} ''
  export HOME=$TMPDIR
  SCRIPT=${./openrouter-auth.sh} bats --tap ${./tests/openrouter-auth.bats}
  touch $out
''
