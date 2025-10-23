# Reusable overlays for both NixOS and standalone Home Manager
inputs: [
  (final: _: {
    stable = import inputs.nixpkgs-stable {
      system = final.system;
      config.allowUnfree = true;
    };
    nur = import inputs.nur {
      nurpkgs = final;
      pkgs = final;
    };
  })

  (final: _: {
    fprintd = inputs.nixpkgs-fprintd-1_94_2.legacyPackages.${final.system}.fprintd;
  })

  # Override nix-search-tv with flake version
  (final: _: {
    nix-search-tv = inputs.nix-search-tv.packages.${final.system}.default;
  })

  # Add claude-code from flake
  (final: _: {
    claude-code = inputs.claude-code.packages.${final.system}.default;
  })

  # Add mcp-servers-nix overlay
  inputs.mcp-servers-nix.overlays.default

  # Add custom packages from this flake
  (final: _: {
    tavily-mcp = inputs.self.packages.${final.system}.tavily-mcp;
  })

  # Brave with Wayland fixes
  (final: prev: {
    brave = prev.brave.overrideAttrs (oldAttrs: {
      buildInputs = (oldAttrs.buildInputs or []) ++ [final.makeWrapper];
      postFixup =
        (oldAttrs.postFixup or "")
        + ''
          wrapProgram $out/bin/brave \
            --add-flags "--disable-accelerated-2d-canvas" \
            --add-flags "--disable-features=WaylandWpColorManagerV1"
        '';
    });
  })
]
