{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  guards = import ../agent-hooks {inherit pkgs;};
  lspServers = import ../lsp-servers.nix {inherit pkgs;};
  localPkgs = inputs.self.packages.${pkgs.stdenv.hostPlatform.system};

  # aeye's pi adapter. Unlike the other three engines this routes nothing
  # through hookyard: hookyard carries post_tool only, and the extension also
  # owns session_start guidance/reset, resume backfill and the /aeye command.
  # Imported from ../hookyard/aeye.nix anyway so every consumer shares one
  # derivation — its PostToolUse stripping touches the other adapters'
  # hooks.json, never adapters/pi.
  aeye = import ../hookyard/aeye.nix {
    inherit pkgs;
    aeye = inputs.tmux-og.inputs.aeye;
  };

  # ../claude-code owns its own nix wiring for these scripts, so they're built
  # separately here rather than shared. Both scripts self-filter on
  # tool_name, so one guard list can serve pi's bash and read tool calls alike.
  skeleton-guard = pkgs.writeShellScriptBin "agent-read-skeleton-guard" (builtins.readFile ../claude-code/skeleton-guard.sh);
  psql-guard = pkgs.writeShellScriptBin "agent-psql-guard" (builtins.readFile ../claude-code/psql-guard.sh);

  # Deny guards first, advisory last: hook-bridge.ts stops at the first deny, so
  # a blocked call shouldn't also spend time on advice it will never show.
  hookPaths = lib.concatStringsSep ":" [
    "${guards.git-default-branch-guard}/bin/agent-git-default-branch-guard"
    "${guards.nix-stage-guard}/bin/agent-nix-stage-guard"
    "${skeleton-guard}/bin/agent-read-skeleton-guard"
    "${psql-guard}/bin/agent-psql-guard"
    "${guards.git-commit-autostage-guard}/bin/agent-git-commit-autostage-guard"
    "${guards.tmux-live-server-guard}/bin/agent-tmux-live-server-guard"
  ];

  # Claude Code gets these skills from the context-efficient-tools plugin,
  # which pi can't see.
  #
  # ripgrep's unquoted description holds "tool: rg", which is invalid YAML;
  # Claude Code tolerates it, pi silently drops the skill.
  xdg-claude = pkgs.applyPatches {
    name = "xdg-claude";
    src = pkgs.fetchFromGitHub {
      owner = "xdg";
      repo = "xdg-claude";
      rev = "6b41d97aad91651ce60c9759326edeb0cc0addc8";
      hash = "sha256-fAI7/hRUENhPgR2dSjtxMXCK0HXRpuv6jPc11aCiZ2I=";
    };
    postPatch = ''
      sed -i 's/^description: \(.*\)$/description: "\1"/' context-efficient-tools/skills/ripgrep/SKILL.md
    '';
  };

  # Built-ins the registry covers are denied so two servers don't attach to one
  # file. The deny list matches by id and applies to custom servers too, hence
  # the prefix. pi-lens makes the first matching custom server primary, in key
  # order, so the prefix also sorts secondaries last. deno claims .ts once the
  # typescript built-in is gone.
  piLensConfig = pkgs.writeText "pi-lens-config.json" (builtins.toJSON {
    lsp = {
      disabledServers = ["python" "python-jedi" "go" "typescript" "deno" "nix" "bash" "lua" "yaml"];
      servers = lib.mapAttrs' (name: s:
        lib.nameValuePair "${
          if s.secondary or false
          then "secondary"
          else "primary"
        }-${name}" {
          inherit name;
          command = lib.getExe s.package;
          # pi-lens appends --stdio when args is absent; the wrappers take none.
          args = [];
          extensions = builtins.attrNames s.extensions;
        })
      lspServers;
    };
  });

  subagentDir = "${pkgs.pi}/libexec/pi/examples/extensions/subagent";

  # pi's own sample roster, with the `model:` pin dropped: those ids are
  # Anthropic's and this machine defaults to openrouter, and an agent without
  # one inherits the dispatching session's model and thinking level. Derived
  # from the package rather than copied in so it tracks pi upgrades with the
  # extension that reads it.
  subagentAgents = pkgs.runCommand "pi-subagent-agents" {} ''
    mkdir -p $out
    for f in ${subagentDir}/agents/*.md; do
      sed '/^model:/d' "$f" >"$out/$(basename "$f")"
    done
  '';

  # Dispatcher workers resolve bare `pi` to this same wrapper; these load only
  # in interactive sessions.
  personalExtensions = lib.concatMapStringsSep " " (e: "-e ${e}") [
    "${localPkgs.pi-lens}/lib/node_modules/pi-lens"
    "${localPkgs.pi-vim}/lib/node_modules/pi-vim"
    "${localPkgs.pi-web-access}/lib/node_modules/pi-web-access"
    "${localPkgs.rpiv-todo}/lib/node_modules/@juicesharp/rpiv-todo"
    # Capture + D2 renders into the carousel. Its scripts resolve aeye,
    # tmux-claude-images and resvg from PATH (lazytmux's carouselDiagramTools)
    # and jq from the system profile. A worker writing the manifest would land
    # its images in the outer session's carousel (noamsto/aeye#235), so it
    # belongs here rather than loading unconditionally.
    "${aeye.tree}/adapters/pi/extensions/aeye.ts"
    # Delegation to child pi processes with their own context windows. Workers
    # are excluded deliberately: WORKER_PROTOCOL tells a pi worker it has no
    # native subagent mechanism, and dispatcher owns that claim.
    "${subagentDir}/index.ts"
  ];

  # pi rewrites ~/.pi/agent/settings.json itself, so nix can't own it. The
  # read-only layer rides on the CLI resource flags instead.
  #
  # ~/.claude/skills is a flat dir of per-skill symlinks (locally-authored
  # skills, the agent-skills bundle, and out-of-store ones); ~/.claude/commands
  # is the shared repo dir. pi follows symlinked skill dirs. Additive to pi's
  # own ~/.pi/agent/skills and any project .pi/skills / .agents/skills.
  #
  # exec -a pi: argv[0] so ps and tmux show `pi`, not the store wrapper.
  pi-wrapper = pkgs.writeShellScriptBin "pi" ''
    export PI_AGENT_HOOKS="${hookPaths}"
    personal=()
    if [ -z "''${CREW_WORKER_ID:-}" ]; then
      export PI_LENS_CONFIG_PATH=${piLensConfig}
      export PI_LENS_DISABLE_LSP_INSTALL=1
      export PI_LENS_DISABLE_TOOL_INSTALL=1
      personal=(${personalExtensions} --lens-guard --skill ${aeye.tree}/adapters/pi/skills --prompt-template ${subagentDir}/prompts)
    fi
    # "$@" is always last, so the caller's args are exactly the last $PI_USER_ARGC argv entries — lets tmux-og's resume stamp (noamsto/tmux-og#666) replay only those.
    export PI_USER_ARGC=$#
    exec -a pi ${pkgs.pi}/bin/pi \
      -e ${./hook-bridge.ts} \
      "''${personal[@]}" \
      --skill "$HOME/.claude/skills" \
      --skill ${xdg-claude}/context-efficient-tools/skills \
      --prompt-template "$HOME/.claude/commands" \
      "$@"
  '';

  # Workers get their settings.json from dispatcher, not this activation.
  managedSettings = {
    # grep/find/ls ship off by default.
    defaultTools = ["read" "bash" "edit" "write" "grep" "find" "ls"];
    defaultProvider = "openrouter";
    defaultModel = "deepseek/deepseek-v4.1-flash";
  };
in {
  home = {
    packages = [pi-wrapper];

    # Global instructions. pi's only machine-wide context channel: it reads
    # ~/.pi/agent/AGENTS.md plus AGENTS.md/CLAUDE.md walking up from cwd, and
    # does NOT expand the @import that pulls this file into ~/.claude/CLAUDE.md.
    # Out-of-store symlink so it stays editable, same file codex symlinks and
    # cursor loads as a rule.
    file = {
      ".pi/agent/AGENTS.md".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/AGENTS.shared.md";

      # The subagent extension resolves its roster as $PI_CODING_AGENT_DIR/agents
      # with no CLI flag to redirect it, so unlike the skills above this one
      # has to land in the home directory. `recursive` links each agent
      # individually rather than claiming ~/.pi/agent/agents as a whole —
      # that tree is pi's, and a directory symlink would fight it.
      #
      # Workers read a different $PI_CODING_AGENT_DIR (~/.pi/dispatcher-worker),
      # so this roster is invisible to them even if the extension ever leaked
      # past the interactive gate.
      ".pi/agent/agents" = {
        source = subagentAgents;
        recursive = true;
      };
    };

    # The Lemonade server on halo is not a provider pi ships, so its models
    # come from here. force = true because the hand-written file this replaces
    # is a regular file HM would otherwise refuse to clobber. A store path
    # rather than an out-of-store symlink: the symlink would resolve against
    # the main checkout, leaving a switch run from a worktree with a dangling
    # file.
    file.".pi/agent/models.json" = {
      source = ./models.json;
      force = true;
    };

    activation.piSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
      settings="$HOME/.pi/agent/settings.json"
      managed='${builtins.toJSON managedSettings}'
      if [ -f "$settings" ] && ! ${lib.getExe pkgs.jq} -e --argjson m "$managed" '(. + $m) == .' "$settings" >/dev/null; then
        run ${lib.getExe pkgs.jq} --argjson m "$managed" '. + $m' "$settings" \
          | run ${pkgs.moreutils}/bin/sponge "$settings"
      fi
    '';
  };
}
