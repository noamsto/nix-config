# NixOS system configurations
{inputs, ...}: let
  inherit (inputs) nixpkgs;
in {
  flake = {
    nixosConfigurations = {
      thinkpad-p14s = nixpkgs.lib.nixosSystem {
        modules = [
          ../hosts/thinkpad-p14s
        ];
        specialArgs = {
          inherit inputs;
          inherit (inputs) self;
        };
      };

      thinkpad-p14s-g5 = nixpkgs.lib.nixosSystem {
        modules = [
          ../hosts/thinkpad-p14s-g5
        ];
        specialArgs = {
          inherit inputs;
          inherit (inputs) self;
        };
      };
    };
  };
}
