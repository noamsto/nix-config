# Cursor CLI module with shared MCP configuration
{pkgs, ...}: let
  # Shared MCP server definitions (same as Claude Code)
  mcpServers = import ../mcp-servers.nix {inherit pkgs;};

  # Cursor-specific: add env var references since Cursor doesn't inherit shell env
  # Uses ${env:NAME} syntax that Cursor resolves at runtime
  cursorMcpServers =
    mcpServers.base
    // {
      tavily =
        mcpServers.base.tavily
        // {
          env = {
            TAVILY_API_KEY = "\${env:TAVILY_API_KEY}";
          };
        };
    };
in {
  home.packages = [pkgs.cursor-agent];

  # Generate cursor MCP config at ~/.cursor/mcp.json
  # Uses same base MCPs as Claude Code for consistent experience
  # Note: Cursor uses ~/.cursor (not ~/.config/cursor) for its config
  home.file.".cursor/mcp.json".text = builtins.toJSON {
    mcpServers = cursorMcpServers;
  };
}
