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

  naspi-nixos = inputs.nixos-raspberrypi.lib.nixosSystem {
    modules = [
      ./naspi-nixos
    ];
    specialArgs = inputs;
  };

  naspi-installer = inputs.nixos-raspberrypi.lib.nixosInstaller {
    modules = [./naspi-nixos];
    specialArgs = inputs;
  };
}
