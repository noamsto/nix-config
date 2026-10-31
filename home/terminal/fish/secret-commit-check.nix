# Direct regression suite for the secret-commit fish function and its jq
# sops-diff filter. The function body is rendered exactly as Home Manager
# installs it (see secret-commit.nix).
#
# The suite also drives a real sops round trip on a throwaway age key, so the
# re-encryption behaviour the filter reasons about is exercised in the build,
# not assumed.
{pkgs}: let
  secretCommitFunction = import ./secret-commit.nix {inherit pkgs;};
in
  pkgs.runCommand "secret-commit-check" {
    nativeBuildInputs = with pkgs; [
      bats
      bash
      fish
      git
      jq
      yq
      sops
      age
      gnugrep
      gnused
      coreutils
    ];
  } ''
    export HOME=$TMPDIR
    export SECRET_COMMIT_FUNCTION=${pkgs.writeText "secret-commit.fish" secretCommitFunction}
    export SECRET_COMMIT_FILTER=${./secret-commit.jq}
    bats --tap ${./tests/secret-commit.bats}
    touch $out
  ''
