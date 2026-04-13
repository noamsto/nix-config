{
  pkgs,
  config,
  ...
}: {
  home.packages = with pkgs; [
    oh-my-opencode
    (pkgs.writeShellScriptBin "comment-checker" ''
      exec ${pkgs.nodejs}/bin/npx --yes @code-yeongyu/comment-checker "$@"
    '')
    nixd # Nix LSP
    typescript-language-server # TS/JS LSP
    bash-language-server # Shell script LSP
    yaml-language-server # YAML LSP
    lua-language-server # Lua LSP (nvim configs)
  ];

  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;
    settings = {
      autoupdate = false;
      # Conventional commits guidelines - loaded from symlinked directory for easy editing
      instructions = [
        "${config.home.homeDirectory}/.config/opencode/instructions/conventional-commits.md"
      ];
      # Register oh-my-opencode plugin - required for agents/categories to work
      # Must use file:// protocol for Nix store paths
      plugin = [
        "file://${pkgs.oh-my-opencode}/lib/oh-my-opencode"
      ];
    };
    tui = {
      theme = "catppuccin";
    };
  };

  # Symlink OpenCode directories for easy editing without rebuilding
  # These are out-of-store symlinks pointing to this repo
  xdg.configFile = {
    "opencode/skills".source =
      config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nix-config/home/ai/opencode/skills";
    "opencode/commands".source =
      config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nix-config/home/ai/opencode/commands";
    "opencode/agents".source =
      config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nix-config/home/ai/opencode/agents";
    "opencode/plugins".source =
      config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nix-config/home/ai/opencode/plugins";
    "opencode/instructions".source =
      config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nix-config/home/ai/opencode/instructions";
    "opencode/oh-my-openagent.json".text = let
      sisyphusConfig = {
        model = "opencode/kimi-k2.5";
        fallback_models = [
          "opencode/gemini-3.1-pro"
          "opencode/claude-opus-4-6"
        ];
      };
    in
      builtins.toJSON {
        "$schema" = "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json";
        default_run_agent = "Sisyphus - Ultraworker";

        # Agent model assignments
        agents = {
          # Canonical key (clean config)
          sisyphus = sisyphusConfig;

          # TEMPORARY: Alias for plugin compatibility
          # Remove once oh-my-opencode version matches opencode
          "Sisyphus - Ultraworker" = sisyphusConfig;

          hephaestus = {
            model = "opencode/gpt-5.4";
            fallback_models = [
              "opencode/claude-opus-4-6"
            ];
          };
          # Oracle needs STRONG model for hard debugging/architecture (Opus preferred)
          oracle = {
            model = "opencode/claude-opus-4-6";
            fallback_models = [
              "opencode/gpt-5.4"
            ];
          };
          # Prometheus creates plans - needs strong reasoning (GPT-5.4 has dual prompts)
          prometheus = {
            model = "opencode/gpt-5.4";
            fallback_models = [
              "opencode/claude-opus-4-6"
            ];
          };
          # Atlas: Kimi K2.5 is OMO default - cheaper than Sonnet, GPT-optimized for todo management
          atlas = {
            model = "opencode/kimi-k2.5";
            fallback_models = [
              "opencode/claude-sonnet-4-6"
              "opencode/gpt-5.4"
            ];
          };
          # Metis analyzes complex tasks - needs reasoning strength (Sonnet sweet spot)
          metis = {
            model = "opencode/claude-sonnet-4-6";
            fallback_models = [
              "opencode/gpt-5.4"
            ];
          };
          explore = {model = "opencode/gemini-3-flash";};
          librarian = {model = "opencode/gemini-3-flash";};
        };

        # Category configurations for domain-optimized model routing
        # Based on oh-my-opencode model requirements and fallback chains
        categories = {
          quick = {
            model = "opencode/gemini-3-flash";
            description = "Trivial tasks - single file changes, typo fixes, simple modifications";
            fallback_models = [
              "opencode/claude-haiku-4-5"
              "opencode/gpt-5-nano"
            ];
          };
          deep = {
            model = "opencode/gemini-3.1-pro";
            description = "Goal-oriented autonomous problem-solving. Thorough research before action. For hairy problems requiring deep understanding.";
            fallback_models = [
              "opencode/claude-opus-4-6"
              "opencode/gpt-5.4"
              "opencode/kimi-k2.5"
            ];
          };
          ultrabrain = {
            model = "opencode/gemini-3.1-pro";
            description = "Use ONLY for genuinely hard, logic-heavy tasks. Give clear goals only, not step-by-step instructions.";
            fallback_models = [
              "opencode/claude-opus-4-6"
              "opencode/gpt-5.4"
            ];
          };
          artistry = {
            model = "opencode/claude-opus-4-6";
            description = "Complex problem-solving with unconventional, creative approaches - beyond standard patterns";
            fallback_models = [
              "opencode/gemini-3.1-pro"
              "opencode/gpt-5.4"
            ];
          };
          "unspecified-high" = {
            model = "opencode/gemini-3.1-pro";
            description = "Tasks that don't fit other categories, high effort required";
            fallback_models = [
              "opencode/claude-opus-4-6"
              "opencode/gpt-5.4"
              "opencode/kimi-k2.5"
            ];
          };
          "unspecified-low" = {
            model = "opencode/gemini-3-flash";
            description = "Tasks that don't fit other categories, low effort required";
            fallback_models = [
              "opencode/claude-sonnet-4-6"
              "opencode/gpt-5.3-codex"
              "opencode/kimi-k2.5"
            ];
          };
          writing = {
            model = "opencode/gemini-3.1-pro";
            description = "Documentation, prose, technical writing";
            fallback_models = [
              "opencode/gemini-3-flash"
              "opencode/claude-sonnet-4-6"
            ];
          };
          "visual-engineering" = {
            model = "opencode/claude-sonnet-4-6";
            description = "Frontend, UI/UX, design, styling, animation. Any task involving UI, UX, CSS, styling, layout, animation, design, or frontend components MUST go here.";
            fallback_models = [
              "opencode/gemini-3.1-pro"
              "opencode/gpt-5.4"
            ];
          };
        };

        # Orchestration
        sisyphus_agent = {
          disabled = false;
          planner_enabled = true;
          replace_plan = true;
          tdd = true;
        };

        # Tmux integration for background agent visibility
        tmux = {
          enabled = true;
          layout = "main-vertical";
          main_pane_size = 60;
          main_pane_min_width = 120;
          agent_pane_min_width = 40;
          isolation = "inline";
        };

        # Ralph loop for autonomous execution
        ralph_loop = {
          enabled = true;
          default_max_iterations = 100;
          default_strategy = "continue";
        };

        # Model fallback and runtime resilience
        model_fallback = true;
        runtime_fallback = {
          enabled = true;
          retry_on_errors = [400 429 503 529];
          notify_on_fallback = true;
        };

        # Background task concurrency limits
        background_task = {
          providerConcurrency = {
            anthropic = 2;
            openai = 3;
            google = 5;
            opencode = 10;
          };
        };

        # Auto-refresh model capabilities on start
        model_capabilities = {
          enabled = true;
          auto_refresh_on_start = true;
          refresh_timeout_ms = 5000;
        };

        # Experimental features
        experimental = {
          auto_resume = true;
        };
      };
  }; # closes xdg.configFile oh-my-openagent.json
}
