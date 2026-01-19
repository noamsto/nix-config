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
    # --mcp-config expects flat object: {serverName: {command/args/url/headers}}
    "amp/mcp-posthog.json".text = builtins.toJSON {
      posthog = helpers.mkNpxMcp {
        package = "mcp-remote@latest";
        args = [
          "https://mcp.posthog.com/sse"
          "--header"
          "Authorization: Bearer \${POSTHOG_PERSONAL_API_KEY}"
        ];
      };
    };

    # Frontend MCP: Playwright for browser automation and UI inspection
    # Note: Amp has built-in web browsing, but Playwright adds UI testing/automation
    "amp/mcp-playwright.json".text = builtins.toJSON {
      playwright = {
        command = "${pkgs.playwright-mcp}/bin/mcp-server-playwright";
        args = ["--executable-path" executable];
      };
    };

    # Notion MCP for documentation/knowledge base work
    "amp/mcp-notion.json".text = builtins.toJSON {
      Notion = {
        type = "http";
        url = "https://mcp.notion.com/mcp";
      };
    };
  };

  # Shell aliases (adds to base, allows project .mcp.json)
  programs.fish.shellAliases = {
    amp-analytics = "amp --mcp-config ~/.config/amp/mcp-posthog.json";
    amp-frontend = "amp --mcp-config ~/.config/amp/mcp-playwright.json";
    amp-docs = "amp --mcp-config ~/.config/amp/mcp-notion.json";
  };

  programs.bash.shellAliases = {
    amp-analytics = "amp --mcp-config ~/.config/amp/mcp-posthog.json";
    amp-frontend = "amp --mcp-config ~/.config/amp/mcp-playwright.json";
    amp-docs = "amp --mcp-config ~/.config/amp/mcp-notion.json";
  };
}
