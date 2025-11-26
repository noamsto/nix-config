{
  pkgs,
  lib,
  ...
}: let
  # Statusline script package
  claude-statusline = pkgs.callPackage ./statusline.nix {};

  # Create nix-managed settings file (merged via --settings flag)
  # This allows Claude Code to maintain its own settings.json for plugins
  nix-settings-json = pkgs.writeTextFile {
    name = "claude-nix-settings.json";
    text = builtins.toJSON {
      includeCoAuthoredBy = false;
      statusLine = {
        type = "command";
        command = "${claude-statusline}/bin/claude-statusline";
      };
    };
  };

  # Create wrapper script that merges nix settings
  claude-wrapper = pkgs.writeShellScriptBin "claude" ''
    exec ${pkgs.claude-code}/bin/claude --settings ${nix-settings-json} "$@"
  '';
in {
  # Import MCP profiles module (generates conditional MCP configs and aliases)
  imports = [./mcp-profiles.nix];

  programs.claude-code = {
    enable = true;
    # Use our wrapper instead of the direct package
    package = claude-wrapper;

    # Don't generate settings.json - let Claude Code manage it
    # (the wrapper handles --settings for HM-managed config)
    settings = {};

    # Base MCPs - always loaded (heavy MCPs loaded via --mcp-config aliases)
    mcpServers = {
      context7 = {
        command = "${pkgs.context7-mcp}/bin/context7-mcp";
        args = [];
        env = {};
      };

      sequential-thinking = {
        command = "${pkgs.mcp-server-sequential-thinking}/bin/mcp-server-sequential-thinking";
        args = [];
        env = {};
      };

      # Packaged tavily-mcp from custom package (packages/tavily-mcp.nix)
      # NOTE: Alternative npx approach (works but not reproducible):
      #   command = "${pkgs.nodejs}/bin/npx";
      #   args = ["-y" "tavily-mcp@latest"];
      #   env = {
      #     PATH = "${pkgs.lib.makeBinPath [pkgs.nodejs pkgs.bash pkgs.coreutils]}";
      #     # Need bash and coreutils for npm to spawn sh processes
      #     # TAVILY_API_KEY = "your-api-key";
      #   };
      tavily = {
        command = "${pkgs.tavily-mcp}/bin/tavily-mcp";
        args = [];
        env = {
          # TAVILY_API_KEY = "your-api-key-here";  # Env variable available via agenix
        };
      };

      # Linear MCP - HTTP transport (recommended over SSE)
      # Run `/mcp` in Claude Code session to authenticate
      linear = {
        type = "http";
        url = "https://mcp.linear.app/mcp";
      };

      # NOTE: Playwright and PostHog MCPs loaded conditionally via aliases:
      #   claude-frontend - adds Playwright MCP
      #   claude-analytics - adds PostHog MCP
      # See mcp-profiles.nix for configuration
    };
  };
}
