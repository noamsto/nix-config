# Shared MCP server definitions for AI tools (Claude Code, Cursor, etc.)
# Single source of truth - import this in each tool's module
{pkgs}: let
  helpers = import ./mcp-helpers.nix {inherit pkgs;};
in {
  # Base MCPs - always loaded by all AI tools
  base = {
    context7 = {
      command = "${pkgs.context7-mcp}/bin/context7-mcp";
      args = [];
      env = {};
    };

    tavily = {
      command = "${pkgs.tavily-mcp}/bin/tavily-mcp";
      args = [];
      env = {};
    };

    linear = {
      type = "http";
      url = "https://mcp.linear.app/mcp";
    };
  };

  # Optional MCPs (heavy/specialized) - load via profiles or on-demand
  optional = {
    playwright = helpers.mkNpxMcp {
      package = "@anthropic-ai/mcp-playwright@latest";
    };

    posthog = helpers.mkNpxMcp {
      package = "mcp-remote@latest";
      args = ["https://mcp.posthog.com/sse" "--header" "Authorization: Bearer \${POSTHOG_PERSONAL_API_KEY}"];
    };
  };

  # Re-export helpers for use in tool-specific configs
  inherit helpers;
}
