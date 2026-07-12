{
  pkgs,
  lib,
  osConfig,
  ...
}: let
  mcpServers = import ../mcp-servers.nix {inherit pkgs lib;};

  mcpAliases =
    {
      claude-frontend = "claude --mcp-config ~/.config/claude-code/mcp-playwright.json";
    }
    // lib.optionalAttrs (osConfig.profile == "work") {
      claude-analytics = "claude --mcp-config ~/.config/claude-code/mcp-posthog.json";
    };
in {
  # Generate additional MCP configs (add to base MCPs)
  xdg.configFile =
    {
      # Frontend MCP: Playwright for browser automation and UI inspection
      "claude-code/mcp-playwright.json".text = builtins.toJSON {
        mcpServers = {
          inherit (mcpServers.base) playwright;
        };
      };
    }
    // lib.optionalAttrs (osConfig.profile == "work") {
      # PostHog MCP for analytics work
      "claude-code/mcp-posthog.json".text = builtins.toJSON {
        mcpServers = {
          posthog = mcpServers.helpers.mkNpxMcp {
            package = "mcp-remote@latest";
            args = [
              "https://mcp.posthog.com/sse"
              "--header"
              "Authorization: Bearer \${POSTHOG_PERSONAL_API_KEY}"
            ];
          };
        };
      };

      # Codex MCP (read-only) for deep-tier claude→codex cross-model review.
      # Injected into deep claude workers via `dispatch` --mcp-config (the honored
      # registration path; --settings does not register mcpServers).
      "claude-code/mcp-codex.json".text = builtins.toJSON {
        mcpServers = {
          codex = {
            command = "codex";
            args = ["mcp-server" "-c" ''sandbox_mode="read-only"'' "-c" ''approval_policy="never"'' "-c" ''model_reasoning_effort="high"''];
          };
        };
      };
    };

  # Shell aliases (adds to base, allows project .mcp.json)
  programs.fish.shellAliases = mcpAliases;
  programs.bash.shellAliases = mcpAliases;
}
