{
  pkgs,
  lib,
  inputs,
  ...
}: let
  # Shared MCP server definitions
  mcpServers = import ../mcp-servers.nix {inherit pkgs;};

  # Statusline script package
  claude-statusline = pkgs.callPackage ./statusline.nix {};

  # Import tmux/sesh utilities for Claude status integration
  seshUtils = import ../../terminal/tmux/sesh-utils.nix {inherit pkgs;};

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
      # Hooks for tmux status integration
      hooks = {
        PreToolUse = [
          {
            hooks = [
              {
                type = "command";
                command = "${seshUtils.claude-status-update}/bin/claude-status-update processing";
              }
            ];
          }
        ];
        Notification = [
          {
            matcher = "permission_prompt";
            hooks = [
              {
                type = "command";
                command = "${seshUtils.claude-status-update}/bin/claude-status-update waiting";
              }
            ];
          }
        ];
        Stop = [
          {
            hooks = [
              {
                type = "command";
                command = "${seshUtils.claude-status-update}/bin/claude-status-update done";
              }
            ];
          }
        ];
        SessionEnd = [
          {
            hooks = [
              {
                type = "command";
                command = "${seshUtils.claude-status-update}/bin/claude-status-update clear";
              }
            ];
          }
        ];
      };
    };
  };

  # Wrap claude-code with npx/uvx access and settings
  # Uses wrappers lib for clean PATH injection
  claude-wrapped = inputs.wrappers.lib.wrapPackage {
    inherit pkgs;
    package = pkgs.claude-code;
    # Make npx (nodejs) and uvx (uv) available for MCP servers and tools
    runtimeInputs = [pkgs.nodejs pkgs.uv];
  };

  # Final wrapper that adds settings flag
  claude-wrapper = pkgs.writeShellScriptBin "claude" ''
    exec ${claude-wrapped}/bin/claude --settings ${nix-settings-json} "$@"
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

    # Use shared base MCPs (heavy MCPs loaded via --mcp-config aliases)
    # See ../mcp-servers.nix for definitions
    # NOTE: Playwright and PostHog MCPs loaded conditionally via aliases:
    #   claude-frontend - adds Playwright MCP
    #   claude-analytics - adds PostHog MCP
    # See mcp-profiles.nix for configuration
    mcpServers = mcpServers.base;
  };
}
