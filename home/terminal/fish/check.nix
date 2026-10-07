# Direct regression suite for the lock-commit fish function and its jq
# lock-diff filters. The function body is rendered exactly as Home Manager
# installs it (see lock-commit.nix), so the test exercises the shipped bytes.
{pkgs}: let
  lockCommitFunction = import ./lock-commit.nix {inherit pkgs;};
in
  pkgs.runCommand "lock-commit-check" {
    nativeBuildInputs = with pkgs; [
      bats
      bash
      fish
      git
      jq
      gnugrep
      gnused
      coreutils
    ];
  } ''
    export HOME=$TMPDIR
    export LOCK_COMMIT_FUNCTION=${pkgs.writeText "lock-commit.fish" lockCommitFunction}
    export LOCK_COMMIT_FILTER=${./lock-commit.jq}
    export LOCK_COMMIT_NVIM_FILTER=${./lock-commit-nvim.jq}
    bats --tap ${./tests/lock-commit.bats}
    touch $out
  ''
