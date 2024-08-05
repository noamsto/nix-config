{
  inputs,
  nixpkgs,
  ...
}: {
  thinkpad-p14s = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
  };
}
