# Cursor CLI module with shared MCP configuration
{
  pkgs,
  lib,
  ...
}: let
  # Shared MCP server definitions (same as Claude Code)
  mcpServers = import ../mcp-servers.nix {inherit pkgs;};
in {
  home.packages = [pkgs.cursor-agent];

  # Generate cursor MCP config at ~/.cursor/mcp.json
  # Uses same base MCPs as Claude Code for consistent experience
  xdg.configFile."cursor/mcp.json".text = builtins.toJSON {
    mcpServers = mcpServers.base;
  };
}
