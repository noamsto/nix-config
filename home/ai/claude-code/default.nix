{
  pkgs,
  lib,
  config,
  inputs,
  osConfig,
  ...
}: let
  # Shared MCP server definitions
  mcpServers = import ../mcp-servers.nix {inherit pkgs lib;};

  claude-statusline = pkgs.callPackage ./statusline.nix {};
  psql-guard = pkgs.writeShellScriptBin "claude-psql-guard" (builtins.readFile ./psql-guard.sh);
  nix-stage-guard = pkgs.writeShellScriptBin "claude-nix-stage-guard" (builtins.readFile ./nix-stage-guard.sh);
  skeleton-guard = pkgs.writeShellScriptBin "claude-read-skeleton-guard" (builtins.readFile ./skeleton-guard.sh);
  skill-suggester = pkgs.writeShellScriptBin "claude-skill-suggester" (builtins.readFile ./skill-suggester.sh);
  git-commit-autostage-guard = pkgs.writeShellScriptBin "claude-git-commit-autostage-guard" (builtins.readFile ./git-commit-autostage-guard.sh);
  git-default-branch-guard = pkgs.writeShellScriptBin "claude-git-default-branch-guard" (builtins.readFile ./git-default-branch-guard.sh);
  deslop-guard = pkgs.writeShellScriptBin "claude-deslop-guard" (builtins.readFile ./deslop-guard.sh);
  deslop-mark = pkgs.writeShellScriptBin "claude-deslop-mark" (builtins.readFile ./deslop-mark.sh);
  dispatch-notify = pkgs.writeShellScriptBin "claude-dispatch-notify" (builtins.readFile ./dispatch-notify.sh);

  # --settings overlay: ONLY keys that need /nix/store paths.
  # Everything else belongs in settings.json (symlinked to repo).
  nix-settings-json = pkgs.writeTextFile {
    name = "claude-nix-settings.json";
    text = builtins.toJSON {
      statusLine = {
        type = "command";
        command = "${claude-statusline}/bin/claude-statusline";
      };
      # Status-state hooks live in the lazytmux CC plugin and image-capture
      # hooks in the aeye CC plugin (both loaded via --plugin-dir in
      # the wrapper below); only personal hooks remain here.
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
              {
                type = "command";
                command = "${git-default-branch-guard}/bin/claude-git-default-branch-guard";
              }
              {
                type = "command";
                command = "${deslop-guard}/bin/claude-deslop-guard";
              }
            ];
          }
          {
            matcher = "Read";
            hooks = [
              {
                type = "command";
                command = "${skeleton-guard}/bin/claude-read-skeleton-guard";
              }
            ];
          }
        ];
        PostToolUse = [
          {
            matcher = "Skill";
            hooks = [
              {
                type = "command";
                command = "${deslop-mark}/bin/claude-deslop-mark";
              }
            ];
          }
        ];
        SessionEnd = [
          {
            hooks = [
              {
                type = "command";
                command = "${dispatch-notify}/bin/claude-dispatch-notify";
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
  #
  # exec -a claude: set argv[0] so ps/comm/Activity Monitor (and Linux tmux,
  # which reads /proc/pid/cmdline) show `claude`, not the nix store wrapper.
  # macOS tmux can't be fixed here: it reads proc_pidpath, which resolves
  # through every wrapper/symlink to the real Bun binary upstream named
  # `.claude-wrapped`, ignoring argv[0]. That title is instead rewritten at the
  # tmux display layer (lazytmux set-titles-string strips `.*-wrapped`).
  claude-wrapper = pkgs.writeShellScriptBin "claude" ''
    export DISABLE_INSTALLATION_CHECKS=1
    export DISABLE_UPDATES=1
    # D2 diagrams (aeye diagrams.sh): bundle d2's own font so resvg
    # renders text, and follow the desktop light/dark scheme for the theme.
    export AEYE_D2_FONT="Source Sans 3"
    export AEYE_D2_FONT_DIR="${pkgs.source-sans}/share/fonts/truetype"
    scheme=$(dconf read /org/gnome/desktop/interface/color-scheme 2>/dev/null)
    if [ "$scheme" = "'prefer-light'" ]; then
      export AEYE_D2_THEME=105
    else
      export AEYE_D2_THEME=200
    fi
    exec -a claude ${claude-wrapped}/bin/claude --settings ${nix-settings-json} --plugin-dir ${inputs.lazytmux}/claude-plugin --plugin-dir ${inputs.lazytmux.inputs.aeye}/adapters/claude-code/plugin "$@"
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
  imports = [
    ./mcp-profiles.nix
    inputs.agent-smith.homeManagerModules.default
    inputs.resolved.homeManagerModules.default
  ];

  programs = {
    # agent-smith CC plugin engine on PATH; the module self-wraps duckdb/git/gh.
    agent-smith.enable = true;
    # resolved CC plugin binary on PATH; the /resolved:stale plugin finds it there.
    resolved.enable = true;
  };

  # Out-of-store symlinks so Claude (and third-party tools) can edit at runtime
  home.file =
    {
      ".claude/CLAUDE.md".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/claude-code/CLAUDE.global.md";
      # Profile overlay imported by CLAUDE.global.md via @~/.claude/CLAUDE.profile.md.
      # Always present (work or personal) so the import never silently no-ops.
      ".claude/CLAUDE.profile.md".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/claude-code/CLAUDE.${osConfig.profile}.md";
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
