{pkgs, ...}: let
  withLockState = import ./aegis-lock-scripts.nix {inherit pkgs;};
in {
  home.packages = [
    (withLockState "aegis-lock-recover")
    (withLockState "aegis-lock-guard")
  ];
}
