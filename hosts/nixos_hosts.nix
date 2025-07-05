{
  inputs,
  nixpkgs,
  ...
}: let
  inherit (inputs) nixos-raspberrypi;
in {
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

  naspi = nixos-raspberrypi.lib.nixosSystem {
    specialArgs = {
      inherit inputs;
      inherit nixos-raspberrypi;
    };
    system = "aarch64-linux";
    modules = [
      ./naspi
    ];
  };
}
