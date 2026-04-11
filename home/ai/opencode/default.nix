{pkgs, ...}: {
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
      plugin = [
        "${pkgs.oh-my-opencode}/lib/oh-my-opencode"
      ];
    };
    tui = {
      theme = "catppuccin";
    };
  };

  # OpenCode web server — DISABLED to use tmux integration with bare TUI
  # systemd.user.services.opencode-web = {
  #   Unit = {
  #     Description = "OpenCode Web Server";
  #     After = ["network-online.target"];
  #   };
  #   Service = {
  #     Type = "simple";
  #     EnvironmentFile = "/etc/agenix/opencode-server-password.env";
  #     ExecStart = "${pkgs.opencode}/bin/opencode web --hostname 0.0.0.0 --port 4096";
  #     Restart = "on-failure";
  #     RestartSec = "5s";
  #   };
  #   Install = {
  #     WantedBy = ["default.target"];
  #   };
  # };

  xdg.configFile."opencode/oh-my-openagent.json".text = let
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
        oracle = {model = "opencode/gpt-5.4";};
        prometheus = {model = "opencode/gemini-3.1-pro";};
        atlas = {model = "opencode/claude-sonnet-4-6";};
        metis = {model = "opencode/gemini-3.1-pro";};
        explore = {model = "opencode/gemini-3-flash";};
        librarian = {model = "opencode/gemini-3-flash";};
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
}
