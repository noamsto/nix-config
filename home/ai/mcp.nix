# Centralized MCP server definitions
{pkgs, ...}: {
  programs.mcp = {
    enable = true;
    servers = {
      context7 = {
        command = "${pkgs.context7-mcp}/bin/context7-mcp";
        args = [];
        env = {};
      };

      tavily = {
        command = "${pkgs.tavily-mcp}/bin/tavily-mcp";
        args = [];
        env = {
          # TAVILY_API_KEY is set via agenix secrets for the user
        };
      };
    };
  };
}
