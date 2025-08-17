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
      "https://nixos-raspberrypi.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM="
      "walker-git.cachix.org-1:vmC0ocfPWh0S/vRAQGtChuiZBTAe4wiKDeyyXM0/7pM="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
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
            # Core NixOS configuration tools
            inputs'.agenix.packages.default
            inputs'.nixos-anywhere.packages.default
            config.treefmt.build.wrapper
            pkgs.git
            pkgs.nh
            pkgs.nodePackages.prettier
            pkgs.zsh
            pkgs.nix-output-monitor
            pkgs.just

            # Lightweight development essentials
            pkgs.jq # JSON processing (small and useful)
            pkgs.typos # Spell checker for code (lightweight)
            pkgs.tokei # Code statistics (lightweight and useful for dev-stats)
          ];
          name = "dots";
          DIRENV_LOG_FORMAT = "";
          shellHook = ''
            ${config.pre-commit.installationScript}

            # Enhanced environment setup
            export EDITOR=nvim
            export DEVELOPMENT_MODE=true

            # Add agent helper to PATH
            export PATH="${./agents}:$PATH"

            # Fish-compatible aliases and functions
            if command -v fish >/dev/null 2>&1; then
              fish -c "
                alias nix-agent='agent-helper.sh'
                alias nbuild='nom build'
                function dev-stats
                  tokei
                  echo
                  git log --oneline | wc -l | xargs echo 'Total commits:'
                end
                funcsave dev-stats
              "
            else
              # Fallback for other shells
              alias nix-agent="agent-helper.sh"
              alias nbuild="nom build"
            fi

            echo "🚀 NixOS Development Environment Ready!"
            echo "📁 Agents available: 'nix-agent help'"
            echo "📊 Project stats: 'dev-stats'"
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
    # === CORE SYSTEM ===
    # Use nixos-unstable for latest packages and features
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";

    # Specific package fixes - review quarterly
    nixpkgs-fprintd-1_94_2.url = "github:NixOS/nixpkgs/0f56e3221392452f2c38e3ddf2eba03abda6bf47";

    systems.url = "github:nix-systems/default-linux";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # === DEVELOPMENT INFRASTRUCTURE ===
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # === USER ENVIRONMENT ===
    home-manager = {
      url = "github:nix-community/home-manager/";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # === DESKTOP ENVIRONMENTS ===
    # Update monthly - stable releases
    plasma-manager = {
      url = "github:pjones/plasma-manager";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    xremap = {
      url = "github:xremap/nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # === APPLICATION PACKAGES ===
    # Pinned versions for stability - update quarterly
    walker = {
      url = "github:abenz1267/walker?ref=v0.13.14";
    };

    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mcp-hub = {
      url = "github:ravitemer/mcp-hub";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # === SPECIALIZED HARDWARE ===
    # Monthly updates for hardware support
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # === SECURITY & SECRETS ===
    # Security-critical - immediate updates
    agenix = {
      url = "github:ryantm/agenix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    mysecrets = {
      url = "git+ssh://git@github.com/noamsto/nix-secrets.git";
      flake = false;
    };

    # === UTILITIES ===
    # Stable versions - quarterly updates
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
