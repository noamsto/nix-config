# Reusable overlays for both NixOS and standalone Home Manager
inputs: [
  (final: _: {
    stable = import inputs.nixpkgs-stable {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };
    inherit
      (import inputs.nixpkgs-bambu {
        inherit (final.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      })
      bambu-studio
      ;
  })

  (final: _: {
    wtc = inputs.wtc.packages.${final.stdenv.hostPlatform.system}.default;
    zr = inputs.zr.packages.${final.stdenv.hostPlatform.system}.default;
    argonaut = inputs.argonaut.packages.${final.stdenv.hostPlatform.system}.default;
  })

  (final: _prev: {
    inherit (inputs.llm-agents.packages.${final.stdenv.hostPlatform.system}) claude-code cursor-agent pi;
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

  # nixpkgs bumped python3Packages.zxing-cpp to 3.0.2; normcap 0.6.0 still
  # pins ==2.3.0 in pyproject.toml. Same relax pattern nixpkgs already uses
  # for jeepney/shiboken6 — drop once upstream loosens the pin / nixpkgs
  # adds this to pythonRelaxDeps.
  (_final: prev: {
    normcap = prev.normcap.overrideAttrs (old: {
      pythonRelaxDeps = (old.pythonRelaxDeps or []) ++ ["zxing-cpp"];
    });
  })

  # Hyprland 0.56.2 resets m_draggingTiled only inside updateDragWindow(), but
  # dragBegin() has three early returns (unmapped window / no workspace / drag
  # rejected on a fullscreen workspace) that skip it. dragEnd() then runs with a
  # stale true and calls changeFloatingMode() on a window this drag never
  # floated -> SEGV in CDwindleAlgorithm::addTarget. Upstream PR #15833 (fixes
  # #15789) is merged to master but unreleased. Drop once nixpkgs carries >0.56.2.
  (_final: prev: {
    hyprland = prev.hyprland.overrideAttrs (old: {
      patches = (old.patches or []) ++ [./patches/hyprland-drag-tiled-reset.patch];
    });
  })

  # sesh builds with Go 1.27 and rebuilds go-mockery with it for its preBuild,
  # but mockery 3.8.0 vendors golang.org/x/tools v0.49.0, which can't decode
  # Go 1.27.2 export data (v5 > 4), so both mockery's checks and sesh's mock
  # generation fail. sesh's go.mod only needs 1.26, so build both with 1.26.
  # Upstream PR vektra/mockery#1188 (fixes #1187) bumps x/tools to v0.51.0.
  # Drop once nixpkgs ships a mockery release carrying it.
  (_final: prev: {
    sesh = prev.sesh.override {buildGo127Module = prev.buildGo126Module;};
  })

  # Determinate Nix 3.23 emits OTel activity type 10113 in --log-format
  # internal-json; nom 2.2.0 rejects any unknown type and aborts, which breaks
  # `nh os switch`. Upstream PR maralorn/nix-output-monitor#321 (fixes #320)
  # maps unknown types to Unknown. Drop once nixpkgs ships a nom carrying it.
  (_final: prev: {
    nix-output-monitor = prev.nix-output-monitor.overrideAttrs (old: {
      patches = (old.patches or []) ++ [./patches/nix-output-monitor-unknown-activity-type.patch];
    });
  })

  # typescript-language-server 6.0.2 moved from yarn to pnpm and shipped a
  # stale fetchPnpmDeps hash, so the whole darwin/hm build dies in the FOD's
  # fixupPhase with a hash mismatch. Upstream fixed the hash in ac7b1aaed03d
  # ("typescript-language-server: fix pnpm hash"), which nixos-unstable at
  # 7fd4004d has not picked up yet. The corrected FOD is already on
  # cache.nixos.org, so this only rewrites the hash. Drop once nixpkgs ships a
  # rev carrying the fix.
  (_final: prev: {
    typescript-language-server =
      if prev.typescript-language-server.version == "6.0.2"
      then
        prev.typescript-language-server.overrideAttrs (old: {
          pnpmDeps = old.pnpmDeps.overrideAttrs (_: {
            outputHash = "sha256-xR/EF60lVBsITKgH7wCM2wHM46PFQevD51KfCENSUH4=";
          });
        })
      else prev.typescript-language-server;
  })
]
