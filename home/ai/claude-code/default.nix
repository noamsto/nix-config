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

  # Hook helpers to reduce repetition in status state machine
  statusCmd = state: {
    type = "command";
    command = "claude-status-update ${state}";
  };
  statusHook = state: {hooks = [(statusCmd state)];};
  matchedStatusHook = matcher: state: {
    inherit matcher;
    hooks = [(statusCmd state)];
  };
  # cleanup + transition to a state
  sessionStartHook = matcher: state: {
    inherit matcher;
    hooks = [(statusCmd "cleanup") (statusCmd state)];
  };

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
        SessionStart = [
          (sessionStartHook "startup" "idle")
          (sessionStartHook "resume" "idle")
          (sessionStartHook "clear" "idle")
          (sessionStartHook "compact" "processing")
        ];
        UserPromptSubmit = [(statusHook "processing")];
        PreToolUse = [
          (statusHook "processing")
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
        PostToolUse = [(statusHook "processing")];
        Notification = [
          (matchedStatusHook "permission_prompt" "waiting")
          (matchedStatusHook "idle_prompt" "done")
        ];
        Stop = [(statusHook "done")];
        PreCompact = [(statusHook "compacting")];
        SessionEnd = [(statusHook "clear")];
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
    lspServers = {
      nix = {
        command = "${pkgs.nixd}/bin/nixd";
        extensionToLanguage = {
          ".nix" = "nix";
        };
      };
      bash = {
        command = "${pkgs.bash-language-server}/bin/bash-language-server";
        args = ["start"];
        extensionToLanguage = {
          ".sh" = "shellscript";
          ".bash" = "shellscript";
        };
      };
    };
  };
}
