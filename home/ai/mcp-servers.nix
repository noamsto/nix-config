# Shared MCP server definitions for AI tools (Claude Code, OpenCode, etc.)
# Single source of truth - import this in each tool's module
{
  pkgs,
  lib,
}: let
  helpers = import ./mcp-helpers.nix {inherit pkgs;};
in {
  # Base MCPs - npx-style (avoids embedding deps that collide with cursor-agent)
  # Used by claude-code, amp, cursor (flat attribute)
  base = {
    context7 = {
      command = "${pkgs.context7-mcp}/bin/context7-mcp";
      args = [];
      env = {};
    };

    playwright = helpers.mkNpxMcp {
      package = "playwright-mcp";
      args = ["--executable-path" "${lib.getExe pkgs.chromium}"];
      env.PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    };

    obsidian = helpers.mkNpxMcp {
      package = "obsidian-mcp";
      args = ["/home/noams/vaults/personal" "/home/noams/vaults/work"];
    };
  };

  # Convert a base MCP entry to opencode format (different structure)
  toOpencode = server: {
    type = "local";
    command = [server.command] ++ server.args;
    enabled = true;
    environment = server.env or {};
  };

  # MCPs provided natively by claude.ai — exclude from Claude Code
  claudeAiProvided = ["linear"];

  # Re-export helpers for use in tool-specific configs
  inherit helpers;
}
