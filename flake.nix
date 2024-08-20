{
  description = "NixOS configuration of Noam Stolero";

  # All outputs for the system (configs)
  outputs = {
    home-manager,
    nixpkgs,
    flake-parts,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [
        inputs.flake-parts.flakeModules.easyOverlay
        inputs.treefmt-nix.flakeModule
        ./pre-commit-hooks.nix
      ];

      perSystem = {
        inputs',
        config,
        pkgs,
        ...
      }: {
        devShells.default = pkgs.mkShell {
          packages = [
            inputs'.agenix.packages.default
            config.treefmt.build.wrapper
            pkgs.git
            pkgs.nodePackages.prettier
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
      flake = {
        nixosConfigurations = import ./hosts/nixos_hosts.nix {inherit inputs nixpkgs;};

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
                profile.type = "personal";
              };
            };
          };
        };
      };
    };

  inputs = {
    # Official NixOS package source, using nixos-unstable branch here
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-old.url = "github:nixos/nixpkgs/?rev=a2b7d875387e245300e3e4f8e6691f18cdcf9aa1";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-23.11";

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

    # Used for better git diffs for theme
    delta = {
      url = "github:dandavison/delta?ref=0.17.0";
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

    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };
    hyprlock = {
      url = "github:hyprwm/hyprlock";
      inputs = {
        hyprlang.follows = "hyprland/hyprlang";
        hyprutils.follows = "hyprland/hyprutils";
        nixpkgs.follows = "hyprland/nixpkgs";
        systems.follows = "hyprland/systems";
      };
    };
    hypridle = {
      url = "github:hyprwm/hypridle";
      inputs = {
        hyprlang.follows = "hyprland/hyprlang";
        hyprutils.follows = "hyprland/hyprutils";
        nixpkgs.follows = "hyprland/nixpkgs";
        systems.follows = "hyprland/systems";
      };
    };

    # add ags
    ags.url = "github:Aylur/ags";
    hyprpanel = {
      url = "github:noamsto/HyprPanel?ref=fix-flake-build";
      inputs = {
        nixpkgs.follows = "hyprland/nixpkgs";
        ags.follows = "ags";
      };
    };

    walker.url = "github:abenz1267/walker";
    matugen = {
      url = "github:InioX/matugen";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "hyprland/systems";
      };
    };
  };
}
