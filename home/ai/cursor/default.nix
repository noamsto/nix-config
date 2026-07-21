# Cursor CLI module with shared MCP configuration
{
  pkgs,
  lib,
  ...
}: let
  mcpServers = import ../mcp-servers.nix {inherit pkgs lib;};
in {
  # Cursor CLI (`cursor-agent`). Used both interactively and as an alternate
  # work-profile `dispatch` worker engine (`dispatch … --agent cursor …`, gated
  # in dispatch.sh). Auth is out of band — run `cursor-agent login` once; there's
  # no secret to manage in Nix.
  home.packages = [pkgs.cursor-agent];

  # Generate cursor MCP config at ~/.cursor/mcp.json
  # Uses same base MCPs as Claude Code for consistent experience.
  # cursor-agent has no per-invocation MCP-config flag, so this single shared
  # file also serves dispatched cursor workers (no separate worker profile —
  # the launch passes --approve-mcps for headless auto-approval).
  # Note: Cursor uses ~/.cursor (not ~/.config/cursor) for its config
  home.file.".cursor/mcp.json".text = builtins.toJSON {
    mcpServers = mcpServers.base;
  };
}
