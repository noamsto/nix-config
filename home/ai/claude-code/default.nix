{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  # Shared MCP server definitions
  mcpServers = import ../mcp-servers.nix {inherit pkgs lib;};

  claude-statusline = pkgs.callPackage ./statusline.nix {};
  psql-guard = pkgs.writeShellScriptBin "claude-psql-guard" (builtins.readFile ./psql-guard.sh);

  nix-settings-json = pkgs.writeTextFile {
    name = "claude-nix-settings.json";
    text = builtins.toJSON {
      includeCoAuthoredBy = false;
      permissions.defaultMode = "auto";
      statusLine = {
        type = "command";
        command = "${claude-statusline}/bin/claude-statusline";
      };
      # Tmux status integration state machine
      hooks = {
        # startup/resume/clear -> idle, compact -> processing
        SessionStart = [
          {
            matcher = "startup";
            hooks = [
              {
                type = "command";
                command = "claude-status-update cleanup";
              }
              {
                type = "command";
                command = "claude-status-update idle";
              }
            ];
          }
          {
            matcher = "resume";
            hooks = [
              {
                type = "command";
                command = "claude-status-update cleanup";
              }
              {
                type = "command";
                command = "claude-status-update idle";
              }
            ];
          }
          {
            matcher = "clear";
            hooks = [
              {
                type = "command";
                command = "claude-status-update cleanup";
              }
              {
                type = "command";
                command = "claude-status-update idle";
              }
            ];
          }
          {
            matcher = "compact";
            hooks = [
              {
                type = "command";
                command = "claude-status-update cleanup";
              }
              {
                type = "command";
                command = "claude-status-update processing";
              }
            ];
          }
        ];
        UserPromptSubmit = [
          {
            hooks = [
              {
                type = "command";
                command = "claude-status-update processing";
              }
            ];
          }
        ];
        PreToolUse = [
          {
            hooks = [
              {
                type = "command";
                command = "claude-status-update processing";
              }
            ];
          }
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "${psql-guard}/bin/claude-psql-guard";
              }
            ];
          }
        ];
        PostToolUse = [
          {
            hooks = [
              {
                type = "command";
                command = "claude-status-update processing";
              }
            ];
          }
        ];
        # permission_prompt -> waiting, idle_prompt -> done
        Notification = [
          {
            matcher = "permission_prompt";
            hooks = [
              {
                type = "command";
                command = "claude-status-update waiting";
              }
            ];
          }
          {
            matcher = "idle_prompt";
            hooks = [
              {
                type = "command";
                command = "claude-status-update done";
              }
            ];
          }
        ];
        Stop = [
          {
            hooks = [
              {
                type = "command";
                command = "claude-status-update done";
              }
            ];
          }
        ];
        PreCompact = [
          {
            hooks = [
              {
                type = "command";
                command = "claude-status-update compacting";
              }
            ];
          }
        ];
        SessionEnd = [
          {
            hooks = [
              {
                type = "command";
                command = "claude-status-update clear";
              }
            ];
          }
        ];
      };
    };
  };

  claude-wrapped = inputs.wrappers.lib.wrapPackage {
    inherit pkgs;
    package = pkgs.claude-code;
    runtimeInputs = [pkgs.nodejs pkgs.uv];
  };

  # DISABLE_INSTALLATION_CHECKS: suppress false warnings when running via Nix
  # https://github.com/anthropics/claude-code/issues/8523
  claude-wrapper = pkgs.writeShellScriptBin "claude" ''
    export DISABLE_INSTALLATION_CHECKS=1
    exec ${claude-wrapped}/bin/claude --settings ${nix-settings-json} "$@"
  '';
in {
  imports = [./mcp-profiles.nix];

  # Out-of-store symlink so Claude can edit it at runtime
  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/claude-code/CLAUDE.global.md";

  programs.claude-code = {
    enable = true;
    package = claude-wrapper;
    settings = {}; # Managed via --settings flag in wrapper
    # Heavy MCPs (Playwright, PostHog) loaded conditionally via mcp-profiles.nix aliases
    mcpServers = lib.removeAttrs mcpServers.base mcpServers.claudeAiProvided;
  };
}
