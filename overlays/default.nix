# ./overlays/default.nix
{inputs, ...}: {
  nixpkgs.overlays = import ../lib/overlays.nix inputs;
}
