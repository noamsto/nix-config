{
  description = "NixOS configuration of Noam Stolero";

  nixConfig = {
    substituters = [
      "https://cache.nixos.org"
      "https://hyprland.cachix.org"
      "https://walker.cachix.org"
      "https://walker-git.cachix.org"
      "https://nixpkgs-unfree.cachix.org"
      "https://nix-community.cachix.org"
      "https://devenv.cachix.org"
      "https://yazi.cachix.org"
      "https://nixos-raspberrypi.cachix.org"
      "https://claude-code.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM="
      "walker-git.cachix.org-1:vmC0ocfPWh0S/vRAQGtChuiZBTAe4wiKDeyyXM0/7pM="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
      "yazi.cachix.org-1:Dcdz63NZKfvUCbDGngQDAZq6kOroIrFoyO064uvLh8k="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
    ];
  };

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

        # RPI4 Installer configuration (following nvmd pattern)
        # Build with: nix build .#rpi4-installer
        rpi4-installer = self.nixosConfigurations.rpi4-installer.config.system.build.sdImage;

        # Standard RPI4 Image using nixos-generators (NixOS wiki approach)
        # Build with: nix build .#rpi4-standard-image
        rpi4-standard-image = inputs.nixos-generators.nixosGenerate {
          system = "aarch64-linux";
          specialArgs = {inherit inputs;};
          modules = [
            ./hosts/rpi4-standard/image.nix
          ];
          format = "sd-aarch64";
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
            ruff.enable = true;
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

    walker = {
      url = "github:abenz1267/walker";
    };

    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

    nix-search-tv.url = "github:3timeslazy/nix-search-tv";

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code.url = "github:sadjow/claude-code-nix";
  };
}
