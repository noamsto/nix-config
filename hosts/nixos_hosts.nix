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
    modules = [
      ./thinkpad-p14s-g5
    ];
    specialArgs = {inherit inputs;};
  };

  naspi = nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      ./naspi
    ];
    specialArgs = {inherit inputs;};
  };

  # Note: Using standard nixos-generators for SD image creation
  # Run: nix build .#nixosConfigurations.naspi.config.system.build.sdImage
}
