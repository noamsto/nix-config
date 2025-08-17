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
    ...
  }: {
    devShells.default = pkgs.mkShell {
      packages = [
        # Core NixOS configuration tools
        inputs'.agenix.packages.default
        inputs'.nixos-anywhere.packages.default
        config.treefmt.build.wrapper
        pkgs.git
        pkgs.nh
        pkgs.nodePackages.prettier
        pkgs.zsh
        pkgs.nix-output-monitor
        pkgs.just

        # Lightweight development essentials
        pkgs.jq # JSON processing (small and useful)
        pkgs.typos # Spell checker for code (lightweight)
        pkgs.tokei # Code statistics (lightweight and useful for dev-stats)
      ];
      name = "dots";
      DIRENV_LOG_FORMAT = "";
      shellHook = ''
        ${config.pre-commit.installationScript}

        # Enhanced environment setup
        export EDITOR=nvim
        export DEVELOPMENT_MODE=true

        # Add agent helper to PATH
        export PATH="${../agents}:$PATH"

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
        echo "📁 Agents available: 'nix-agent help'"
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
          indent_size = 4;
        };
      };
    };

    formatter = pkgs.alejandra;

    # Pre-commit configuration
    pre-commit.settings = {
      hooks = {
        treefmt.enable = true;
        typos.enable = true;
      };
    };
  };
}
