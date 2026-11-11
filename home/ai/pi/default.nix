{inputs, ...}: {
  config,
  pkgs,
  lib,
  osConfig,
  ...
}: let
  isLocalServer = osConfig.nix-config.ai.localServer.enable;
  inherit (osConfig.nix-config.ai.pi) modelsFile;
  inherit (osConfig.nix-config.ai.openrouter) keyFile;
  openrouterAuth = pkgs.writeShellApplication {
    name = "pi-openrouter-auth";
    runtimeInputs = [pkgs.jq pkgs.coreutils];
    text = builtins.readFile ./openrouter-auth.sh;
  };

  piGuards = import ./guards.nix {
    inherit pkgs;
    inherit (inputs) dispatcher;
  };
  lspServers = import ../lsp-servers.nix {inherit pkgs;};
  localPkgs = inputs.self.packages.${pkgs.stdenv.hostPlatform.system};

  # The one switch: when true, the interactive `pi` command runs Pi-Bolt.
  # Set to false to restore the stock-pi wrapper exactly.
  piBoltAsPi = true;
  # The Pi-Bolt binary, defined once; `pi` (when switched on) and `pi-bolt` share it.
  piBoltBin = lib.getExe localPkgs.pi-bolt-compiled;

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

  # Dispatcher workers resolve bare `pi` to this same wrapper (stock pi even
  # when piBoltAsPi is on, since CREW_WORKER_ID is set); these load only in
  # interactive sessions.
  # pi-lens, pi-vim, pi-web-access and rpiv-todo: defined in packages/default.nix
  # and compiled into Pi-Bolt there; everything below loads from its files.
  baseExtensions =
    localPkgs.pi-bolt-compiled.compiledExtensions
    ++ [
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
  # Reports run state to houston over its local socket, in order. Interactive
  # sessions only, like the rest of this list: workers keep the hook path.
  extensions =
    baseExtensions
    ++ lib.optional osConfig.agentDashboard.enable "${inputs.houston}/contrib/pi-mod/houston.ts";
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
  #
  # mkPiWrapper wraps either build: pi (pkgs.pi) or the ahead-of-time compiled
  # pi-bolt, which reads the same ~/.pi/agent config. With boltBin set, the
  # non-subcommand launch runs boltBin when CREW_WORKER_ID is empty (interactive)
  # and bin otherwise (workers); with boltBin null the script is unchanged.
  # PI_BOLT_ARGV0 makes the pi-bolt shim keep argv[0] as `pi`, so tmux-og's
  # pane_current_command match (pi) still recognises the process.
  mkPiWrapper = {
    name,
    bin,
    boltBin ? null,
    extraSubcommands ? "",
  }:
    pkgs.writeTextFile {
      inherit name;
      executable = true;
      destination = "/bin/${name}";
      # A moved upstream path otherwise surfaces only as pi refusing to start.
      meta.mainProgram = name;
      checkPhase = "${pkgs.runtimeShell} -n \"$target\"\n" + lib.concatMapStringsSep "\n" (e: "test -e ${e} || { echo 'missing pi extension: ${e}' >&2; exit 1; }") extensions;
      text = ''
        #!${pkgs.runtimeShell}
        # Pass pi subcommands straight to the real binary — the injected --skill / --prompt-template
        # flags put options before the subcommand, which pi rejects (subcommand must be argv[1]).
        case "''\${1:-}" in
          install|remove|uninstall|update|list|config|auth|mcp${extraSubcommands})
            exec -a ${name} ${bin} "$@"
            ;;
        esac
        personal=()
        if [ -z "''${CREW_WORKER_ID:-}" ]; then
          export PI_LENS_CONFIG_PATH=${piLensConfig}
          export PI_LENS_DISABLE_LSP_INSTALL=1
          export PI_LENS_DISABLE_TOOL_INSTALL=1
          personal=(${personalExtensions} --lens-guard --skill ${aeye.tree}/adapters/pi/skills --prompt-template ${subagentDir}/prompts)${lib.optionalString (config.programs.dispatcher.agentBrowser.package != null) ''

          personal+=(--skill ${config.home.sessionVariables.DISPATCHER_SKILLS_DIR}/agent-browser)''}
        fi
        # "$@" is always last, so the caller's args are exactly the last $PI_USER_ARGC argv entries — lets tmux-og's resume stamp (noamsto/tmux-og#666) replay only those.
        export PI_USER_ARGC=$#${lib.optionalString (boltBin != null) ''

          bin=${bin}
          if [ -z "''${CREW_WORKER_ID:-}" ]; then
            bin=${boltBin}
            export PI_BOLT_ARGV0=${name}
          fi''}
        exec -a ${name} ${
          if boltBin == null
          then bin
          else ''"$bin"''
        } \
          "''${personal[@]}" \
          --skill "$HOME/.claude/skills" \
          --skill ${xdg-claude}/context-efficient-tools/skills \
          --prompt-template "$HOME/.claude/commands" \
          "$@"
      '';
    };

  pi-wrapper = mkPiWrapper {
    name = "pi";
    bin = "${pkgs.pi}/bin/pi";
    boltBin =
      if piBoltAsPi
      then piBoltBin
      else null;
  };

  # Always available by name, whatever piBoltAsPi says.
  pi-bolt-wrapper = mkPiWrapper {
    name = "pi-bolt";
    bin = piBoltBin;
    extraSubcommands = "|service|doctor|compile";
  };

  # Workers get their settings.json from dispatcher, not this activation.
  managedSettings = {
    # grep/find/ls ship off by default.
    defaultTools = ["read" "bash" "edit" "write" "grep" "find" "ls"];
    defaultProvider =
      if isLocalServer
      then "Lemonade"
      else "openrouter";
    defaultModel =
      if isLocalServer
      then "Qwen3.8-Flash-Next-Strata"
      else "deepseek/deepseek-v4.1-flash-1017";
  };
