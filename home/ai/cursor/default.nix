# Cursor CLI module with shared MCP configuration
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  mcpServers = import ../mcp-servers.nix {
    inherit pkgs lib;
    inherit (config.home) username;
  };

  # Reviewer agents, from the one store tree ../claude-code/agents.nix builds.
  agents = import ../claude-code/agents.nix {
    inherit pkgs lib;
    inherit (inputs) dispatcher;
  };

  aeye = import ../hookyard/aeye.nix {
    inherit pkgs;
    aeye = inputs.tmux-og.inputs.aeye;
  };
  aeye-cursor = "${aeye.tree}/adapters/cursor";

  # The dispatcher's cursor-worker backstop. Cursor exposes no session-end
  # event, so its `stop` (end-of-turn) hook stands in: `--turn-end` posts
  # `exited` for a worker that stopped without reporting, and leaves a
  # `blocked` one alone because that worker is waiting, not gone.
  #
  # Wrapped rather than pointed at directly, for two reasons. Hooks run with a
  # bare environment, and the script shells out to jq/git/tmux/dd. And aeye's
  # installer strips every hooks.json entry whose command contains
  # `/adapters/cursor/scripts/` — the dispatcher's script lives at exactly that
  # path, so a direct reference would be deleted on the next activation.
  dispatcherCursorNotify = pkgs.writeShellApplication {
    name = "dispatcher-cursor-notify";
    runtimeInputs = [pkgs.jq pkgs.git pkgs.tmux pkgs.coreutils pkgs.gnugrep];
    text = ''exec ${inputs.dispatcher}/adapters/cursor/scripts/dispatch-notify.sh "$@"'';
  };
in {
  home = {
    # Cursor CLI (`cursor-agent`). Auth is out of band — run
    # `cursor-agent login` once; there's no secret to manage in Nix.
    packages = [pkgs.cursor-agent];

    file = {
      # Generate cursor MCP config at ~/.cursor/mcp.json
      # Uses same base MCPs as Claude Code for consistent experience, excluding
      # Firefox DevTools — cursor-agent has no per-invocation MCP-config flag so
      # this single shared file also serves dispatched cursor workers (no separate
      # worker profile — the launch passes --approve-mcps for headless
      # auto-approval). Firefox DevTools attaches to the owner's logged-in Firefox
      # and is excluded because dispatched workers get a separate headless browser
      # CLI from the dispatcher instead.
      # Note: Cursor uses ~/.cursor (not ~/.config/cursor) for its config
      ".cursor/mcp.json".text = builtins.toJSON {
        mcpServers = builtins.removeAttrs mcpServers.base ["firefox-devtools"];
      };

      # Global instructions. `~/.cursor/rules/*.mdc` is cursor's user-level rule
      # directory — the file is silently ignored unless it carries
      # `alwaysApply: true` frontmatter, which AGENTS.shared.md provides. Symlinks
      # are followed, so this points at the same file claude imports and codex reads
      # as ~/.codex/AGENTS.md. Out-of-store to stay editable without a rebuild.
      ".cursor/rules/shared-conventions.mdc".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/AGENTS.shared.md";

      # Same reviewer/specialist agents as Claude Code / Codex. Cursor docs also
      # read ~/.claude/agents, but the CLI only reliably discovers project-level
      # agents; user-level ~/.cursor/agents still helps the IDE and keeps the
      # three harnesses on one source of truth.
      ".cursor/agents".source = agents;
    };

    # aeye's Cursor adapter (noamsto/aeye#169): merge its hook entries into
    # ~/.cursor/hooks.json. Runs on EVERY activation, unlike the marker-guarded
    # codex blocks — install.sh strips prior aeye entries (matched on
    # /adapters/cursor/scripts/ in the command) and re-appends pointing at the
    # current store path, so an aeye bump never leaves dangling hook commands.
    # aeye.tree has no postToolUse rows (those route through hookyard), so this
    # writes sessionStart entries only. Unrelated user entries are preserved;
    # a malformed hooks.json fails the merge loudly instead of clobbering.
    # install.sh also links the aeye-diagrams / aeye-image-gallery skills into
    # ~/.cursor/skills. Hooks find `aeye` + `resvg` on PATH via lazytmux's
    # carouselDiagramTools. PATH is pinned for the activation env, which
    # doesn't guarantee jq.
    activation = {
      aeyeCursorHooks = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run env PATH="${lib.makeBinPath [pkgs.jq pkgs.coreutils]}:$PATH" ${aeye-cursor}/install.sh
      '';

      # Merge the dispatcher's `stop` hook into the same shared hooks.json.
      # aeye, hookyard and this merger each strip only their own marker before
      # re-appending, so they commute and need no ordering.
      dispatcherCursorStopHook = lib.hm.dag.entryAfter ["writeBoundary"] ''
        hooks_file="$HOME/.cursor/hooks.json"
        run mkdir -p "$HOME/.cursor"
        if [ -f "$hooks_file" ]; then
          ${pkgs.jq}/bin/jq empty "$hooks_file" >/dev/null 2>&1 || {
            echo "dispatcherCursorStopHook: $hooks_file is not valid JSON — refusing to rewrite it" >&2
            exit 1
          }
        else
          echo '{"version":1,"hooks":{}}' >"$hooks_file"
        fi
        run ${pkgs.jq}/bin/jq --arg cmd "${lib.getExe dispatcherCursorNotify} --turn-end" '
          (.version //= 1)
          | .hooks.stop = (
              ((.hooks.stop // []) | map(select(
                (.command | type) != "string"
                or (.command | contains("dispatcher-cursor-notify") | not)
              )))
              + [{command: $cmd, timeout: 15}]
            )
        ' "$hooks_file" >"$hooks_file.tmp"
        run mv "$hooks_file.tmp" "$hooks_file"
      '';

      # Cursor Agent follows XDG_CONFIG_HOME when it is set. Merge these
      # settings so the CLI can retain every other user-managed preference.
      # Attribution is injected by the agent's own commit/PR path, not by the
      # model, so an always-apply rule cannot suppress it; only this opt-out can.
      cursorAgentCliConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/cursor"
        config="$config_dir/cli-config.json"
        run mkdir -p "$config_dir"
        if [ -f "$config" ]; then
          run ${pkgs.jq}/bin/jq '(.version //= 1) | .editor.vimMode = true | .attribution.attributeCommitsToAgent = false | .attribution.attributePRsToAgent = false' "$config" > "$config.tmp"
          run mv "$config.tmp" "$config"
        else
          run install -Dm644 ${pkgs.writeText "cursor-agent-cli-config.json" (builtins.toJSON {
          version = 1;
          editor.vimMode = true;
          attribution = {
            attributeCommitsToAgent = false;
            attributePRsToAgent = false;
          };
        })} "$config"
        fi
      '';
    };
  };
}
