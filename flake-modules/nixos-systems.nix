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
      thinkpad-p14s-g5 = mkSystem ../hosts/thinkpad-p14s-g5;
      thinkpad-p14s-g6 = mkSystem ../hosts/thinkpad-p14s-g6;
      halo = mkSystem ../hosts/halo;
      installer = mkSystem ../hosts/installer;
    };
  };
}
