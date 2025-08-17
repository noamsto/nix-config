# Home Manager configurations
{inputs, ...}: {
  flake.homeConfigurations = {
    naspi-raspbian = inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.nixpkgs.legacyPackages."aarch64-linux";
      modules = [
        ../hosts/naspi/home.nix
      ];
      extraSpecialArgs = {
        inherit inputs;
        osConfig = {
          username = "noams";
          user-full-name = "Noam Stolero";
          email = "noamstolero@gmail.com";
          hostname = "naspi";
          desktop.mode = "none";
          profile = "personal";
        };
      };
    };
  };
}
