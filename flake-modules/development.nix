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

    # The hosts' pkgs (overlays + allowUnfree), for scripts/update-bot's failure-to-attr mapping.
    legacyPackages = pkgs;

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

        # Direct bats regression suite for the pi openrouter auth.json upsert script.
        pi-openrouter-auth = import ../home/ai/pi/openrouter-auth-check.nix {inherit pkgs;};

        # Unit tests of the flake-update bot's pin selection and failure-to-attr logic.
        update-bot = pkgs.runCommand "update-bot-tests" {nativeBuildInputs = [pkgs.python3];} ''
          cp -r ${../scripts/update-bot} src
          chmod -R u+w src
          PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover src
          touch $out
        '';

        # Unit tests of the R2 binary-cache tool; build.yml is copied in for the roots.json consistency test.
        nix-cache = pkgs.runCommand "nix-cache-tests" {nativeBuildInputs = [pkgs.python3];} ''
          cp -r ${../scripts/nix-cache} src
          chmod -R u+w src
          cp ${../.github/workflows/build.yml} src/build.yml
          PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover src
          touch $out
        '';

        # Direct bats regression suite for the secret-read, git-identity and pgrep-self-match guard scripts.
        agent-hooks = import ../home/ai/agent-hooks/check.nix {inherit pkgs;};

        # Direct bats regression suite for the deslop push guard.
        deslop-guard = import ../home/ai/claude-code/check.nix {inherit pkgs;};

        # Direct bats regression suite for the lock-commit fish function.
        lock-commit = import ../home/terminal/fish/check.nix {inherit pkgs;};

        # Direct bats regression suite for the secret-commit fish function,
        # including a real sops round trip on a throwaway age key.
        secret-commit = import ../home/terminal/fish/secret-commit-check.nix {inherit pkgs;};

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
        # greetd IPC against the real PAM chain: a typed password never waits on
        # the fingerprint reader; only an empty submit uses it.
        greetd-pam = import ../nixos/hyprland/greetd-pam-test.nix {inherit pkgs;};
        # Drives the real keyring TPM unlock units in a VM: one unlock per new
        # keyring control socket, and a broken PCR 7 seal notifies once.
        keyring-tpm-unlock = import ../nixos/hyprland/keyring-tpm-unlock-test.nix {inherit pkgs;};
        bt-headset-mode = import ../home/desktop/bt-headset/check.nix {inherit pkgs;};
        # Direct bats regression suite for the xresources-apply script, against a
        # real Xvfb server + xrdb (fresh-X-server behaviour).
        xresources-apply = import ../home/desktop/hyprland/check.nix {inherit pkgs;};

        # Direct bats regression suite for aegis-lock-guard: locks despite a
        # lingering lock client, never replaces one while the session is locked.
        aegis-lock-guard = import ../home/desktop/hyprland/aegis-lock-check.nix {inherit pkgs;};

        # Runs workspace-manager undocked with noctalia dead: it must still reload
        # Hyprland instead of dying on the pgrep lookup.
        workspace-manager = import ../home/desktop/hyprland/workspace-manager-check.nix {inherit pkgs;};

        # Runs jellyfin-known-proxies against a missing, populated and
        # element-less network.xml, plus an idempotent rerun.
        jellyfin-known-proxies = import ../nixos/services/jellyfin-known-proxies-check.nix {inherit pkgs;};
      }
      // lib.optionalAttrs (system == "x86_64-linux") {
        # The Nix-served LazyVim config, headless in the sandbox (x86_64-linux: the
        # example host's system).
        nvim-lazy = import ../home/nvim/check.nix {
          inherit pkgs;
          hmConfig = let
            inherit (inputs.self.nixosConfigurations.example) config;
          in
            config.home-manager.users.${config.username};
        };
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
          pkgs.cachix
        ]
        # Remote NixOS installer — Linux-only, irrelevant on the darwin devShell.
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          inputs'.nixos-anywhere.packages.default
        ];
      name = "dots";
      DIRENV_LOG_FORMAT = "";
      shellHook = ''
        # prek chains a foreign hook as .legacy. Two stale kinds break it: git-lfs
        # shims (fail when git-lfs is missing) and Python pre-commit scripts
        # (fail with "installed in migration mode"). Drop them first; the guard
        # leaves prek's own hooks ("generated by prek:") alone.
        hooks_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/hooks
        for h in pre-commit pre-commit.legacy pre-push pre-push.legacy post-checkout post-commit post-merge; do
          if [ -f "$hooks_dir/$h" ] && grep -qE 'git[ -]lfs|generated by pre-commit:' "$hooks_dir/$h"; then
            rm -f "$hooks_dir/$h"
            echo "removed stale git-lfs/pre-commit hook: $hooks_dir/$h"
          fi
        done

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
        statix.enable = true;
        deadnix = {
          enable = true;
          # NixOS/HM modules destructure `{ config, lib, pkgs, ... }:`, so keep
          # those pattern names: without this deadnix rewrites the signatures.
          no-lambda-pattern-names = true;
        };
        shellcheck.enable = true;
        shfmt = {
          enable = true;
          indent_size = 2;
        };
        prettier = {
          enable = true;
          # Markdown, JS and TS are left to their own tools; JSON is in scope
          # here (the old hook's `(.js|…)` regex skipped it by accident).
          # `home/nvim/` is owned by the unmerged #778 branch (vendored LazyVim
          # JSON), and a generated npm lockfile feeds `fetchNpmDeps`, whose
          # pinned `npmDepsHash` is whitespace-sensitive.
          # pins.json is machine-written by scripts/update-bot in json.dumps form;
          # reformatting it would fail the next round's treefmt check.
          excludes = ["pins.json" "*.md" "*.js" "*.ts" "home/nvim/**" "**/package-lock.json"];
        };
      };
    };
  };
}
