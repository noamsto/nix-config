{
  pkgs,
  lib,
  config,
  inputs,
  osConfig,
  ...
}: let
  # Shared MCP server definitions
  mcpServers = import ../mcp-servers.nix {inherit pkgs lib;};
  lspServers = import ../lsp-servers.nix {inherit pkgs;};

  claude-statusline = pkgs.callPackage ./statusline.nix {};
  sharedGuards = import ../agent-hooks {inherit pkgs;};
  aeye = import ../hookyard/aeye.nix {
    inherit pkgs;
    aeye = inputs.tmux-og.inputs.aeye;
  };

  psql-guard = pkgs.writeShellScriptBin "claude-psql-guard" (builtins.readFile ./psql-guard.sh);
  skeleton-guard = pkgs.writeShellScriptBin "claude-read-skeleton-guard" (builtins.readFile ./skeleton-guard.sh);
  skill-suggester = pkgs.writeShellScriptBin "claude-skill-suggester" (builtins.readFile ./skill-suggester.sh);
  deslop-guard = pkgs.writeShellScriptBin "claude-deslop-guard" (builtins.readFile ./deslop-guard.sh);
  deslop-mark = pkgs.writeShellScriptBin "claude-deslop-mark" (builtins.readFile ./deslop-mark.sh);

  # hookyard's envelope carries the engine payload verbatim under `.native`; the
  # guards' hookSpecificOutput is already hookyard's handler wire protocol.
  # ../pi registers the same guards without this `.native` strip — its envelope's
  # canonical `tool_name` is what those guards branch on — so the two modules
  # differ here on purpose. See ../pi/guards.nix's header before unifying them.
  # A guard that overruns timeout_ms abstains, so each gets most of the 4300ms cap.
  guardHandler = {
    name,
    exe,
    match,
  }: let
    bridge = pkgs.writeShellApplication {
      name = "${name}-hookyard-bridge";
      runtimeInputs = [pkgs.jq];
      text = ''
        jq -c .native | ${exe}
      '';
    };
  in {
    inherit match;
    id = "guards.${name}";
    exec = "${bridge}/bin/${name}-hookyard-bridge";
    events = ["pre_tool"];
    engines = ["claude-code"];
    timeout_ms = 4000;
  };
  guardsManifest = pkgs.writeText "guards-hookyard.json" (builtins.toJSON {
    handlers = [
      (guardHandler {
        name = "psql";
        exe = "${psql-guard}/bin/claude-psql-guard";
        match = ["Bash"];
      })
      (guardHandler {
        name = "nix-stage";
        exe = "${sharedGuards.nix-stage-guard}/bin/agent-nix-stage-guard";
        match = ["Bash"];
      })
      (guardHandler {
        name = "git-commit-autostage";
        exe = "${sharedGuards.git-commit-autostage-guard}/bin/agent-git-commit-autostage-guard";
        match = ["Bash"];
      })
      (guardHandler {
        name = "git-default-branch";
        exe = "${sharedGuards.git-default-branch-guard}/bin/agent-git-default-branch-guard";
        match = ["Bash"];
      })
      (guardHandler {
        name = "tmux-live-server";
        exe = "${sharedGuards.tmux-live-server-guard}/bin/agent-tmux-live-server-guard";
        match = ["Bash"];
      })
      (guardHandler {
        name = "deslop";
        exe = "${deslop-guard}/bin/claude-deslop-guard";
        match = ["Bash"];
      })
      (guardHandler {
        name = "secret-read";
        exe = "${sharedGuards.secret-read-guard}/bin/agent-secret-read-guard";
        match = ["Bash" "Read" "Grep"];
      })
      (guardHandler {
        name = "read-skeleton";
        exe = "${skeleton-guard}/bin/claude-read-skeleton-guard";
        match = ["Read"];
      })
    ];
  });

  # --settings overlay: ONLY keys that need /nix/store paths.
  # Everything else belongs in settings.json (symlinked to repo).
  nix-settings-json = pkgs.writeTextFile {
    name = "claude-nix-settings.json";
    text = builtins.toJSON {
      statusLine = {
        type = "command";
        command = "${claude-statusline}/bin/claude-statusline";
      };
      # Profile-gated plugins. Deep-merged with (and higher precedence than)
      # the common set in settings.json, so these are profile-locked: the
      # /plugin TUI can't toggle them on the wrong machine. Common,
      # TUI-toggleable plugins stay in settings.json.
      enabledPlugins =
        lib.optionalAttrs (osConfig.profile == "work") {
          "pg@aiguide" = true;
          "cc-skills-golang@samber" = true;
          "figma@claude-plugins-official" = true;
          "pr-reviewers@factify-pr-reviewers" = true;
        }
        // lib.optionalAttrs (osConfig.profile == "personal") {
          "swift-lsp@claude-plugins-official" = true;
        };
      # Marketplace for the work-only pr-reviewers plugin above. Common
      # marketplaces (samber, aiguide, claude-plugins-official, etc.) live in
      # settings.json; this one is profile-gated alongside its plugin.
      extraKnownMarketplaces = lib.optionalAttrs (osConfig.profile == "work") {
        "factify-pr-reviewers" = {
          source = {
            source = "github";
            repo = "factify-inc/claude-pr-reviewers";
          };
        };
      };
      # Allow-lists the codex MCP tools (registered via `dispatch`'s
      # --mcp-config, not this overlay — --settings doesn't register
      # mcpServers) so an auto-mode worker's reviewer subagent isn't denied.
      # Union'd with settings.json's allow list.
      permissions.allow =
        lib.optionals (osConfig.profile == "work") ["mcp__codex__*"];
      # Status-state hooks live in the lazytmux CC plugin and aeye's
      # SessionStart hooks in the aeye CC plugin (both loaded via --plugin-dir
      # in the wrapper below); aeye's PostToolUse hooks come from hookyard's
      # `claudeOverlay.merged`. Only personal hooks remain here.
      hooks = {
        SessionStart = [
          {
            matcher = "startup";
            hooks = [
              {
                type = "command";
                command = "${skill-suggester}/bin/claude-skill-suggester";
              }
            ];
          }
        ];
        PostToolUse = [
          {
            matcher = "Skill";
            hooks = [
              {
                type = "command";
                command = "${deslop-mark}/bin/claude-deslop-mark";
              }
            ];
          }
        ];
        # SessionEnd dispatch-notify now ships in the dispatcher plugin's own
        # hooks.json (loaded via --plugin-dir below), so it is no longer wired
        # here.
      };
    };
  };

  claude-wrapped = inputs.wrappers.lib.wrapPackage {
    inherit pkgs;
    package = pkgs.claude-code;
    # betterleaks: the dispatcher plugin's public-leak guard skips its secret
    # scan when it isn't on PATH.
    runtimeInputs = [pkgs.nodejs pkgs.uv pkgs.betterleaks];
  };

  # DISABLE_INSTALLATION_CHECKS: suppress false warnings when running via Nix
  # https://github.com/anthropics/claude-code/issues/8523
  # DISABLE_UPDATES: block self-update paths on immutable Nix store (>=2.1.118)
  #
  # exec -a claude: set argv[0] so ps/comm/Activity Monitor (and Linux tmux,
  # which reads /proc/pid/cmdline) show `claude`, not the nix store wrapper.
  # macOS tmux can't be fixed here: it reads proc_pidpath, which resolves
  # through every wrapper/symlink to the real Bun binary upstream named
  # `.claude-wrapped`, ignoring argv[0]. That title is instead rewritten at the
  # tmux display layer (lazytmux set-titles-string strips `.*-wrapped`).
  claude-wrapper =
    pkgs.writeShellScriptBin "claude" ''
      export DISABLE_INSTALLATION_CHECKS=1
      export DISABLE_UPDATES=1
      # D2 diagrams (aeye diagrams.sh): bundle d2's own font so resvg
      # renders text, and follow the desktop light/dark scheme for the theme.
      export AEYE_D2_FONT="Source Sans 3"
      export AEYE_D2_FONT_DIR="${pkgs.source-sans}/share/fonts/truetype"
      scheme=$(dconf read /org/gnome/desktop/interface/color-scheme 2>/dev/null)
      if [ "$scheme" = "'prefer-light'" ]; then
        export AEYE_D2_THEME=105
      else
        export AEYE_D2_THEME=200
      fi
      exec -a claude ${claude-wrapped}/bin/claude --settings ${config.programs.hookyard.claudeOverlay.merged} --plugin-dir ${inputs.tmux-og}/claude-plugin --plugin-dir ${aeye.tree}/adapters/claude-code/plugin --plugin-dir ${inputs.dispatcher}/adapters/claude-code/plugin "$@"
    ''
    # writeShellScriptBin carries no version, so the HM claude-code module can't
    # detect that the wrapped package is >=2.1.157 and falls back to the legacy
    # --plugin-dir wrapper (with an eval warning). Expose the upstream version so
    # the module uses persistent personal plugins for the managed MCP/LSP config.
    // {inherit (pkgs.claude-code) version;};

  # Auto-discover skill directories under ./skills and symlink each into ~/.claude/skills/
  # Per-skill symlinks (rather than one dir-level symlink) so we don't conflict with
  # upstream-managed entries like tmux-interactive.
  skillNames =
    builtins.attrNames
    (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills));
  skillSymlinks = lib.listToAttrs (map (name: {
      name = ".claude/skills/${name}";
      value.source =
        config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/nix-config/home/ai/claude-code/skills/${name}";
    })
    skillNames);
