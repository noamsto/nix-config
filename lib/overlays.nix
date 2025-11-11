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
    nur = import inputs.nur {
      nurpkgs = final;
      pkgs = final;
    };
  })

  (final: _: let
    inherit (final.stdenv.hostPlatform) system;
  in {
    inherit (inputs.nixpkgs-fprintd-1_94_2.legacyPackages.${system}) fprintd;
  })

  # Override nix-search-tv with flake version
  (final: _: {
    nix-search-tv = inputs.nix-search-tv.packages.${final.stdenv.hostPlatform.system}.default;
  })

  # Add claude-code from flake
  (final: _: {
    claude-code = inputs.claude-code.packages.${final.stdenv.hostPlatform.system}.default;
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
            --add-flags "--disable-accelerated-2d-canvas" \
            --add-flags "--disable-features=WaylandWpColorManagerV1"
        '';
    });
  })
]
