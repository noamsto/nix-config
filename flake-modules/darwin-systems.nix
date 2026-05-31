# nix-darwin (macOS) system configurations
{inputs, ...}: let
  mkDarwin = hostModule:
    inputs.nix-darwin.lib.darwinSystem {
      modules = [hostModule];
      specialArgs = {
        inherit inputs;
        inherit (inputs) self;
      };
    };
in {
  flake.darwinConfigurations = {
    mbp-m4-pro = mkDarwin ../hosts/mbp-m4-pro;
  };
}
