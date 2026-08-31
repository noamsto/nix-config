{
  description = "NixOS configuration of Noam Stolero";
  # All outputs for the system (configs)
  outputs = {flake-parts, ...} @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      imports = [
        ./flake-modules/development.nix
        ./flake-modules/nixos-systems.nix
        ./flake-modules/home-manager.nix
        ./flake-modules/darwin-systems.nix
        ./packages
      ];

      # perSystem configuration is now handled in flake-modules/development.nix

      flake = {};
    };

  # SYNC: Keep in sync with lib/caches.nix (nixConfig can't use imports)
  nixConfig = {
    substituters = [
      "https://cache.nixos.org"
      "https://cache.flakehub.com"
      "https://hyprland.cachix.org"
      "https://vicinae.cachix.org"
      "https://nix-amd-ai.cachix.org"
      "https://wtc.cachix.org"
      "https://nixpkgs-unfree.cachix.org"
      "https://nix-community.cachix.org"
      "https://yazi.cachix.org"
      "https://noctalia.cachix.org"
      "https://lazytmux.cachix.org"

      # llm-agents.nix publishes here, NOT numtide.cachix.org
      "https://cache.numtide.com"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      "cache.flakehub.com-4:Asi8qIv291s0aYLyH6IOnr5Kf6+OF14WVjkE6t3xMio="
      "cache.flakehub.com-5:zB96CRlL7tiPtzA9/WKyPkp3A2vqxqgdgyTVNGShPDU="
      "cache.flakehub.com-6:W4EGFwAGgBj3he7c5fNh9NkOXw0PUVaxygCVKeuvaqU="
      "cache.flakehub.com-7:mvxJ2DZVHn/kRxlIaxYNMuDG1OvMckZu32um1TadOR8="
      "cache.flakehub.com-8:moO+OVS0mnTjBTcOUh2kYLQEd59ExzyoW1QgQ8XAARQ="
      "cache.flakehub.com-9:wChaSeTI6TeCuV/Sg2513ZIM9i0qJaYsF+lZCXg0J6o="
      "cache.flakehub.com-10:2GqeNlIp6AKp4EF2MVbE1kBOp9iBSyo0UPR9KoR0o1Y="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
      "nix-amd-ai.cachix.org-1:F4OU4vw/lV2oiG6SBHZ+nqjl4EFJuqI4X9A7pvaBmhQ="
      "wtc.cachix.org-1:rXr2jpSoAtqezDz8xK/gPMjH2Rgyda0zOErfk3N5WnI="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
      "yazi.cachix.org-1:Dcdz63NZKfvUCbDGngQDAZq6kOroIrFoyO064uvLh8k="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "lazytmux.cachix.org-1:8P28D3LZAKqPlkEGKzRRU9gon3rgBv4u8/4VWRn6TCg="

      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
    trusted-substituters = ["https://cache.flakehub.com"];
  };

  inputs = {
    # === CORE SYSTEM ===
    # Use nixos-unstable for latest packages and features
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";

    systems.url = "github:nix-systems/default-linux";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # === macOS (nix-darwin) ===
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Makes nix-installed .app bundles show up in Spotlight/Launchpad by
    # replacing their /nix/store symlinks with proper macOS aliases.
    # NOTE: do NOT make its nixpkgs follow ours — mac-app-util is a Common Lisp
    # app and pins a known-good nixpkgs; forcing our unstable nixpkgs breaks its
    # SBCL/fare-quasiquote build on aarch64-darwin. The extra nixpkgs is the cost.
    mac-app-util.url = "github:hraban/mac-app-util";

    # Homebrew taps pinned for nix-homebrew (flake = false: plain source trees)
    homebrew-core = {
      url = "github:Homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:Homebrew/homebrew-cask";
      flake = false;
    };
    # Third-party tap for SwipeAerospace (3-finger swipe → AeroSpace workspace).
    homebrew-mediosz = {
      url = "github:mediosz/homebrew-tap";
      flake = false;
    };
    # Upstream tap for AeroSpace itself (Developer ID-signed build).
    homebrew-nikitabobko = {
      url = "github:nikitabobko/homebrew-tap";
      flake = false;
    };

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

    hyprdynamicmonitors = {
      url = "github:fiffeek/hyprdynamicmonitors";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vicinae = {
      url = "github:vicinaehq/vicinae/v0.27.5";
    };

    # Argo CD terminal UI. nixpkgs lags upstream, so track the flake directly.
    # Held at the last rev whose test suite passes: 2.18.0 (#266) broke
    # TestEventsCommand_Off_ClosesPaneAndStopsAutoOpen, which fails the package
    # build. Unpin once upstream is green again.
    argonaut = {
      url = "github:darksworm/argonaut/4caae2c0e29c5ada8c840af6718bdcf3eeb57baa";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      # Pinned to last v4 rev. v5 is a breaking rewrite (programs.noctalia-shell →
      # programs.noctalia, JSON→TOML config, plugins/pluginSettings dropped from the
      # module). Unpin when home/desktop/noctalia is migrated to the v5 schema.
      url = "github:noctalia-dev/noctalia-shell/5311e14d2000af2f523789c76a3d869dcb42f130";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    aegis-lock.url = "https://flakehub.com/f/noamsto/aegis-lock/*.tar.gz";

    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-desktop = {
      url = "github:aaddrick/claude-desktop-debian";
    };

    # === SPECIALIZED HARDWARE ===
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      # Track master until a tag past v1.0.0 ships: v1.0.0 sets the removed
      # `boot.bootspec.enable`, which current nixpkgs rejects (bootspec is now
      # always-on). flake.lock pins the exact rev.
      url = "github:nix-community/lanzaboote";
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

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-search-tv = {
      url = "github:3timeslazy/nix-search-tv";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Packaged Firefox add-ons (rycee/nur-expressions) for declarative,
    # per-profile extension installs — used by the marionette automation profile.
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wrappers.url = "github:Lassulus/wrappers";

    lazytmux = {
      url = "github:noamsto/lazytmux";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # agent-smith CC plugin engine (extractor/analyst/applier binaries); the
    # plugin itself is enabled via settings.json's extraKnownMarketplaces.
    agent-smith = {
      url = "github:noamsto/agent-smith";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # resolved CC plugin binary; the plugin itself is enabled via settings.json's
    # extraKnownMarketplaces.
    resolved = {
      url = "github:noamsto/resolved";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Dispatcher agent fan-out harness: the crew bus, `dispatch`, the protocols,
    # and per-engine adapters for claude-code, codex and cursor. Extracted from
    # this repo's home/ai/claude-code/.
    # `extract` holds the initial history; drop the ref once it lands on main.
    dispatcher = {
      url = "github:noamsto/dispatcher/extract";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wtc = {
      url = "github:noamsto/wtc";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zr = {
      url = "github:noamsto/zr";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # AMD AI: XRT, XDNA plugin, FastFlowLM, Lemonade (NPU + ROCm)
    nix-amd-ai.url = "github:noamsto/nix-amd-ai";

    # Declarative Agent Skills catalog -> per-harness skill dirs (see
    # home/ai/agent-skills). Pins the upstream skill repos below so a skill set
    # only moves when the lockfile does.
    agent-skills-nix = {
      url = "github:Kyure-A/agent-skills-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Skill source. Upstream lands ~5 commits/day and reshuffles bucket folders,
    # so `nix flake update mattpocock-skills` is a deliberate act: a renamed or
    # moved skill fails the build against the allowlist rather than silently
    # vanishing from ~/.claude/skills.
    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };
  };
}
