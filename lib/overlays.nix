# Reusable overlays for both NixOS and standalone Home Manager
inputs: [
  # Expose stable nixpkgs for selective package pinning
  (final: _: {
    stable = import inputs.nixpkgs-stable {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };
  })

  # Override nix-search-tv with flake version
  (final: _: {
    nix-search-tv = inputs.nix-search-tv.packages.${final.stdenv.hostPlatform.system}.default;
  })

  # Add LLM agents from flake
  (final: _prev: {
    inherit (inputs.llm-agents.packages.${final.stdenv.hostPlatform.system}) claude-code gemini-cli codex cursor-agent crush happy-coder;
    # Amp with process.title wrapper so it shows as "amp" instead of "node" in ps
    amp = let
      upstream = inputs.llm-agents.packages.${final.stdenv.hostPlatform.system}.amp;
      mainJs = "${upstream}/lib/node_modules/@sourcegraph/amp/dist/main.js";
      loader = final.writeText "amp-loader.mjs" ''
        process.title = 'amp';
        await import('${mainJs}');
      '';
    in
      final.writeShellScriptBin "amp" ''
        export PATH="${final.lib.makeBinPath [final.ripgrep]}:$PATH"
        export AMP_SKIP_UPDATE_CHECK=1
        exec ${final.nodejs_24}/bin/node ${loader} "$@"
      '';
  })

  # Add mcp-servers-nix overlay
  inputs.mcp-servers-nix.overlays.default

  # Add custom packages from this flake
  (final: _: {
    inherit (inputs.self.packages.${final.stdenv.hostPlatform.system}) tavily-mcp;
  })

  # Enable AMD GPU monitoring in btop via ROCm
  (_final: prev: {
    btop = prev.btop.override {rocmSupport = true;};
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
