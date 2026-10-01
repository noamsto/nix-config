# Regression suite for xresources-apply: drives a real Xvfb server + xrdb, so
# the assertions see the fresh X resource database a restarted XWayland presents.
{pkgs}:
pkgs.runCommand "xresources-apply-check" {
  nativeBuildInputs = with pkgs; [
    bats
    bash
    coreutils
    gnused
    xrdb
    xvfb
  ];
} ''
  export XRAPPLY=${./scripts/xresources-apply.sh}
  bats --tap ${./tests/xresources-apply.bats}
  touch $out
''
