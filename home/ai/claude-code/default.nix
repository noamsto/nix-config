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
        # Session started -> cleanup stale entries from dead panes
        SessionStart = [
          {
            hooks = [
              {
                type = "command";
                command = "${seshUtils.claude-status-update}/bin/claude-status-update cleanup";
              }
            ];
          }
        ];
        # User submitted prompt -> processing
        UserPromptSubmit = [
          {
            hooks = [
              {
                type = "command";
                command = "${seshUtils.claude-status-update}/bin/claude-status-update processing";
              }
            ];
          }
        ];
        # Tool use -> still processing
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
        # Tool completed -> back to processing (covers permission granted)
        PostToolUse = [
          {
            hooks = [
              {
                type = "command";
                command = "${seshUtils.claude-status-update}/bin/claude-status-update processing";
              }
            ];
          }
        ];
        # Permission prompt -> waiting for user
        # Other notifications (idle_prompt, auth_success, etc.) -> processing
        # This handles the case where user responds to permission dialog (no dedicated hook exists)
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
          {
            # Catch-all for non-permission notifications - helps reset from stale waiting state
            matcher = "idle_prompt";
            hooks = [
              {
                type = "command";
                command = "${seshUtils.claude-status-update}/bin/claude-status-update done";
              }
            ];
          }
        ];
        # Claude finished responding -> done
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
        # Session ended -> clear status
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
  # Theme is handled by theme-toggle.sh updating ~/.claude.json directly
  # DISABLE_INSTALLATION_CHECKS=1 suppresses false "native installation" warnings
  # when running via Nix (see: https://github.com/anthropics/claude-code/issues/8523)
  claude-wrapper = pkgs.writeShellScriptBin "claude" ''
    export DISABLE_INSTALLATION_CHECKS=1
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