in {
  assertions = [
    {
      assertion = !isLocalServer || modelsFile != null;
      message = "nix-config.ai.localServer.enable needs nix-config.ai.pi.modelsFile: pi's default provider (Lemonade) is defined only there.";
    }
  ];

  # The tool-call guards, as hookyard yard-mode `pre_tool` handlers (./guards.nix),
  # plus the dispatcher's own pi handlers generated from its hookyard.json. Both
  # are plain manifests: ../hookyard owns `enable` and the install pass and this
  # contributes manifest paths and nothing else. It also decides which pi settings
  # dirs the bridge lands in — both the ambient one and the dispatcher worker's.
  programs.hookyard.manifests = [piGuards.manifest piGuards.dispatcherManifest];

  home = {
    packages = [pi-wrapper pi-bolt-wrapper];

    # Global instructions. pi's only machine-wide context channel: it reads
    # ~/.pi/agent/AGENTS.md plus AGENTS.md/CLAUDE.md walking up from cwd, and
    # does NOT expand the @import that pulls this file into ~/.claude/CLAUDE.md.
    # Out-of-store symlink so it stays editable, same file codex symlinks and
    # cursor loads as a rule.
    file = {
      ".pi/agent/AGENTS.md".source =
        config.lib.file.mkOutOfStoreSymlink "${osConfig.nix-config.checkoutPath}/home/ai/AGENTS.shared.md";

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

      # pi-web-access defaults `workflow` to `summary-review`, which opens the
      # browser curator with a generated draft on every search. Keep it text-only.
      # This path is also the extension's credential store, so provider keys
      # belong in env vars rather than in a file nix owns.
      ".config/pi/web-search.json".text = builtins.toJSON {workflow = "none";};
    };

    # A local Lemonade server is not a provider pi ships, so its models come
    # from a host-supplied file. force = true because the hand-written file
    # this replaces is a regular file HM would otherwise refuse to clobber. A
    # store path rather than an out-of-store symlink: the symlink would resolve
    # against the main checkout, leaving a switch run from a worktree with a
    # dangling file. The local-server default (Strata) is set in managedSettings
    # above; the 27B and gpt-oss-120b cannot load beside the pinned Strata (not
    # enough RAM), so using them means unloading Strata first.
    file.".pi/agent/models.json" = lib.mkIf (modelsFile != null) {
      source = modelsFile;
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

    # pi rewrites auth.json itself, so Nix cannot own it; this upserts only the
    # openrouter entry. The key never enters the file, only a `!cat` of its path.
    # Dispatcher workers use ~/.pi/dispatcher-worker, whose auth.json crew links
    # to the interactive one (the script writes through the link); a regular
    # file left there before crew first seeds the dir is replaced by that link.
    activation.piOpenrouterAuth = lib.mkIf (keyFile != null) (lib.hm.dag.entryAfter ["writeBoundary"] ''
      run ${lib.getExe openrouterAuth} ${lib.escapeShellArg keyFile} "$HOME/.pi/agent/auth.json"
      run ${lib.getExe openrouterAuth} ${lib.escapeShellArg keyFile} "$HOME/.pi/dispatcher-worker/auth.json"
    '');
  };
}
