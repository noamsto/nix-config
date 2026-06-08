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
  nix-stage-guard = pkgs.writeShellScriptBin "claude-nix-stage-guard" (builtins.readFile ./nix-stage-guard.sh);
  skill-suggester = pkgs.writeShellScriptBin "claude-skill-suggester" (builtins.readFile ./skill-suggester.sh);
  git-commit-autostage-guard = pkgs.writeShellScriptBin "claude-git-commit-autostage-guard" (builtins.readFile ./git-commit-autostage-guard.sh);

  # --settings overlay: ONLY keys that need /nix/store paths.
  # Everything else belongs in settings.json (symlinked to repo).
  nix-settings-json = pkgs.writeTextFile {
    name = "claude-nix-settings.json";
    text = builtins.toJSON {
      statusLine = {
        type = "command";
        command = "${claude-statusline}/bin/claude-statusline";
      };
      # Status-state hooks live in the lazytmux CC plugin (loaded via
      # --plugin-dir in the wrapper below); only personal hooks remain here.
      hooks = {
        SessionStart = [
          {
            matcher = "startup";
            hooks = [
              {
                type = "command";
                command = "${skill-suggester}/bin/claude-skill-suggester";
              }
            ];
          }
        ];
        PreToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "${psql-guard}/bin/claude-psql-guard";
              }
              {
                type = "command";
                command = "${nix-stage-guard}/bin/claude-nix-stage-guard";
              }
              {
                type = "command";
                command = "${git-commit-autostage-guard}/bin/claude-git-commit-autostage-guard";
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
  # DISABLE_UPDATES: block self-update paths on immutable Nix store (>=2.1.118)
  claude-wrapper = pkgs.writeShellScriptBin "claude" ''
    export DISABLE_INSTALLATION_CHECKS=1
    export DISABLE_UPDATES=1
    exec ${claude-wrapped}/bin/claude --settings ${nix-settings-json} --plugin-dir ${inputs.lazytmux}/claude-plugin "$@"
  '';

  # Auto-discover skill directories under ./skills and symlink each into ~/.claude/skills/
  # Per-skill symlinks (rather than one dir-level symlink) so we don't conflict with
  # upstream-managed entries like tmux-interactive.
  skillNames =
    builtins.attrNames
    (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills));
  skillSymlinks = lib.listToAttrs (map (name: {
      name = ".claude/skills/${name}";
      value.source =
        config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/nix-config/home/ai/claude-code/skills/${name}";
    })
    skillNames);
in {
  imports = [./mcp-profiles.nix];

  # Out-of-store symlinks so Claude (and third-party tools) can edit at runtime
  home.file =
    {
      ".claude/CLAUDE.md".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/claude-code/CLAUDE.global.md";
      ".claude/settings.json".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/claude-code/settings.json";
      ".claude/agents".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/claude-code/agents";
      ".claude/commands".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/claude-code/commands";
    }
    // skillSymlinks;

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
      python = {
        command = "${pkgs.pyright}/bin/pyright-langserver";
        args = ["--stdio"];
        extensionToLanguage = {
          ".py" = "python";
          ".pyi" = "python";
        };
      };
    };
  };
}
