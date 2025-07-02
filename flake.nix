{
  description = "NixOS configuration of Noam Stolero";

  # All outputs for the system (configs)
  outputs = {
    home-manager,
    nixpkgs,
    flake-parts,
    self,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [
        inputs.treefmt-nix.flakeModule
        ./pre-commit-hooks.nix
        ./packages
      ];

      flake = {
        nixosConfigurations = import ./hosts/nixos_hosts.nix {inherit inputs nixpkgs;};

        # SD Image generation for Raspberry Pi
        # Build with: nix build .#sdImages.naspi
        sdImages = let
          nixos = self.nixosConfigurations;
        in {
          naspi = nixos.naspi.config.system.build.sdImage;
        };

        homeConfigurations = {
          naspi-raspbian = home-manager.lib.homeManagerConfiguration {
            pkgs = inputs.nixpkgs.legacyPackages."aarch64-linux";
            modules = [
              ./hosts/naspi/home.nix
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
      };

      perSystem = {
        inputs',
        config,
        pkgs,
        ...
      }: {
        devShells.default = pkgs.mkShell {
          packages = [
            inputs'.agenix.packages.default
            inputs'.nixos-anywhere.packages.default
            config.treefmt.build.wrapper
            pkgs.git
            pkgs.nh
            pkgs.nodePackages.prettier
            pkgs.zsh
            pkgs.nix-output-monitor
          ];
          name = "dots";
          DIRENV_LOG_FORMAT = "";
          shellHook = ''
            ${config.pre-commit.installationScript}
          '';
        };

        # configure treefmt
        treefmt = {
          projectRootFile = "flake.nix";

          programs = {
            alejandra.enable = true;
            black.enable = true;
            deadnix.enable = false;
            shellcheck.enable = true;
            shfmt = {
              enable = true;
              indent_size = 4;
            };
          };
        };
        formatter = pkgs.alejandra;
      };
    };

  inputs = {
    # Official NixOS package source, using nixos-unstable branch here
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-fprintd-1_94_2.url = "github:NixOS/nixpkgs/0f56e3221392452f2c38e3ddf2eba03abda6bf47";

    systems.url = "github:nix-systems/default-linux";
    flake-compat.url = "github:edolstra/flake-compat";
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "flake-compat";
      };
    };

    # a tree-wide formatter
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    yazi.url = "github:sxyazi/yazi?ref=v0.4.0";
    agenix.url = "github:ryantm/agenix";

    mysecrets = {
      url = "git+ssh://git@github.com/noamsto/nix-secrets.git";
      flake = false;
    };

    # Xremap for remapping keys
    xremap = {
      url = "github:xremap/nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:pjones/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    hyprland.url = "github:hyprwm/Hyprland";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };
    hyprlock = {
      url = "github:hyprwm/hyprlock";
      inputs = {
        nixpkgs.follows = "hyprland/nixpkgs";
        systems.follows = "hyprland/systems";
        hyprgraphics.follows = "hyprland/hyprgraphics";
        hyprutils.follows = "hyprland/hyprutils";
        hyprlang.follows = "hyprland/hyprlang";
        hyprwayland-scanner.follows = "hyprland/hyprwayland-scanner";
      };
    };
    hypridle = {
      url = "github:hyprwm/hypridle";
      inputs = {
        nixpkgs.follows = "hyprland/nixpkgs";
        systems.follows = "hyprland/systems";
        hyprlang.follows = "hyprland/hyprlang";
        hyprutils.follows = "hyprland/hyprutils";
        hyprland-protocols.follows = "hyprland/hyprland-protocols";
        hyprwayland-scanner.follows = "hyprland/hyprwayland-scanner";
      };
    };
    hyprland-contrib = {
      url = "github:hyprwm/contrib";
      inputs.nixpkgs.follows = "hyprland/nixpkgs";
    };

    hyprpanel = {
      url = "github:Jas-SinghFSU/HyprPanel";
      inputs = {
        nixpkgs.follows = "hyprland/nixpkgs";
      };
    };
    matugen.url = "github:InioX/matugen?ref=v2.4.1";
    walker.url = "github:abenz1267/walker?ref=v0.8.9";

    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";

    catppuccin.url = "github:catppuccin/nix";

    mcp-hub.url = "github:ravitemer/mcp-hub";
    aicommit2 = {
      url = "github:noamsto/aicommit2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # For RPI4
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";
    nix-search-tv.url = "github:3timeslazy/nix-search-tv";

    devenv = {
      url = "github:cachix/devenv?ref=v1.6.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
