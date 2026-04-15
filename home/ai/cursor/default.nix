# Cursor CLI module with shared MCP configuration
{
  pkgs,
  lib,
  ...
}: let
  mcpServers = import ../mcp-servers.nix {inherit pkgs lib;};
in {
  # TEMPORARILY DISABLED due to playwright-core collision with playwright-mcp
  # Both bundle playwright-core at $out/index.js causing build failure
  # home.packages = [pkgs.cursor-agent];

  # Generate cursor MCP config at ~/.cursor/mcp.json
  # Uses same base MCPs as Claude Code for consistent experience
  # Note: Cursor uses ~/.cursor (not ~/.config/cursor) for its config
  home.file.".cursor/mcp.json".text = builtins.toJSON {
    mcpServers = mcpServers.base;
  };
}
