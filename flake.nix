{
  description = "NixOS configuration of Noam Stolero";

  # All outputs for the system (configs)
  outputs = {
    home-manager,
    nixpkgs,
    nixpkgs-stable,
    ...
  } @ inputs: let
    pkgs-linux = inputs.nixpkgs.legacyPackages.x86_64-linux;

    # This lets us reuse the code to "create" a system
    # Credits go to sioodmy on this one!
    # https://github.com/sioodmy/dotfiles/blob/main/flake.nix
    mkSystem = {
      pkgs,
      system,
      hostname,
      username,
      user_full_name,
      user_email,
    }: let
      pkgs-stable = import nixpkgs-stable {
        inherit system;
        config.allowUnfree = true;
      };
      args = {inherit pkgs-stable system hostname username user_full_name user_email inputs;};
    in
      pkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {networking.hostName = hostname;}
          # General configuration (users, networking, sound, etc)
          (./. + "/hosts/${hostname}/system.nix")
          # Hardware config (bootloader, kernel modules, filesystems, etc)
          # DO NOT USE MY HARDWARE CONFIG!! USE YOUR OWN!!
          (./. + "/hosts/${hostname}/hardware-configuration.nix")
          home-manager.nixosModules.home-manager

          # Agenix secrets-manager
          ./secrets
          {
            home-manager = {
              useUserPackages = true;
              useGlobalPkgs = true;
              extraSpecialArgs = args;
              # Home manager config (configures programs like firefox, zsh, eww, etc)
              users.${username} = ./. + "/hosts/${hostname}/home.nix";
            };
          }

          (import ./overlays)
        ];
        specialArgs = args;
      };
  in {
    formatter.x86_64-linux = pkgs-linux.alejandra;
    nixosConfigurations = {
      thinkpad-p14s = mkSystem {
        pkgs = inputs.nixpkgs;
        system = "x86_64-linux";
        hostname = "thinkpad-p14s";
        username = "noams";
        user_full_name = "Noam Stolero";
        user_email = "stellern@gmail.com";
      };
    };

    homeConfigurations = {
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
        };
      };
    };
  };

  # the nixConfig here only affects the flake itself, not the system configuration!
  nixConfig = {
    experimental-features = ["nix-command" "flakes"];

    substituters = [
      # replace official cache with a mirror located in China
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://cache.nixos.org"
    ];

    # nix community's cache server
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://devenv.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
    ];
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
