# Direct regression suite for the lock-commit fish function and its jq
# lock-diff filters. The function body is rendered exactly as Home Manager
# installs it (see lock-commit.nix), with a sample watch list in place of the
# host's configured one.
{pkgs}: let
  inherit (pkgs) lib;
  lockCommitFunction = import ./lock-commit.nix {
    inherit pkgs lib;
    watchedInputs = [
      {
        input = "mysecrets";
        glob = "*.age";
      }
      {
        input = "other";
        glob = "docs/*.md";
      }
    ];
  };
  lockCommitFunctionUnwatched = import ./lock-commit.nix {
    inherit pkgs lib;
    watchedInputs = [];
  };
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
    export LOCK_COMMIT_FUNCTION_UNWATCHED=${pkgs.writeText "lock-commit-unwatched.fish" lockCommitFunctionUnwatched}
    export LOCK_COMMIT_FILTER=${./lock-commit.jq}
    bats --tap ${./tests/lock-commit.bats}
    touch $out
  ''