in {
  imports = [
    ./mcp-profiles.nix
    ./session-archive.nix
    inputs.agent-smith.homeManagerModules.default
    inputs.resolved.homeManagerModules.default
    inputs.dispatcher.homeManagerModules.default
  ];

  programs = {
    # agent-smith CC plugin engine on PATH; the module self-wraps duckdb/git/gh.
    agent-smith.enable = true;
    # resolved CC plugin binary on PATH; the /resolved:stale plugin finds it there.
    resolved.enable = true;
    # crew + dispatch + dispatcher on PATH, DISPATCH_PROFILE and
    # DISPATCHER_PROTOCOL_DIR exported. The claude plugin dir is passed in the
    # wrapper below. `engines` — not `profile` — gates which worker engines may
    # be dispatched and which per-engine artifacts get installed.
    dispatcher = {
      enable = true;
      inherit (osConfig) profile;
      # cursor-agent ships on every host but is only logged in on the work one.
      engines = ["claude" "pi"] ++ lib.optionals (osConfig.profile == "work") ["cursor"];
      # $40/mo OpenRouter budget gate for pi worker spend — personal only.
      openrouter.monthlyTarget = lib.mkIf (osConfig.profile == "personal") 40;
      orgTrackers.factify-inc = "linear:ENG";
    };

    # hookyard refuses to write through the settings.json symlink, so it
    # merges its hooks into this overlay instead of writing its own file —
    # set here, not in ../hookyard, so `nix-settings-json` stays in scope.
    hookyard = {
      claudeOverlay.base = nix-settings-json;
      manifests = [guardsManifest];
    };
  };

  home = {
    # Out-of-store symlinks so Claude (and third-party tools) can edit at runtime
    file =
      {
        ".claude/CLAUDE.md".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/claude-code/CLAUDE.global.md";
        # Engine-neutral conventions imported by CLAUDE.global.md via
        # @~/.claude/AGENTS.shared.md. The same file backs ~/.codex/AGENTS.md
        # and ~/.cursor/rules (see ../codex, ../cursor) — one source, three engines.
        ".claude/AGENTS.shared.md".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/AGENTS.shared.md";
        # Profile overlay imported by CLAUDE.global.md via @~/.claude/CLAUDE.profile.md.
        # Always present (work or personal) so the import never silently no-ops.
        ".claude/CLAUDE.profile.md".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/claude-code/CLAUDE.${osConfig.profile}.md";
        ".claude/settings.json".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/claude-code/settings.json";
        # Mirrored to ~/.cursor/agents and ~/.codex/agents from those modules —
        # one source tree for all three harnesses.
        ".claude/agents".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/claude-code/agents";
        ".claude/commands".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/claude-code/commands";
        # No `.claude/workflows` symlink: spec-plan-critic.js was the only
        # workflow and it moved to the dispatcher plugin. Git does not track an
        # empty directory, so pointing at one would dangle on a fresh clone.
      }
      // skillSymlinks;
  };

  programs.claude-code = {
    enable = true;
    package = claude-wrapper;
    settings = {}; # Managed via --settings flag in wrapper
    # Heavy MCPs (Playwright, PostHog) loaded conditionally via mcp-profiles.nix aliases
    mcpServers = lib.removeAttrs mcpServers.base mcpServers.claudeAiProvided;
    # Secondaries are left out: how Claude Code arbitrates two servers claiming
    # one extension is undocumented.
    lspServers =
      lib.mapAttrs (_: s: {
        command = lib.getExe s.package;
        extensionToLanguage = s.extensions;
      })
      (lib.filterAttrs (_: s: !(s.secondary or false)) lspServers);
  };
}
