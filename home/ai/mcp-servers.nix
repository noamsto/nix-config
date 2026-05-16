# Shared MCP server definitions for AI tools (Claude Code, OpenCode, etc.)
# Single source of truth - import this in each tool's module
{
  pkgs,
  lib,
}: let
  helpers = import ./mcp-helpers.nix {inherit pkgs;};
  obsidianVaults = ["/home/noams/vaults/personal" "/home/noams/vaults/work"];
in {
  # Base MCPs - npx-style (avoids embedding deps that collide with cursor-agent)
  # Used by claude-code, amp, cursor (flat attribute)
  base = {
    context7 = {
      command = "${pkgs.context7-mcp}/bin/context7-mcp";
      args = [];
      env = {};
    };

    playwright = {
      command = lib.getExe pkgs.playwright-mcp;
      args = ["--executable-path" (lib.getExe pkgs.chromium)];
      env = {
        PLAYWRIGHT_BROWSERS_PATH = "/home/noams/.cache/ms-playwright";
      };
    };

    obsidian = helpers.mkNpxMcp {
      package = "obsidian-mcp";
      args = obsidianVaults;
    };

    firefox-devtools = helpers.mkNpxMcp {
      package = "firefox-devtools-mcp@latest";
      args = ["--connect-existing" "--marionette-port" "2828"];
    };
  };

  # Wrapper-based MCPs for editable JSON configs (opencode.json, etc.)
  # These provide simple command names that work when the wrapper is in PATH
  wrappers = {
    obsidian = helpers.mkNpxWrapper {
      name = "obsidian-mcp-wrapper";
      package = "obsidian-mcp";
      extraArgs = obsidianVaults;
    };
    playwright = pkgs.writeShellScriptBin "playwright-mcp-wrapper" ''
      exec ${lib.getExe pkgs.playwright-mcp} --executable-path ${lib.getExe pkgs.chromium} "$@"
    '';
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
