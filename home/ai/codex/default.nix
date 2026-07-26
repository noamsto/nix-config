{
  pkgs,
  lib,
  inputs,
  ...
}: let
  mcpServers = import ../mcp-servers.nix {inherit pkgs lib;};
  tomlFormat = pkgs.formats.toml {};

  aeye-plugin = "${inputs.lazytmux.inputs.aeye}/adapters/codex/plugin";
  aeye-version = (lib.importJSON "${aeye-plugin}/.codex-plugin/plugin.json").version;
  aeye-cache = ".codex/plugins/cache/aeye/aeye";
in {
  home = {
    # OpenAI Codex CLI. Used both interactively and as an alternate `dispatch`
    # worker engine (`dispatch … --agent codex …`). Auth is out of band — run
    # `codex login` once; there's no secret to manage in Nix.
    packages = [pkgs.codex];

    # Worker MCP profile. `dispatch … --agent codex` launches with
    # `--profile worker`, which layers this file on top of the hand-managed
    # ~/.codex/config.toml (model, trust levels, NUX) without clobbering it. It
    # gives dispatched codex workers the same base MCP stack as claude workers,
    # from the single mcp-servers.nix source. Cheap by construction: codex defers
    # tool schemas and browsers launch lazily, so the servers cost ~nothing until
    # a task actually uses one.
    file.".codex/worker.config.toml".source = tomlFormat.generate "codex-worker.config.toml" {
      mcp_servers = mcpServers.base;
    };

    # aeye's Codex adapter — the counterpart to the `--plugin-dir` the claude
    # wrapper passes. Codex has no such flag and loads plugins only from a real
    # directory under ~/.codex/plugins/cache: a symlinked tree still reports
    # "installed, enabled" in `codex plugin list` while its skills never reach
    # the model. Modes carry over because hooks.json execs scripts/*.sh
    # directly; the chmod lets the next switch replace the read-only tree.
    #
    # The matching `[marketplaces.aeye]` / `[plugins."aeye@aeye"]` stanzas are
    # hand-managed in ~/.codex/config.toml — no store path, so not Nix's.
    activation.aeyeCodexPlugin = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run rm -rf "$HOME/${aeye-cache}"
      run mkdir -p "$HOME/${aeye-cache}"
      run cp -rL ${aeye-plugin} "$HOME/${aeye-cache}/${aeye-version}"
      run chmod -R u+w "$HOME/${aeye-cache}"
    '';
  };
}
