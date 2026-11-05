# NixOS system configurations
{inputs, ...}: let
  inherit (inputs) nixpkgs self;
in {
  flake = {
    nixosConfigurations = {
      example = nixpkgs.lib.nixosSystem {modules = [(import ../hosts/example {inherit self;})];};
      # nixos-raspberrypi's own nixosSystem: it injects the specialArg its board
      # modules need and evaluates against its own (cached) nixpkgs.
      example-rpi4 = inputs.nixos-raspberrypi.lib.nixosSystem {modules = [(import ../hosts/example-rpi4 {inherit self;})];};
    };
  };
}
