{
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}: let
  isServer = osConfig.machine.type == "server";
in {
  home.sessionPath = ["$HOME/.local/bin"];

  imports = [
    inputs.lazytmux.homeManagerModules.default
    ./foot
    ./kitty
    ./fish
    ./process_compose
    ./television
    ./btop.nix
    ./lazydocker.nix
  ];
  programs.lazytmux = {
    enable = true;
    wt.enable = false; # Replaced by worktrunk
    processIcons = {
      houston = "🚀";
    };
    startupSession = {
      enable = true;
      name = "nix-config";
      directory = "%h/nix-config";
      terminal.emulator = "kitty";
    };
  };

  home.packages = [pkgs.worktrunk];

  xdg.configFile."worktrunk/config.toml".text = ''
    worktree-path = "{{ repo_path }}/.worktrees/{{ branch | sanitize }}"

    [post-switch]
    tmux = """
    [ -z "$TMUX" ] && exit 0
    SESSION=$(tmux display-message -p '#{session_name}')
    # Find existing window by @worktree metadata or pane path
    WIN=$(tmux list-windows -t "$SESSION" -F '#{window_index}\t#{@worktree}\t#{pane_current_path}' \
      | awk -F'\t' '$2 == "{{ worktree_path }}" || $3 == "{{ worktree_path }}" { print $1; exit }')
    if [ -n "$WIN" ]; then
      tmux select-window -t "$SESSION:$WIN"
    else
      tmux new-window -a -t "$SESSION" -c "{{ worktree_path }}"
      tmux set-option -t "$SESSION" -w @worktree "{{ worktree_path }}"
      tmux set-option -t "$SESSION" -w @branch "{{ branch | sanitize }}"
    fi
    """

    [post-remove]
    tmux = """
    [ -z "$TMUX" ] && exit 0
    SESSION=$(tmux display-message -p '#{session_name}')
    WIN=$(tmux list-windows -t "$SESSION" -F '#{window_index}\t#{@worktree}\t#{pane_current_path}' \
      | awk -F'\t' '$2 == "{{ worktree_path }}" || $3 == "{{ worktree_path }}" { print $1; exit }')
    [ -n "$WIN" ] && tmux kill-window -t "$SESSION:$WIN" 2>/dev/null || true
    """
  '';

  programs = {
    yazi = {
      enable = true;
      enableFishIntegration = true;
      shellWrapperName = "y";

      plugins = {
        inherit (pkgs.yaziPlugins) mount git;
        gvfs = pkgs.fetchFromGitHub {
          owner = "boydaihungst";
          repo = "gvfs.yazi";
          rev = "master";
          sha256 = "sha256-6VNra6WUjDfBdGjCw/6VOAaAgZLF78/4Gj47BOh1Q/0=";
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
              id = "git";
              name = "*";
              run = "git";
            }
            {
              id = "git";
              name = "*/";
              run = "git";
            }
          ];
        };
      };

      initLua = ''
        require("git"):setup()
        require("gvfs"):setup()
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
