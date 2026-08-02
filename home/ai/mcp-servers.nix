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

  # Remote (streamable HTTP) MCP servers. Claude gets these via claude.ai
  # connectors / plugin MCPs; cursor-agent and codex need explicit entries.
  # All are work tools — consumers gate on osConfig.profile.
  remote = {
    linear.url = "https://mcp.linear.app/mcp";
    notion.url = "https://mcp.notion.com/mcp";
    fireflies.url = "https://api.fireflies.ai/mcp";
    figma.url = "https://mcp.figma.com/mcp";
    slack = {
      url = "https://mcp.slack.com/mcp";
      # mcp.slack.com rejects dynamic client registration (pre-registered
      # confidential clients only). Borrow the client_id from Slack's official
      # MCP plugin (slackapi/slack-mcp-plugin) so `codex mcp login slack` runs
      # PKCE as that client; if Slack rotates it, copy the current value from
      # that repo. Cursor-agent is a partner client and OAuthes without this.
      codexOauthClientId = "1601185624273.8899143856786";
    };
    groundcover = {
      url = "https://mcp.groundcover.com/api/mcp";
      headers = {
        X-Timezone = "Asia/Jerusalem";
        X-Tenant-UUID = "f9cea478-4af0-451b-b226-c05829b9f8ea";
        X-Backend-Id = "groundcover";
      };
    };
    posthog = {
      url = "https://mcp.posthog.com/mcp";
      bearerTokenEnvVar = "POSTHOG_PERSONAL_API_KEY";
    };
  };

  # Convert a remote MCP entry to cursor mcp.json format
  toCursor = server:
    {inherit (server) url;}
    // lib.optionalAttrs (server ? headers) {inherit (server) headers;};

  # Convert a remote MCP entry to codex config.toml [mcp_servers.*] format
  toCodex = server:
    {inherit (server) url;}
    // lib.optionalAttrs (server ? headers) {http_headers = server.headers;}
    // lib.optionalAttrs (server ? bearerTokenEnvVar) {bearer_token_env_var = server.bearerTokenEnvVar;}
    // lib.optionalAttrs (server ? codexOauthClientId) {oauth.client_id = server.codexOauthClientId;};

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
