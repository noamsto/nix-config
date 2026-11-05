# NixOS system configurations
{inputs, ...}: let
  inherit (inputs) nixpkgs self;
in {
  flake = {
    nixosConfigurations = {
      example = nixpkgs.lib.nixosSystem {modules = [(import ../hosts/example {inherit self;})];};
    };
  };
}
