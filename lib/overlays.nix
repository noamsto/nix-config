# Reusable overlays for both NixOS and standalone Home Manager
inputs: [
  # Expose multiple nixpkgs versions for selective package usage
  (final: _: {
    # Main unstable nixpkgs (useful for naspi to get newer packages)
    unstable = import inputs.nixpkgs {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };
    # Stable channel packages
    stable = import inputs.nixpkgs-stable {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };
  })

  # Override nix-search-tv with flake version
  (final: _: {
    nix-search-tv = inputs.nix-search-tv.packages.${final.stdenv.hostPlatform.system}.default;
  })

  # Add claude-code from flake
  (final: _: {
    inherit (inputs.llm-agents.packages.${final.stdenv.hostPlatform.system}) claude-code gemini-cli codex cursor-agent crush happy-coder;
  })

  # Add mcp-servers-nix overlay
  inputs.mcp-servers-nix.overlays.default

  # Add custom packages from this flake
  (final: _: {
    inherit (inputs.self.packages.${final.stdenv.hostPlatform.system}) tavily-mcp;
  })

  # Brave with Wayland fixes
  (final: prev: {
    brave = prev.brave.overrideAttrs (oldAttrs: {
      buildInputs = (oldAttrs.buildInputs or []) ++ [final.makeWrapper];
      postFixup =
        (oldAttrs.postFixup or "")
        + ''
          wrapProgram $out/bin/brave \
            --add-flags "--disable-features=WaylandWpColorManagerV1"
        '';
    });
  })
]
