{
  config,
  pkgs,
  lib,
  ...
}: let
  executable = lib.getExe pkgs.chromium;
in {
  # Generate additional MCP configs (add to base MCPs)
  xdg.configFile = {
    # PostHog MCP for analytics work
    "claude-code/mcp-posthog.json".text = builtins.toJSON {
      mcpServers = {
        posthog = {
          command = "${pkgs.nodejs}/bin/npx";
          args = [
            "-y"
            "mcp-remote@latest"
            "https://mcp.posthog.com/sse"
            "--header"
            "Authorization: Bearer \${POSTHOG_PERSONAL_API_KEY}"
          ];
          env = {
            PATH = "${pkgs.lib.makeBinPath [pkgs.nodejs pkgs.bash pkgs.coreutils]}";
          };
        };
      };
    };

    # Playwright MCP for frontend work
    "claude-code/mcp-playwright.json".text = builtins.toJSON {
      mcpServers = {
        playwright = {
          command = "${pkgs.playwright-mcp}/bin/mcp-server-playwright";
          args = ["--executable-path" executable];
        };
      };
    };
  };

  # Shell aliases (adds to base, allows project .mcp.json)
  programs.fish.shellAliases = {
    claude-analytics = "claude --mcp-config ~/.config/claude-code/mcp-posthog.json";
    claude-frontend = "claude --mcp-config ~/.config/claude-code/mcp-playwright.json";
  };

  programs.bash.shellAliases = {
    claude-analytics = "claude --mcp-config ~/.config/claude-code/mcp-posthog.json";
    claude-frontend = "claude --mcp-config ~/.config/claude-code/mcp-playwright.json";
  };
}
