{
  pkgs,
  lib,
  ...
}: let
  executable = lib.getExe pkgs.chromium;
  helpers = import ../mcp-helpers.nix {inherit pkgs;};
in {
  # Generate additional MCP configs (add to base MCPs)
  xdg.configFile = {
    # PostHog MCP for analytics work
    "claude-code/mcp-posthog.json".text = builtins.toJSON {
      mcpServers = {
        posthog = helpers.mkNpxMcp {
          package = "mcp-remote@latest";
          args = [
            "https://mcp.posthog.com/sse"
            "--header"
            "Authorization: Bearer \${POSTHOG_PERSONAL_API_KEY}"
          ];
        };
      };
    };

    # Frontend MCPs: Playwright + Chrome DevTools
    "claude-code/mcp-playwright.json".text = builtins.toJSON {
      mcpServers = {
        playwright = {
          command = "${pkgs.playwright-mcp}/bin/mcp-server-playwright";
          args = ["--executable-path" executable];
        };
        chrome-devtools = helpers.mkNpxMcp {
          package = "chrome-devtools-mcp@latest";
        };
      };
    };

    # Notion MCP for documentation/knowledge base work
    "claude-code/mcp-notion.json".text = builtins.toJSON {
      mcpServers = {
        Notion = {
          type = "http";
          url = "https://mcp.notion.com/mcp";
        };
      };
    };
  };

  # Shell aliases (adds to base, allows project .mcp.json)
  programs.fish.shellAliases = {
    claude-analytics = "claude --mcp-config ~/.config/claude-code/mcp-posthog.json";
    claude-frontend = "claude --mcp-config ~/.config/claude-code/mcp-playwright.json";
    claude-docs = "claude --mcp-config ~/.config/claude-code/mcp-notion.json";
  };

  programs.bash.shellAliases = {
    claude-analytics = "claude --mcp-config ~/.config/claude-code/mcp-posthog.json";
    claude-frontend = "claude --mcp-config ~/.config/claude-code/mcp-playwright.json";
    claude-docs = "claude --mcp-config ~/.config/claude-code/mcp-notion.json";
  };
}
