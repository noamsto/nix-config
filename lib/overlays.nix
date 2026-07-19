# Reusable overlays for both NixOS and standalone Home Manager
inputs: [
  (final: _: {
    stable = import inputs.nixpkgs-stable {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };
  })

  (final: _: {
    nix-search-tv = inputs.nix-search-tv.packages.${final.stdenv.hostPlatform.system}.default;
    wtc = inputs.wtc.packages.${final.stdenv.hostPlatform.system}.default;
    zr = inputs.zr.packages.${final.stdenv.hostPlatform.system}.default;
    argonaut = inputs.argonaut.packages.${final.stdenv.hostPlatform.system}.default;
  })

  (final: _prev: {
    inherit (inputs.llm-agents.packages.${final.stdenv.hostPlatform.system}) claude-code cursor-agent oh-my-opencode opencode pi;
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

  inputs.mcp-servers-nix.overlays.default

  # Firefox add-ons built through *this* repo's pkgs, so `allowUnfree` applies
  # (the flake's own `packages` output can't see it — 1Password is unfree).
  inputs.firefox-addons.overlays.default

  # Provides `claude-desktop` and `claude-desktop-fhs` (FHS variant for MCP)
  inputs.claude-desktop.overlays.default

  (_final: prev: {
    # rocmSupport pulls rocm-smi (Linux-only). Keep the GPU-enabled btop on
    # Linux; leave btop untouched on darwin.
    btop =
      if prev.stdenv.hostPlatform.isLinux
      then prev.btop.override {rocmSupport = true;}
      else prev.btop;
  })

  (_final: prev: {
    # catppuccin 2.5.0's build-time checks import its matplotlib extra (a
    # check-only optional-dep, never propagated to runtime), which crashes on
    # matplotlib 3.11 — it dropped the internal `matplotlib.style.core`. We only
    # consume the pygments extra, so skip the checks until catppuccin supports
    # matplotlib 3.11. Applied via pythonPackagesExtensions so python313.withPackages sees it.
    pythonPackagesExtensions =
      prev.pythonPackagesExtensions
      ++ [
        (_pyfinal: pyprev: {
          catppuccin = pyprev.catppuccin.overridePythonAttrs (_: {
            doCheck = false;
            dontUsePythonImportsCheck = true;
          });
        })
      ];
  })

  (_final: prev: {
    slack = prev.slack.overrideAttrs (old: {
      installPhase =
        (old.installPhase or "")
        + ''
          wrapProgram $out/bin/slack \
            --add-flags "--enable-features=VaapiVideoDecodeLinuxGL,VaapiVideoEncoder,VaapiIgnoreDriverChecks" \
            --add-flags "--enable-gpu-rasterization" \
            --add-flags "--enable-zero-copy" \
            --add-flags "--ignore-gpu-blocklist"
        '';
    });
  })
]
