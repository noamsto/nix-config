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

  (_final: prev: {
    btop = prev.btop.override {rocmSupport = true;};
  })

  # Point profile-sync-daemon's firefox sync at the XDG profile location
  # ($HOME/.config/mozilla/firefox), matching programs.firefox.configPath.
  # Firefox 150+ honors XDG natively, but psd's browser script hardcodes the
  # legacy path. --replace-fail guards against silent breakage on psd updates.
  (_final: prev: {
    profile-sync-daemon = prev.profile-sync-daemon.overrideAttrs (old: {
      postFixup =
        (old.postFixup or "")
        + ''
          substituteInPlace $out/share/psd/browsers/firefox \
            --replace-fail '.mozilla/firefox' '.config/mozilla/firefox'
        '';
    });
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
