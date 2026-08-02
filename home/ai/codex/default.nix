{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  mcpServers = import ../mcp-servers.nix {inherit pkgs lib;};
  tomlFormat = pkgs.formats.toml {};

  # This whole module is work-only (gated in home/ai/default.nix), so the
  # remote MCPs — all work tools — ride along ungated. OAuth logins happen
  # interactively (`codex mcp login <name>`); workers reuse the stored tokens.
  codexRemoteMcp = lib.mapAttrs (_: mcpServers.toCodex) mcpServers.remote;
  codexMcpSnippet = name:
    tomlFormat.generate "codex-mcp-${name}.toml" {mcp_servers.${name} = codexRemoteMcp.${name};};

  worker-config = tomlFormat.generate "codex-worker.config.toml" {
    mcp_servers = mcpServers.base // codexRemoteMcp;
  };

  aeye-plugin = "${inputs.lazytmux.inputs.aeye}/adapters/codex/plugin";
  aeye-version = (lib.importJSON "${aeye-plugin}/.codex-plugin/plugin.json").version;
  aeye-cache = ".codex/plugins/cache/aeye/aeye";
in {
  home = {
    # OpenAI Codex CLI. Used both interactively and as an alternate `dispatch`
    # worker engine (`dispatch … --agent codex …`). Auth is out of band — run
    # `codex login` once; there's no secret to manage in Nix.
    packages = [pkgs.codex];

    # Global instructions — codex's only machine-wide channel, read ahead of any
    # project AGENTS.md. Out-of-store symlink so it stays editable, pointing at
    # the file claude imports and cursor loads as a rule.
    file = {
      ".codex/AGENTS.md".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/AGENTS.shared.md";

      # Same reviewer/specialist agents as Claude Code / Cursor (one tree under
      # home/ai/claude-code/agents). Codex loads ~/.codex/agents for user scope.
      ".codex/agents".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/claude-code/agents";
    };

    # Worker MCP profile. `dispatch … --agent codex` launches with
    # `--profile worker`, which layers this file on top of the hand-managed
    # ~/.codex/config.toml (model, trust levels, NUX) without clobbering it. It
    # gives dispatched codex workers the same base MCP stack as claude workers,
    # from the single mcp-servers.nix source. Cheap by construction: codex defers
    # tool schemas and browsers launch lazily, so the servers cost ~nothing until
    # a task actually uses one.
    #
    # Writable copy, not a `home.file` symlink: codex writes TUI config changes
    # back to the topmost layer, so a store symlink fails it — "failed to persist
    # config at /nix/store/…". Wiped on each switch, which is fine: dispatch
    # passes model and effort as explicit flags.
    activation = {
      codexWorkerProfile = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run rm -f "$HOME/.codex/worker.config.toml"
        run install -Dm644 ${worker-config} "$HOME/.codex/worker.config.toml"
      '';

      # Interactive codex reads only ~/.codex/config.toml (profiles layer on
      # top), so MCP parity for interactive sessions means merging the same
      # mcp_servers into the hand-managed file. Append-only, one grep-guarded
      # stanza per server: codex rewrites this file when persisting TUI state,
      # so a marker-block replace would fight it. To pick up a changed server
      # definition, `codex mcp remove <name>` and switch again.
      codexMcpServers = lib.hm.dag.entryAfter ["writeBoundary"] ''
        config="$HOME/.codex/config.toml"
        run mkdir -p "$HOME/.codex"
        if [ ! -f "$config" ]; then
          run install -Dm644 /dev/null "$config"
        fi
        ${lib.concatMapStringsSep "\n" (name: ''
          if ! grep -q '^\[mcp_servers\.${name}\]' "$config"; then
            run sh -c 'printf "\n" >> "$2" && cat "$1" >> "$2"' sh ${codexMcpSnippet name} "$config"
          fi
        '') (builtins.attrNames codexRemoteMcp)}
      '';

      # Keep modal editing enabled without taking ownership of config.toml: Codex
      # persists authentication, trusted projects, and plugin state in this file.
      codexVimMode = lib.hm.dag.entryAfter ["writeBoundary"] ''
        config="$HOME/.codex/config.toml"
        run mkdir -p "$HOME/.codex"
        if [ ! -f "$config" ]; then
          run install -Dm644 /dev/null "$config"
        fi
        if grep -q '^vim_mode_default =' "$config"; then
          run sed -i 's/^vim_mode_default = .*/vim_mode_default = true/' "$config"
        elif grep -q '^\[tui\]$' "$config"; then
          run sed -i '/^\[tui\]$/a vim_mode_default = true' "$config"
        else
          run sh -c 'printf "\\n[tui]\\nvim_mode_default = true\\n" >> "$1"' sh "$config"
        fi
      '';

      # aeye's Codex adapter — the counterpart to the `--plugin-dir` the claude
      # wrapper passes. Codex has no such flag and loads plugins only from a real
      # directory under ~/.codex/plugins/cache: a symlinked tree still reports
      # "installed, enabled" in `codex plugin list` while its skills never reach
      # the model. Modes carry over because hooks.json execs scripts/*.sh
      # directly; the chmod lets the next switch replace the read-only tree.
      #
      # The matching `[marketplaces.aeye]` / `[plugins."aeye@aeye"]` stanzas are
      # hand-managed in ~/.codex/config.toml — no store path, so not Nix's.
      aeyeCodexPlugin = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run rm -rf "$HOME/${aeye-cache}"
        run mkdir -p "$HOME/${aeye-cache}"
        run cp -rL ${aeye-plugin} "$HOME/${aeye-cache}/${aeye-version}"
        run chmod -R u+w "$HOME/${aeye-cache}"
      '';
    };
  };
}
