# NixOS system configurations
{inputs, ...}: let
  inherit (inputs) nixpkgs;

  mkSystem = hostModule:
    nixpkgs.lib.nixosSystem {
      modules = [hostModule];
      specialArgs = {
        inherit inputs;
        inherit (inputs) self;
      };
    };
in {
  flake = {
    nixosConfigurations = {
      tp-g5 = mkSystem ../hosts/tp-g5;
      tp-g6 = mkSystem ../hosts/tp-g6;
      halo = mkSystem ../hosts/halo;
      installer = mkSystem ../hosts/installer;
    };
  };
}
