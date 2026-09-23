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
      "https://jovian-nixos.cachix.org"

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
      "jovian-nixos.cachix.org-1:mAWLjAxLNlfxAnozUjOqGj4AxQwCl7MXwOfu7msVlAo="

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
      url = "github:vicinaehq/vicinae";
    };

    # Argo CD terminal UI. nixpkgs lags upstream, so track the flake directly.
    # Held at the last rev whose test suite passes: 2.18.0 (#266) broke
    # TestEventsCommand_Off_ClosesPaneAndStopsAutoOpen, which fails the package
    # build. Unpin once upstream is green again.
    argonaut = {
      url = "github:darksworm/argonaut/4caae2c0e29c5ada8c840af6718bdcf3eeb57baa";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Tracks upstream's `cachix` branch, which always points at the newest commit
    # already built by their CI. Deliberately no `inputs.nixpkgs.follows`: it
    # forks the derivation hash and misses noctalia.cachix.org, which matters now
    # that the shell core is C++.
    noctalia.url = "github:noctalia-dev/noctalia/cachix";

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

    # No nixpkgs.follows: following ours forks the derivation away from the
    # one its CI built, so every rebuild compiles it from source instead of
    # substituting from lazytmux.cachix.org.
    tmux-og.url = "github:noamsto/tmux-og";

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

    # Cross-engine agent hook router. One manifest of handlers renders into
    # Claude Code's, Codex's, Cursor's and Pi's native hook config in a single
    # `hookyard install` pass, owned by home/ai/hookyard.
    hookyard = {
      url = "github:noamsto/hookyard";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        # Check-only dependency upstream; nothing here evaluates it, so
        # without this the lock carries a third home-manager revision and
        # fetches another tree on every update.
        home-manager.follows = "home-manager";
      };
    };

    # Steam Deck UI (Gaming Mode) for halo's console role. Deliberately only
    # the Steam session — `jovian.devices.steamdeck` stays off, since it would
    # pull linux-neptune over the gfx1151 kernel halo needs.
    jovian = {
      url = "github:Jovian-Experiments/Jovian-NixOS";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Dispatcher agent fan-out harness: the crew bus, `dispatch`, the protocols,
    # and per-engine adapters for claude-code, codex and cursor. Extracted from
    # this repo's home/ai/claude-code/.
    dispatcher = {
      url = "github:noamsto/dispatcher/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # No nixpkgs.follows: following ours forks the derivation away from the
    # one its CI built, so every rebuild compiles it from source instead of
    # substituting from wtc.cachix.org.
    wtc.url = "github:noamsto/wtc";

    zr = {
      url = "github:noamsto/zr";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # AMD AI: XRT, XDNA plugin, FastFlowLM, Lemonade (NPU + ROCm)
    nix-amd-ai.url = "github:noamsto/nix-amd-ai";

    # Interview study tracker served on halo. Private repo, hence git+ssh —
    # `github:` would need an access token in the daemon's nix.conf.
    prep = {
      url = "git+ssh://git@github.com/noamsto/job-search.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Telegram relay for the portfolio scout, served on halo (see
    # nixos/services/money-scout.nix and hosts/halo/default.nix).
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Web dashboard for tmux-hosted AI agents, served on halo (see
    # home/ai/houston and hosts/halo/default.nix's localProxy wiring).
    houston = {
      url = "github:noamsto/houston";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

    # Declarative Jellyfin config for halo (libraries, users, encoding) via
    # Jellarr. Pinned to our fork, which carries three changes upstream lacks:
    #   * PR #79's Jellyfin 12 auth fix — upstream still sends the X-Emby-Token
    #     header that 12.0 rejects with a 401, which Jellarr then misreads as
    #     "already up to date";
    #   * tone-mapping options (our PR #82), so HDR->SDR conversion is
    #     declarative instead of a dashboard-only setting;
    #   * per-user subtitle language and playback mode (our PR #83), so the
    #     Hebrew default is declared here rather than flipped in the web UI and
    #     lost on a from-scratch install. Upstream's v0.1.1 line already has the
    #     language half; playback mode is the piece neither line has.
    # Switch back to github:venkyr77/jellarr once all three merge.
    jellarr = {
      url = "github:noamsto/jellarr/49b15afca3e51d2fa69b398283a960c6ea421c4e";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
