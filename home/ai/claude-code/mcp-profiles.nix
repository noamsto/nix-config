{
  pkgs,
  lib,
  config,
  ...
}: let
  mcpServers = import ../mcp-servers.nix {
    inherit pkgs lib;
    inherit (config.home) username;
  };

  mcpAliases = {
    claude-frontend = "claude --mcp-config ~/.config/claude-code/mcp-playwright.json";
  };
in {
  # Generate additional MCP configs (add to base MCPs)
  xdg.configFile = {
    # Frontend MCP: Playwright for browser automation and UI inspection
    "claude-code/mcp-playwright.json".text = builtins.toJSON {
      mcpServers = {
        inherit (mcpServers.base) playwright;
      };
    };
  };

  # Shell aliases (adds to base, allows project .mcp.json)
  programs.fish.shellAliases = mcpAliases;
  programs.bash.shellAliases = mcpAliases;
}
