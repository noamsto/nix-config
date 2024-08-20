{
  inputs,
  nixpkgs,
  ...
}: {
  thinkpad-p14s = nixpkgs.lib.nixosSystem {
    modules = [./thinkpad-p14s];
    specialArgs = {inherit inputs;};
  };
  thinkpad-p14s-g5 = nixpkgs.lib.nixosSystem {
    modules = [./thinkpad-p14s-g5];
    specialArgs = {inherit inputs;};
  };
}
