{
  description = "NixOS configuration of Ryan Yin";

  # ...

  inputs = {
    # Official NixOS package source, using nixos-unstable branch here
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-23.05";

    hyprland = {
      url = "github:hyprwm/Hyprland";
      # build with your own instance of nixpkgs
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin-hyprland = {
      url = "github:catppuccin/hyprland";
      flake = false;
    };

    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-23.05";
      # The `follows` keyword in inputs is used for inheritance.
      # Here, `inputs.nixpkgs` of home-manager is kept consistent with the `inputs.nixpkgs` of the current flake,
      # to avoid problems caused by different versions of nixpkgs dependencies.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Alacritty themes overlay
    alacritty-theme.url = "github:alexghr/alacritty-theme.nix";

    agenix.url = "github:ryantm/agenix";

    mysecrets = {
      url = "git+ssh://git@github.com/noamsto/nix-secrets.git?shallow=1";
      flake = false;
    };

    # NvChad feature-rich neovim config.
    # nvchad = {
    #   url = "github:NvChad/NvChad/";
    #   flake = false;
    # };
  };

  # All outputs for the system (configs)
  outputs = {
    home-manager,
    nixpkgs,
    nixpkgs-stable,
    ...
  } @ inputs: let
    pkgs-linux = inputs.nixpkgs.legacyPackages.x86_64-linux;
    lib = nixpkgs.lib;

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
        system = system;
        config.allowUnfree = true;
      };
      args = {inherit pkgs-stable system hostname username user_full_name user_email;} // inputs;
    in
      pkgs.lib.nixosSystem {
        system = system;
        modules = [
          {networking.hostName = hostname;}
          # General configuration (users, networking, sound, etc)
          (./. + "/hosts/${hostname}/system.nix")
          # Hardware config (bootloader, kernel modules, filesystems, etc)
          # DO NOT USE MY HARDWARE CONFIG!! USE YOUR OWN!!
          (./. + "/hosts/${hostname}/hardware-configuration.nix")
          home-manager.nixosModules.home-manager
          ./secrets
          {
            home-manager = {
              useUserPackages = true;
              useGlobalPkgs = true;
              extraSpecialArgs = args;
              # Home manager config (configures programs like firefox, zsh, eww, etc)
              users.${username} = ./. + "/hosts/${hostname}/home.nix";
            };
            nixpkgs.overlays = [
              inputs.alacritty-theme.overlays.default
            ];
          }
        ];
        specialArgs = args;
      };
  in {
    nixosConfigurations = {
      # Now, defining a new system is can be done in one line
      #                                     Architecture   Hostname
      nixos-test = mkSystem inputs.nixpkgs "x86_64-linux" "nixos-test";
      noams-barracuda = mkSystem {
        pkgs = inputs.nixpkgs;
        system = "x86_64-linux";
        hostname = "noams-barracuda";
        username = "noams";
        user_full_name = "Noam Stolero";
        user_email = "nstolero@barracuda.com";
      };
    };
    formatter.x86_64-linux = pkgs-linux.alejandra;
  };

  # the nixConfig here only affects the flake itself, not the system configuration!
  nixConfig = {
    experimental-features = ["nix-command" "flakes"];

    substituters = [
      "https://cache.nixos.org"
      # "https://anyrun.cachix.org"
      "https://hyprland.cachix.org"
    ];

    # nix community's cache server
    extra-substituters = [
      "https://nix-community.cachix.org"
      # "https://nixpkgs-wayland.cachix.org"
      https://devenv.cachix.org
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      # "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
      # "anyrun.cachix.org-1:pqBobmOjI7nKlsUMV25u9QHa9btJK65/C8vnO3p346s="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };
}
