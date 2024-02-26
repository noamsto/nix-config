{
  description = "NixOS configuration of Ryan Yin";

  # ...

  inputs = {
    # Official NixOS package source, using nixos-unstable branch here
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-old.url = "github:nixos/nixpkgs/?rev=a2b7d875387e245300e3e4f8e6691f18cdcf9aa1";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-23.05";

    catppuccin-hyprland = {
      url = "github:catppuccin/hyprland";
      flake = false;
    };

    catpuccin-bottom = {
      url = "github:catppuccin/bottom";
      flake = false;
    };

    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/";
      # The `follows` keyword in inputs is used for inheritance.
      # Here, `inputs.nixpkgs` of home-manager is kept consistent with the `inputs.nixpkgs` of the current flake,
      # to avoid problems caused by different versions of nixpkgs dependencies.
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

    # AstroNvim is an aesthetic and feature-rich neovim config.
    astronvim = {
      url = "github:AstroNvim/AstroNvim/v3.43.4";
      flake = false;
    };

    # Used for better git diffs
    delta = {
      url = "github:dandavison/delta?rev=7375f7a165dabe430e12d531fedd84bb3a027c6b";
      flake = false;
    };

    # sddm theme
    sddm-sugar-dark = {
      url = "github:MarianArlt/sddm-sugar-dark";
      flake = false;
    };

    # Xremap for remapping keys
    xremap.url = "github:xremap/nix-flake";

    # Hyprland
    hyprland.url = "github:hyprwm/Hyprland";
    hyprland-plugins.url = "github:hyprwm/hyprland-plugins";
    nix-colors.url = "github:misterio77/nix-colors";
    # add ags
    ags.url = "github:Aylur/ags";
  };

  # All outputs for the system (configs)
  outputs = {
    home-manager,
    nixpkgs,
    nixpkgs-stable,
    nixpkgs-old,
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
      pkgs-unstable = import nixpkgs {
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
            nixpkgs.overlays = [
              (final: prev: {
                # Broken packages
                inherit (pkgs-stable) azure-cli;

                # Use tmux fork until this issue is closed: https://github.com/tmux/tmux/issues/2705
                tmux = prev.tmux.overrideAttrs (prviousAttrs: {
                  version = "next-3.4";
                  patches = [];
                  src = prev.fetchFromGitHub {
                    owner = "tiagovla";
                    repo = "tmux";
                    rev = "b6be05261a4d92cf41156ccbf5f41d19ca18665f";
                    sha256 = "sha256-w0Z2I+b95RYGrNvFqXbUwkcTTDUvi7RawuAgz5nGsl0=";
                  };
                });
                # Fix slack screen sharing following: https://github.com/flathub/com.slack.Slack/issues/101#issuecomment-1807073763
                slack = prev.slack.overrideAttrs (previousAttrs: {
                  installPhase =
                    previousAttrs.installPhase
                    + ''
                      sed -i'.backup' -e 's/,"WebRTCPipeWireCapturer"/,"LebRTCPipeWireCapturer"/' $out/lib/slack/resources/app.asar

                    '';
                });
              })
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
      noams-barracuda-hypr = mkSystem {
        pkgs = inputs.nixpkgs;
        system = "x86_64-linux";
        hostname = "noams-barracuda-hypr";
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
      # replace official cache with a mirror located in China
      # "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://cache.nixos.org"
      # "https://anyrun.cachix.org"
      "https://hyprland.cachix.org"
    ];

    # nix community's cache server
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://devenv.cachix.org"
      # "https://nixpkgs-wayland.cachix.org"
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
