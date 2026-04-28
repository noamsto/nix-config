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

  # Silence noisy "Did not detect DSR response from terminal" warning that nvim
  # 0.12.x emits on every startup under tmux (false positive — DSR works, the
  # 100ms wait just isn't long enough during heavy plugin load).
  # Upstream fix: https://github.com/neovim/neovim/pull/38699 (NVIM_NOTTYFAST=1)
  # Tracking issue: https://github.com/neovim/neovim/issues/38648
  # Drop this overlay once nixpkgs ships nvim with commit 66149ca6, then set
  # `home.sessionVariables.NVIM_NOTTYFAST = "1"` in home/nvim/default.nix.
  (_final: prev: {
    neovim-unwrapped = prev.neovim-unwrapped.overrideAttrs (old: {
      patches = (old.patches or []) ++ [../overlays/neovim-suppress-dsr-warning.patch];
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
