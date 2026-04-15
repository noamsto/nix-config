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
    rev = "main";
    sha256 = "sha256-st/3ta9HouoTnic+oUBQF/3bpSoARq5U8JxWTcolIbw=";
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
