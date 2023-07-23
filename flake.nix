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
  };

  # All outputs for the system (configs)
  outputs = {
    home-manager,
    nixpkgs,
    nur,
    ...
  } @ inputs: let
    system = "x86_64-linux"; #current system
    pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    lib = nixpkgs.lib;

    # This lets us reuse the code to "create" a system
    # Credits go to sioodmy on this one!
    # https://github.com/sioodmy/dotfiles/blob/main/flake.nix
    mkSystem = pkgs: system: hostname:
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
          {
            home-manager = {
              useUserPackages = true;
              useGlobalPkgs = true;
              extraSpecialArgs = {inherit inputs;};
              # Home manager config (configures programs like firefox, zsh, eww, etc)
              users.noams = ./. + "/hosts/${hostname}/home.nix";
            };
            nixpkgs.overlays = [
              inputs.alacritty-theme.overlays.default
            ];
          }
        ];
        specialArgs = {inherit inputs;};
      };
  in {
    nixosConfigurations = {
      # Now, defining a new system is can be done in one line
      #                                Architecture   Hostname
      nixos-test = mkSystem inputs.nixpkgs "x86_64-linux" "nixos-test";
      noams-barracuda = mkSystem inputs.nixpkgs "x86_64-linux" "noams-barracuda";
    };
    formatter.${system} = pkgs.alejandra;
  };
}
