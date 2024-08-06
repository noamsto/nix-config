{
  description = "NixOS configuration of Noam Stolero";

  # All outputs for the system (configs)
  outputs = {
    home-manager,
    nixpkgs,
    ...
  } @ inputs: let
    pkgs-linux = inputs.nixpkgs.legacyPackages.x86_64-linux;
  in {
    formatter.x86_64-linux = pkgs-linux.alejandra;
    nixosConfigurations = import ./hosts/nixos_hosts.nix {inherit inputs nixpkgs;};

    homeConfigurations = {
      #TODO: Add osConfig as special arg
      naspi-raspbian = home-manager.lib.homeManagerConfiguration {
        pkgs = inputs.nixpkgs.legacyPackages."aarch64-linux";
        modules = [
          ./hosts/naspi/home.nix
        ];
        extraSpecialArgs = {
          inherit inputs;
          username = "noams";
          hostname = "naspi";
          user_full_name = "Noam Stolero";
          user_email = "noamstolero@gmail.com";
          osConfig = import ./options.nix;
        };
      };
    };
  };

  inputs = {
    # Official NixOS package source, using nixos-unstable branch here
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-old.url = "github:nixos/nixpkgs/?rev=a2b7d875387e245300e3e4f8e6691f18cdcf9aa1";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-23.11";

    # For RPI4
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catpuccin-alacritty = {
      url = "github:catppuccin/alacritty";
      flake = false;
    };

    agenix.url = "github:ryantm/agenix";

    mysecrets = {
      url = "git+ssh://git@github.com/noamsto/nix-secrets.git?shallow=1";
      flake = false;
    };

    # Used for better git diffs
    delta = {
      url = "github:dandavison/delta?rev=7375f7a165dabe430e12d531fedd84bb3a027c6b";
      flake = false;
    };

    # Xremap for remapping keys
    xremap.url = "github:xremap/nix-flake";

    plasma-manager = {
      url = "github:pjones/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    k9s-catuppuccin-skins = {
      url = "github:catppuccin/k9s";
      flake = false;
    };
  };
}
