{
  config,
  pkgs,
  lib,
  inputs,
  osConfig,
  ...
}: let
  isHalo = osConfig.hostname == "halo";

  piGuards = import ./guards.nix {
    inherit pkgs;
    inherit (inputs) dispatcher;
  };
  lspServers = import ../lsp-servers.nix {inherit pkgs;};
  localPkgs = inputs.self.packages.${pkgs.stdenv.hostPlatform.system};

  # aeye's pi adapter, a self-contained hookyard "build mode" package: its own
  # bin/hookyard router and table cover session_start guidance/reset, resume
  # backfill, post_tool capture and the /aeye command. It never touches the
  # yard state the ../hookyard install pass writes (the manifest there has no
  # pi handlers for aeye), so it neither double-routes nor conflicts with the
  # guards' yard bridge. Imported from ../hookyard/aeye.nix so every consumer
  # shares one derivation — its PostToolUse stripping touches the other
  # adapters' hooks.json, never adapters/pi.
  aeye = import ../hookyard/aeye.nix {
    inherit pkgs;
    aeye = inputs.tmux-og.inputs.aeye;
  };

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
  extensions = [
    "${localPkgs.pi-lens}/lib/node_modules/pi-lens"
    "${localPkgs.pi-vim}/lib/node_modules/pi-vim"
    "${localPkgs.pi-web-access}/lib/node_modules/pi-web-access"
    "${localPkgs.rpiv-todo}/lib/node_modules/@juicesharp/rpiv-todo"
    # Capture + D2 renders into the carousel. Its scripts resolve aeye,
    # tmux-claude-images and resvg from PATH (lazytmux's carouselDiagramTools)
    # and jq from the system profile. A worker writing the manifest would land
    # its images in the outer session's carousel (noamsto/aeye#235), so it
    # belongs here rather than loading unconditionally.
    "${aeye.tree}/adapters/pi"
    # Delegation to child pi processes with their own context windows. Workers
    # are excluded deliberately: WORKER_PROTOCOL tells a pi worker it has no
    # native subagent mechanism, and dispatcher owns that claim.
    "${subagentDir}/index.ts"
  ];
  personalExtensions = lib.concatMapStringsSep " " (e: "-e ${e}") extensions;

  # pi rewrites ~/.pi/agent/settings.json itself, so nix can't own it. The
  # read-only layer rides on the CLI resource flags instead.
  #
  # ~/.claude/skills is a flat dir of per-skill symlinks (locally-authored
  # skills, the agent-skills bundle, and out-of-store ones); ~/.claude/commands
  # is the shared repo dir. pi follows symlinked skill dirs. Additive to pi's
  # own ~/.pi/agent/skills and any project .pi/skills / .agents/skills (nix-config's
  # repo-specific skills live in .agents/skills, symlinked into .claude/skills).
  #
  # exec -a pi: argv[0] so ps and tmux show `pi`, not the store wrapper.
  pi-wrapper = pkgs.writeTextFile {
    name = "pi";
    executable = true;
    destination = "/bin/pi";
    # A moved upstream path otherwise surfaces only as pi refusing to start.
    meta.mainProgram = "pi";
    checkPhase = "${pkgs.runtimeShell} -n \"$target\"\n" + lib.concatMapStringsSep "\n" (e: "test -e ${e} || { echo 'missing pi extension: ${e}' >&2; exit 1; }") extensions;
    text = ''
      #!${pkgs.runtimeShell}
      # Pass pi subcommands straight to the real binary — the injected --skill / --prompt-template
      # flags put options before the subcommand, which pi rejects (subcommand must be argv[1]).
      case "''\${1:-}" in
        install|remove|uninstall|update|list|config|auth|mcp)
          exec -a pi ${pkgs.pi}/bin/pi "$@"
          ;;
      esac
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
        "''${personal[@]}" \
        --skill "$HOME/.claude/skills" \
        --skill ${xdg-claude}/context-efficient-tools/skills \
        --prompt-template "$HOME/.claude/commands" \
        "$@"
    '';
  };

  # Workers get their settings.json from dispatcher, not this activation.
  managedSettings = {
    # grep/find/ls ship off by default.
    defaultTools = ["read" "bash" "edit" "write" "grep" "find" "ls"];
    defaultProvider =
      if isHalo
      then "Lemonade"
      else "openrouter";
    defaultModel =
      if isHalo
      then "Qwen3.8-Flash-Next-MTP"
      else "deepseek/deepseek-v4.1-flash";
  };
in {
  # The tool-call guards, as hookyard yard-mode `pre_tool` handlers (./guards.nix).
  # ../hookyard owns `enable` and the install pass; this contributes a manifest
  # path and nothing else. It also decides which pi settings dirs the bridge
  # lands in — both the ambient one and the dispatcher worker's.
  programs.hookyard.manifests = [piGuards.manifest];

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
    # file. The halo default (Flash-Next) is set in managedSettings above; the
    # 27B and gpt-oss-120b cannot load beside the pinned Flash-Next (not enough
    # RAM), so using them means unloading Flash-Next first.
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
