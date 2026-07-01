# Shared MCP server definitions for AI tools (Claude Code, OpenCode, etc.)
# Single source of truth - import this in each tool's module
{
  pkgs,
  lib,
}: let
  helpers = import ./mcp-helpers.nix {inherit pkgs;};

  # chromium is Linux-only in nixpkgs. On darwin, omit --executable-path so
  # playwright-mcp uses its own managed browser. Wrapped in lib.optionals so the
  # `pkgs.chromium` thunk is never forced off-Linux (it would fail meta checks).
  playwrightExecArgs =
    lib.optionals pkgs.stdenv.hostPlatform.isLinux ["--executable-path" (lib.getExe pkgs.chromium)];
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
      args = playwrightExecArgs;
      env = {
        PLAYWRIGHT_BROWSERS_PATH = "/home/noams/.cache/ms-playwright";
      };
    };

    firefox-devtools = helpers.mkNpxMcp {
      package = "firefox-devtools-mcp@latest";
      args = ["--connect-existing" "--marionette-port" "2828"];
    };
  };

  # Wrapper-based MCPs for editable JSON configs (opencode.json, etc.)
  # These provide simple command names that work when the wrapper is in PATH
  wrappers = {
    playwright = pkgs.writeShellScriptBin "playwright-mcp-wrapper" ''
      exec ${lib.getExe pkgs.playwright-mcp} ${lib.escapeShellArgs playwrightExecArgs} "$@"
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
