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
      claude-cad = "claude --mcp-config ~/.config/claude-code/mcp-freecad.json";
    }
    // lib.optionalAttrs (osConfig.profile == "work") {
      claude-analytics = "claude --mcp-config ~/.config/claude-code/mcp-posthog.json";
    };

  # FreeCAD MCP addon source
  freecad-mcp-addon = pkgs.fetchFromGitHub {
    owner = "neka-nat";
    repo = "freecad-mcp";
    rev = "aae23e561b1384d5949dff20a4fff0caf2b23cd5";
    sha256 = "sha256-c0AIO62P8+oR3My4iFpFAD98Wpw5wjGITPOjK+WtIMU=";
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

      # Worker profile: NO MCP servers — paired with `--strict-mcp-config` so a fanned-out
      # worker doesn't spawn the full base stack (playwright/chromium, firefox, obsidian…).
      # The `crew` bus is a fish function, so it stays available regardless.
      "claude-code/mcp-worker.json".text = builtins.toJSON {
        mcpServers = {};
      };

      # FreeCAD MCP for CAD modeling
      "claude-code/mcp-freecad.json".text = builtins.toJSON {
        mcpServers = {
          freecad = mcpServers.helpers.mkUvxMcp {
            package = "freecad-mcp";
            args = ["--only-text-feedback"]; # Reduce token usage
          };
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
    };

  # Install FreeCAD MCP addon
  home.file.".local/share/FreeCAD/Mod/FreeCADMCP".source = "${freecad-mcp-addon}/addon/FreeCADMCP";

  # Shell aliases (adds to base, allows project .mcp.json)
  programs.fish.shellAliases = mcpAliases;
  programs.bash.shellAliases = mcpAliases;
}
