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

      groundcover = {
        command = "npx";
        args = [
          "-y"
          "mcp-remote@0.1.30"
          "https://mcp.groundcover.com/api/mcp"
          "54278"
          "--header"
          "X-Timezone:Asia/Jerusalem"
          "--header"
          "X-Tenant-UUID:f9cea478-4af0-451b-b226-c05829b9f8ea"
          "--header"
          "X-Backend-Id:groundcover"
        ];
        env = {};
      };
    };
  };
}
