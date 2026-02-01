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
        ./flake-modules/development.nix
        ./flake-modules/nixos-systems.nix
        ./flake-modules/home-manager.nix
        ./packages
      ];

      # perSystem configuration is now handled in flake-modules/development.nix

      flake = {
        # Raspberry Pi host configurations metadata
        # Used by deployment scripts for metadata-driven operations
        rpiHosts = import ./lib/rpi-hosts.nix;
      };
    };

  # SYNC: Keep in sync with lib/caches.nix (nixConfig can't use imports)
  nixConfig = {
    substituters = [
      "https://cache.nixos.org"
      "https://cache.flakehub.com"
      "https://cache.determinate.systems"
      "https://hyprland.cachix.org"
      "https://vicinae.cachix.org"
      "https://claude-code.cachix.org"
      "https://nixpkgs-unfree.cachix.org"
      "https://nix-community.cachix.org"
      "https://yazi.cachix.org"
      "https://nixos-raspberrypi.cachix.org"
      "https://numtide.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cache.determinate.systems:GsijX2T9bK2pwsOeNFzBSIA2FKGJ/puvIqCBHQC3HsU="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
      "yazi.cachix.org-1:Dcdz63NZKfvUCbDGngQDAZq6kOroIrFoyO064uvLh8k="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    # === CORE SYSTEM ===
    # Use nixos-unstable for latest packages and features
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";

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

    xremap = {
      url = "github:xremap/nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprdynamicmonitors.url = "github:fiffeek/hyprdynamicmonitors";

    # === APPLICATION PACKAGES ===
    # Pinned versions for stability - update quarterly
    vicinae.url = "github:vicinaehq/vicinae"; # Pinned to stable release (Nov 6, 2025)

    noctalia = {
      url = "github:noamsto/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia-plugins = {
      url = "github:noctalia-dev/noctalia-plugins";
      flake = false;
    };

    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # === SPECIALIZED HARDWARE ===
    # Monthly updates for hardware support
    # Pinned to d0e2a7a (Nov 1) - Last known working with cached kernel & auth
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/d0e2a7a36b08e2049e3024bc23ab391ca9de454c";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # === SECURITY & SECRETS ===
    # Security-critical - immediate updates
    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
      # Don't follow nixpkgs - leads to cache misses for FlakeHub Cache artifacts
    };

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

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-search-tv = {
      url = "github:3timeslazy/nix-search-tv";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents.url = "github:numtide/llm-agents.nix/";

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
    };

    wrappers.url = "github:Lassulus/wrappers";

    # === LOCAL APPLICATIONS ===
    go-bills = {
      url = "git+ssh://git@github.com/noamsto/go-bills.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
