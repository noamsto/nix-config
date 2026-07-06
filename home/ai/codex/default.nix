{
  pkgs,
  lib,
  ...
}: let
  mcpServers = import ../mcp-servers.nix {inherit pkgs lib;};
  tomlFormat = pkgs.formats.toml {};
in {
  # OpenAI Codex CLI. Used both interactively and as an alternate `dispatch`
  # worker engine (`dispatch … --agent codex …`). Auth is out of band — run
  # `codex login` once; there's no secret to manage in Nix.
  home.packages = [pkgs.codex];

  # Worker MCP profile. `dispatch … --agent codex` launches with
  # `--profile worker`, which layers this file on top of the hand-managed
  # ~/.codex/config.toml (model, trust levels, NUX) without clobbering it. It
  # gives dispatched codex workers the same base MCP stack as claude workers,
  # from the single mcp-servers.nix source. Cheap by construction: codex defers
  # tool schemas and browsers launch lazily, so the servers cost ~nothing until
  # a task actually uses one.
  home.file.".codex/worker.config.toml".source = tomlFormat.generate "codex-worker.config.toml" {
    mcp_servers = mcpServers.base;
  };
}
