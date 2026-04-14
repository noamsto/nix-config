# Shared MCP server definitions for AI tools (Claude Code, OpenCode, etc.)
# Single source of truth - import this in each tool's module
{
  pkgs,
  lib,
}: let
  helpers = import ./mcp-helpers.nix {inherit pkgs;};
in rec {
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
  };

  # Alias for backwards compatibility (points to same as base)
  claude = base;

  # Opencode format MCPs (different structure - uses environment, not env)
  opencode = {
    context7 = {
      type = "local";
      command = ["${pkgs.context7-mcp}/bin/context7-mcp"];
      enabled = true;
    };

    playwright = {
      type = "local";
      command = [
        "npx"
        "-y"
        "playwright-mcp"
        "--executable-path"
        "${lib.getExe pkgs.chromium}"
      ];
      enabled = true;
      environment = {
        PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
        PATH = pkgs.lib.makeBinPath [pkgs.nodejs pkgs.bash pkgs.coreutils];
      };
    };
  };

  # MCPs provided natively by claude.ai — exclude from Claude Code
  claudeAiProvided = ["linear"];

  # Optional MCPs (heavy/specialized) - load via profiles or on-demand
  optional = {
    posthog = helpers.mkNpxMcp {
      package = "mcp-remote@latest";
      args = ["https://mcp.posthog.com/sse" "--header" "Authorization: Bearer \${POSTHOG_PERSONAL_API_KEY}"];
    };
  };

  # Re-export helpers for use in tool-specific configs
  inherit helpers;
}
