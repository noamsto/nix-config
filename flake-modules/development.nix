# Development environment configuration
{inputs, ...}: {
  imports = [
    inputs.treefmt-nix.flakeModule
    ../pre-commit-hooks.nix
  ];

  perSystem = {
    inputs',
    config,
    pkgs,
    lib,
    system,
    ...
  }: {
    # Match the hosts' pkgs: devShell tools sit first on PATH, so a stock build
    # here (e.g. nom) would shadow the patched system one.
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = import ../lib/overlays.nix inputs;
      config.allowUnfree = true;
    };

    checks =
      {
        # pi's hookyard guard manifest, end to end: the locked hookyard binary
        # installs it, then routes real pi tool_call payloads through the real
        # handler executables. A guard that stops blocking fails open and silently,
        # so it is checked here rather than left to the rebuild.
        pi-guards = import ../home/ai/pi/guards-check.nix {
          inherit pkgs;
          hookyard = inputs'.hookyard.packages.default;
          inherit (inputs) dispatcher;
        };

        # Every pi handler in the locked dispatcher's hookyard.json must reach the
        # generated manifest, or be in guards.nix's explicit exclusion list. A
        # silently dropped handler fails the build here rather than disappearing
        # at hook-fire time.
        pi-dispatcher-manifest = import ../home/ai/pi/dispatcher-manifest-check.nix {
          inherit pkgs;
          inherit (inputs) dispatcher;
        };

        # Direct bats regression suite for the secret-read, git-identity and pgrep-self-match guard scripts.
        agent-hooks = import ../home/ai/agent-hooks/check.nix {inherit pkgs;};

        # Direct bats regression suite for the deslop push guard.
        deslop-guard = import ../home/ai/claude-code/check.nix {inherit pkgs;};

        # Direct bats regression suite for the lock-commit fish function.
        lock-commit = import ../home/terminal/fish/check.nix {inherit pkgs;};

        # Every locked input must come from a public URL scheme. A
        # `github:<owner>/<private-repo>` node passes this walk, so CI also
        # archives every input with no access tokens. URLs with embedded
        # credentials also fail.
        no-private-inputs = pkgs.runCommand "no-private-inputs" {nativeBuildInputs = [pkgs.jq];} ''
          offenders=$(jq -c '[.nodes | to_entries[] | select(.value.locked != null)
            | select(.value.locked | ((.type == "github" or .type == "gitlab"
                or ((.url // "") | startswith("https://")))
                and ((.url // "") | test("^[a-z+]+://[^/]*@|[?&][^=&]*(token|key|signature|credential|secret|password)[^=&]*="; "i") | not)) | not) | .key]' ${../flake.lock})
          if [ "$offenders" != "[]" ]; then
            echo "flake.lock nodes not fetched from a public URL: $offenders" >&2
            exit 1
          fi
          touch $out
        '';
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        steam-console-idle = import ../nixos/steam-console/idle-test.nix {inherit pkgs;};
        money-scout-relay = import ../nixos/services/money-scout-relay-test.nix {inherit pkgs;};
        money-scout-commands = import ../nixos/services/money-scout-commands-test.nix {
          inherit pkgs;
          hermesVenv = inputs'.hermes-agent.packages.default.passthru.hermesVenv;
        };
        money-scout-research-relay = import ../nixos/services/money-scout-research-relay-test.nix {inherit pkgs;};
        bt-headset-mode = import ../home/desktop/bt-headset/check.nix {inherit pkgs;};
        # Direct bats regression suite for the xresources-apply script, against a
        # real Xvfb server + xrdb (fresh-X-server behaviour).
        xresources-apply = import ../home/desktop/hyprland/check.nix {inherit pkgs;};
      };

    devShells.default = pkgs.mkShell {
      packages =
        [
          # Core NixOS configuration tools
          config.treefmt.build.wrapper
          pkgs.git
          pkgs.nh
          pkgs.prettier
          pkgs.fish
          pkgs.nix-output-monitor
          pkgs.just
          pkgs.statix
          pkgs.shellcheck
          # Same derivation the git hook calls, so the two cannot drift.
          config.pre-commit.settings.package

          # Package authoring helpers (see nix-package-authoring skill)
          pkgs.nurl # generate fetcher + hash from a URL
          pkgs.nix-init # scaffold a full derivation from a URL

          # Lightweight development essentials
          pkgs.jq # JSON processing (small and useful)
          pkgs.tokei # Code statistics (lightweight and useful for dev-stats)

          pkgs.home-manager
        ]
        # Remote NixOS installer — Linux-only, irrelevant on the darwin devShell.
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          inputs'.nixos-anywhere.packages.default
        ];
      name = "dots";
      DIRENV_LOG_FORMAT = "";
      shellHook = ''
        ${config.pre-commit.installationScript}

        # Enhanced environment setup
        export EDITOR=nvim
        export DEVELOPMENT_MODE=true

        # Fish-compatible aliases and functions
        if command -v fish >/dev/null 2>&1; then
          fish -c "
            alias nix-agent='agent-helper.sh'
            alias nbuild='nom build'
            function dev-stats
              tokei
              echo
              git log --oneline | wc -l | xargs echo 'Total commits:'
            end
            funcsave dev-stats
          "
        else
          # Fallback for other shells
          alias nix-agent="agent-helper.sh"
          alias nbuild="nom build"
        fi

        echo "🚀 NixOS Development Environment Ready!"
        echo "📊 Project stats: 'dev-stats'"
      '';
    };

    # configure treefmt
    treefmt = {
      projectRootFile = "flake.nix";

      programs = {
        alejandra.enable = true;
        ruff.enable = true;
        deadnix.enable = false;
        shellcheck.enable = true;
        shfmt = {
          enable = true;
          indent_size = 2;
        };
      };
    };

    formatter = pkgs.alejandra;

    # Pre-commit configuration
    pre-commit.settings = {
      hooks = {
        treefmt.enable = true;
      };
    };
  };
}
