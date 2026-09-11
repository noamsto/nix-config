{
  config,
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}: let
  isServer = osConfig.machine.type == "server";
in {
  home = {
    sessionPath = ["$HOME/.local/bin"];
    packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [pkgs.wtc];

    # Workaround for eza upstream bug: theme.yml is silently ignored unless
    # EZA_CONFIG_DIR is set (src/options/theme.rs returns default config when
    # the env var is unset, even if theme.yml exists at the default path).
    sessionVariables.EZA_CONFIG_DIR = "$HOME/.config/eza";
  };

  # NOTE: imports must stay unconditional — conditioning them on `pkgs`
  # triggers infinite recursion (pkgs is resolved inside the module fixpoint).
  # Linux-only effects are gated below via mkIf, and inside ./foot itself.
  imports = [
    inputs.tmux-og.homeManagerModules.default
    ./foot
    ./kitty
    ./fish
    ./process_compose
    ./television
    ./btop.nix
    ./lazydocker.nix
  ];
  # Cross-platform: the module gates its Linux systemd / darwin launchd internals.
  programs.tmux-og = {
    enable = true;
    # macOS: use the otherwise-unused § key (left of 1 on Mac ISO keyboards) as
    # prefix. Linux keeps the lazytmux default (backtick).
    prefix = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin "§";
    # macOS: launchd-started tmux servers capture a stale $SHELL (/bin/zsh), so
    # panes open in zsh even though the account shell is fish. Pin default-shell.
    # Linux propagates the login shell fine, so leave it at the default there.
    defaultShell = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (lib.getExe pkgs.fish);
    worktrunk.enable = true;
    # Consolidate every repo's worktrees under one external root instead of a
    # visible `<repo>-worktrees` sibling that doubles up the git folder listing.
    # Org-nested (<org>/<repo>) so same-named repos across orgs can't collide.
    # Non-nested, so the watchman/fsevents concern (see lazytmux) doesn't apply.
    worktrunk.worktreePath = "${config.home.homeDirectory}/Data/git/.worktrees/{{ repo_path | dirname | basename }}/{{ repo_path | basename }}/{{ branch | sanitize }}";
    agentIntegration.enable = true;
    # tmux enables sixel for no terminal by default, so the bridge's sixel relay
    # stays inert until the outer terminal is named here. foot paints sixel; kitty
    # uses its own graphics protocol and must NOT be listed.
    sixelTerminals = ["foot"];
    # Summarize fallback windows (no issue, default branch) into a short title
    # via `claude -p` instead of showing the raw captured prompt.
    aiNaming.enable = true;
    # The CC plugin (--plugin-dir in the claude wrapper) ships the same skills
    skills.enable = false;
    persist = {
      enable = true;
      restoreMode = "auto";
      # Opt-in: mutates ~/.codex/config.toml and needs a one-time `/hooks` →
      # "Trust all" in an interactive codex session (trust hash isn't declarable).
      resumeCodex = true;
    };
    # Native Codex status hooks → claude-status-update (same trust step as above).
    # Prefer these over the agent-detect scraper for processing→idle transitions.
    codexStatus.enable = true;
    # Cursor Agent CLI status hooks → same status files (agent-detect stays backfill).
    cursorStatus.enable = true;
    # Control-mode bridge: ssh hosts the session picker (`prefix + s`) probes
    # for remote tmux sessions; Enter opens a live-bridged local window.
    # A host never bridges into itself. The alias is a MagicDNS name that need
    # not resemble the hostname it reaches (`tp-g6` → `thinkpad-p14s-g6`), so the
    # gate is spelled out per host until noamsto/lazytmux#387 lands.
    remote.hosts =
      lib.optional (osConfig.hostname != "thinkpad-p14s-g6") "tp-g6"
      ++ lib.optional (osConfig.hostname != "mbp-m4-pro") "mbp"
      ++ lib.optional (osConfig.hostname != "halo") "halo";
    processIcons = {
      houston = "🚀";
    };
    startupSession = {
      enable = true;
      name = "nix-config";
      directory = "${config.home.homeDirectory}/nix-config";
      terminal.emulator = "kitty";
      # A serverMode host is reached over ssh with no graphical login, so the
      # default graphical-session.target gating never fires and no tmux server
      # exists for the remote bridge to reach. Bind to default.target instead.
      headless = osConfig.machine.serverMode or false;
    };
  };

  # Eza icon overrides matching yazi custom icons (theme-toggle.sh update_yazi)
  # Schema: filenames/extensions are top-level, each entry is { icon: { glyph: <char> } }
  xdg.configFile."eza/theme.yml".text = let
    nixIcon = "󰜗"; # nerd: nf-md-snowflake
    vaultIcon = "󱒇"; # nerd: nf-md-vault
    gitIcon = ""; # nerd: nf-fa-git_alt
    dotfilesIcon = "󰒓"; # nerd: nf-md-cog
    srcIcon = ""; # nerd: nf-cod-folder_library
    docsIcon = ""; # nerd: nf-md-book
    scriptsIcon = ""; # nerd: nf-cod-terminal
  in ''
    filenames:
      nix-config:
        icon:
          glyph: "${nixIcon}"
      vaults:
        icon:
          glyph: "${vaultIcon}"
      git:
        icon:
          glyph: "${gitIcon}"
      dotfiles:
        icon:
          glyph: "${dotfilesIcon}"
      src:
        icon:
          glyph: "${srcIcon}"
      docs:
        icon:
          glyph: "${docsIcon}"
      scripts:
        icon:
          glyph: "${scriptsIcon}"
  '';

  programs = {
    yazi = {
      enable = true;
      enableFishIntegration = true;
      shellWrapperName = "y";

      plugins = {
        inherit (pkgs.yaziPlugins) mount git full-border;
        gvfs = pkgs.fetchFromGitHub {
          owner = "boydaihungst";
          repo = "gvfs.yazi";
          rev = "3abc0a258f9d7aeaa453a2d0d6e103c5a305953d";
          sha256 = "sha256-UHneVJ+YXyDuPrZS+PZbs9n9h+VN5M2QG36FdprBkJc=";
        };
      };

      # Custom yazi configuration
      settings = {
        mgr = {
          show_hidden = false;
          show_symlink = true;
        };
        plugin = {
          prepend_fetchers = [
            {
              url = "*";
              run = "git";
              group = "git";
            }
            {
              url = "*/";
              run = "git";
              group = "git";
            }
          ];
        };
      };

      initLua = ''
        require("git"):setup()
        require("gvfs"):setup()
        require("full-border"):setup()
      '';

      # Custom keybindings for dragon-drop integration
      keymap = {
        mgr.prepend_keymap = [
          {
            on = ["M"];
            run = "plugin mount";
            desc = "Mount plugin";
          }
          {
            on = ["c" "D"];
            run = ''shell --confirm 'dragon-drop --and-exit "$@"' $$'';
            desc = "Drag and drop (exit after)";
          }
          {
            on = ["c" "t"];
            run = ''shell --confirm 'dragon-drop --target' $$'';
            desc = "Dragon drop target (receive files)";
          }
        ];
      };
    };

    starship = {
      enable = true;
      enableFishIntegration = true;
      settings = lib.mkMerge [
        {
          add_newline = false;

          palette = "catppuccin_mocha";

          # Minimal format - only what matters
          format = lib.concatStrings [
            "$nix_shell"
            "$direnv"
            "$directory"
            "\${custom.git_branch_smart}"
            "\${custom.git_wt}"
            "$git_status"
            "$cmd_duration"
            "$line_break"
            "$character"
          ];

          nix_shell = {
            format = "[❄ $state]($style) ";
            style = "bold blue";
          };

          direnv = {
            disabled = false;
            format = "[$loaded]($style) ";
            style = "bold teal";
            loaded_msg = "📂";
            unloaded_msg = "";
            allowed_msg = "";
            not_allowed_msg = "📂!";
            denied_msg = "";
          };

          directory = {
            truncation_length = 4;
            truncate_to_repo = true;
            fish_style_pwd_dir_length = 1;
            style = "bold sapphire";
            repo_root_style = "bold mauve";
            repo_root_format = "[$before_root_path]($before_repo_root_style)[$repo_root]($repo_root_style)[$path]($style) ";
          };

          git_branch.disabled = true;

          custom.git_branch_smart = {
            disabled = false;
            command = ''
              set icon \ue725 # nerd: nf-dev-git_branch
              set branch (git branch --show-current 2>/dev/null)
              or exit 1
              test -z "$branch"; and exit 1
              set wt_dir (basename (git rev-parse --show-toplevel 2>/dev/null))
              set normalized (string replace -a '/' '-' -- $branch)
              if test "$normalized" = "$wt_dir"
                echo "$icon"
              else
                echo "$icon $branch"
              end
            '';
            when = "git rev-parse --is-inside-work-tree 2>/dev/null";
            shell = ["fish" "--no-config"];
            style = "bold lavender";
            format = "[$output]($style) ";
          };

          custom.git_wt = {
            disabled = false;
            command = "echo '🌳'";
            when = "test -f .git";
            shell = ["fish" "--no-config"];
            style = "bold lavender";
            format = "[$output]($style) ";
          };

          git_status = {
            format = "[$all_status$ahead_behind]($style) ";
            style = "bold red";
            conflicted = "!";
            ahead = "⇡";
            behind = "⇣";
            diverged = "⇕";
            up_to_date = "";
            stashed = "≡";
          };

          cmd_duration = {
            min_time = 2000;
            style = "bold peach";
          };

          character = {
            success_symbol = "[󰈺](bold green)";
            error_symbol = "[󰈺](bold red)";
            vimcmd_symbol = "[](bold blue)";
            vimcmd_visual_symbol = "[](bold peach)";
            vimcmd_replace_one_symbol = "[](bold orange)";
          };

          # Catppuccin Latte palette (light theme) - WCAG AA compliant modifications
          palettes.catppuccin_latte = {
            base = "#eff1f5";
            blue = "#1e66f5";
            crust = "#dce0e8";
            flamingo = "#b84545"; # Darkened for 4.8:1 contrast
            green = "#358023"; # Darkened for 4.5:1 contrast
            lavender = "#4a5fc9"; # Darkened for 4.7:1 contrast
            mantle = "#e6e9ef";
            maroon = "#e64553";
            mauve = "#8839ef";
            overlay0 = "#9ca0b0";
            overlay1 = "#8c8fa1";
            overlay2 = "#7c7f93";
            peach = "#c24b00"; # Darkened for 4.6:1 contrast
            pink = "#b84a9e"; # Darkened for 4.6:1 contrast
            red = "#d20f39";
            rosewater = "#a85847"; # Darkened for 4.7:1 contrast
            sapphire = "#0d7489"; # Darkened for 4.8:1 contrast
            sky = "#0077a3"; # Darkened for 4.5:1 contrast
            subtext0 = "#6c6f85";
            subtext1 = "#5c5f77";
            surface0 = "#ccd0da";
            surface1 = "#bcc0cc";
            surface2 = "#acb0be";
            teal = "#127275"; # Darkened for 4.5:1 contrast
            text = "#4c4f69";
            yellow = "#996b00"; # Darkened for 4.7:1 contrast
          };

          # Catppuccin Mocha palette (dark theme)
          palettes.catppuccin_mocha = {
            base = "#1e1e2e";
            blue = "#89b4fa";
            crust = "#11111b";
            flamingo = "#f2cdcd";
            green = "#a6e3a1";
            lavender = "#b4befe";
            mantle = "#181825";
            maroon = "#eba0ac";
            mauve = "#cba6f7";
            overlay0 = "#6c7086";
            overlay1 = "#7f849c";
            overlay2 = "#9399b2";
            peach = "#fab387";
            pink = "#f5c2e7";
            red = "#f38ba8";
            rosewater = "#f5e0dc";
            sapphire = "#74c7ec";
            sky = "#89dceb";
            subtext0 = "#a6adc8";
            subtext1 = "#bac2de";
            surface0 = "#313244";
            surface1 = "#45475a";
            surface2 = "#585b70";
            teal = "#94e2d5";
            text = "#cdd6f4";
            yellow = "#f9e2af";
          };
        }
        (lib.mkIf
          isServer
          {
            # Server-specific overrides
            username.show_always = true;
            hostname.ssh_only = false;
          })
      ];
    };

    bat.enable = true;
  };
}
