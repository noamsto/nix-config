{pkgs, ...}: {
  home.packages = with pkgs; [
    eza
    zoxide
    grc
    nix-search-tv
  ];

  # === DYNAMIC THEME SUPPORT ===
  # Fish themes for light/dark mode switching
  # catppuccin.fish is disabled to avoid `fish_config theme choose` conflicting
  # with dynamic theme switching. Both themes are defined here manually.
  xdg.configFile = {
    # Catppuccin Latte theme (light mode)
    # Official colors from https://github.com/catppuccin/fish
    "fish/themes/Catppuccin Latte.theme".text = ''
      # name: 'Catppuccin Latte'
      # url: 'https://github.com/catppuccin/fish'
      # preferred_background: eff1f5

      fish_color_normal 4c4f69
      fish_color_command 1e66f5
      fish_color_param dd7878
      fish_color_keyword 8839ef
      fish_color_quote 40a02b
      fish_color_redirection ea76cb
      fish_color_end fe640b
      fish_color_comment 8c8fa1
      fish_color_error d20f39
      fish_color_gray 9ca0b0
      fish_color_selection --background=ccd0da
      fish_color_search_match --background=ccd0da
      fish_color_option 40a02b
      fish_color_operator ea76cb
      fish_color_escape e64553
      fish_color_autosuggestion 9ca0b0
      fish_color_cancel d20f39
      fish_color_cwd df8e1d
      fish_color_user 179299
      fish_color_host 1e66f5
      fish_color_host_remote 40a02b
      fish_color_status d20f39
      fish_color_valid_path --underline
      fish_pager_color_progress 9ca0b0
      fish_pager_color_prefix ea76cb
      fish_pager_color_completion 4c4f69
      fish_pager_color_description 8c8fa1
      fish_pager_color_selected_background --background=ccd0da
    '';

    # Catppuccin Mocha theme (dark mode)
    # Official colors from https://github.com/catppuccin/fish
    "fish/themes/Catppuccin Mocha.theme".text = ''
      # name: 'Catppuccin Mocha'
      # url: 'https://github.com/catppuccin/fish'
      # preferred_background: 1e1e2e

      fish_color_normal cdd6f4
      fish_color_command 89b4fa
      fish_color_param f2cdcd
      fish_color_keyword f38ba8
      fish_color_quote a6e3a1
      fish_color_redirection f5c2e7
      fish_color_end fab387
      fish_color_comment 7f849c
      fish_color_error f38ba8
      fish_color_gray 6c7086
      fish_color_selection --background=313244
      fish_color_search_match --background=313244
      fish_color_option a6e3a1
      fish_color_operator f5c2e7
      fish_color_escape eba0ac
      fish_color_autosuggestion 6c7086
      fish_color_cancel f38ba8
      fish_color_cwd f9e2af
      fish_color_user 94e2d5
      fish_color_host 89b4fa
      fish_color_host_remote a6e3a1
      fish_color_status f38ba8
      fish_pager_color_progress 6c7086
      fish_pager_color_prefix f5c2e7
      fish_pager_color_completion cdd6f4
      fish_pager_color_description 6c7086
      fish_pager_color_selected_background --background=45475a
    '';

    # __reload_theme function for dynamic theme switching
    "fish/functions/__reload_theme.fish".text = ''
      function __reload_theme
          # Accept theme as argument, or read from state file
          set -l current_theme $argv[1]

          if test -z "$current_theme"
              # No argument - read from state file
              set -l theme_state_file "$HOME/.local/state/theme-state.json"
              set -l legacy_state_file "$HOME/.local/state/theme-mode"

              set current_theme "dark"
              if test -f $theme_state_file
                  set current_theme (command jq -r '.theme // "dark"' $theme_state_file 2>/dev/null)
              else if test -f $legacy_state_file
                  set current_theme (cat $legacy_state_file)
              end
          end

          # Select theme file
          set -l theme_file "$HOME/.config/fish/themes/Catppuccin Mocha.theme"
          if test "$current_theme" = "light"
              set theme_file "$HOME/.config/fish/themes/Catppuccin Latte.theme"
          end

          # Load colors from theme file
          if test -f "$theme_file"
              while read -l line
                  # Skip comments and empty lines
                  if string match -qr '^\s*#|^\s*$' -- $line
                      continue
                  end
                  # Extract variable name (first word)
                  set -l var_name (string split ' ' -- $line)[1]
                  # Erase global variable first (it shadows universal)
                  set -eg $var_name 2>/dev/null
                  # Set universal variable (propagates to all fish instances)
                  if string match -qr '^fish_(color|pager)' -- $line
                      eval "set -U $line" 2>/dev/null
                  end
              end < "$theme_file"
          end

          # Update FZF colors for this session
          # The universal variable fzf_theme_colors is set by theme-toggle
          if set -q fzf_theme_colors
              # Get base FZF_DEFAULT_OPTS without any --color option we added
              set -l base_opts (string replace -r -- '--color=[^ ]+$' "" $FZF_DEFAULT_OPTS; or true)
              set -gx FZF_DEFAULT_OPTS $base_opts $fzf_theme_colors
          end

          # NOTE: BAT_THEME universal variable is automatically available
          # No need to explicitly set it here - handled in interactiveShellInit
      end
    '';

    # Dynamic theme initialization (runs on shell startup)
    # Named zzz- to run after other conf.d scripts
    "fish/conf.d/zzz-dynamic-theme.fish".text = ''
      # Dynamic theme loading based on current theme mode
      # This overrides the hardcoded theme in config.fish

      # Only run in interactive shells
      status is-interactive; or exit

      # Watch for fzf_theme_colors changes (set by theme-toggle)
      # This updates FZF_DEFAULT_OPTS automatically in all running fish sessions
      function __on_fzf_theme_change --on-variable fzf_theme_colors
          if set -q fzf_theme_colors
              # Get base opts without our theme colors
              set -l base_opts (string replace -r -- '--color=[^ ]+$' "" $FZF_DEFAULT_OPTS; or true)
              set -gx FZF_DEFAULT_OPTS $base_opts $fzf_theme_colors
          end
      end

      # NOTE: No watcher needed for BAT_THEME - universal variables are automatically
      # available across all fish sessions. We just export it in interactiveShellInit.

      # Reload theme colors based on state file
      __reload_theme
    '';
  };

  programs = {
    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };

    fish = {
      enable = true;
      generateCompletions = true; # Fixed in home-manager PR #8226 (Nov 2025)

      # Prefer abbreviations over aliases (shows full command, enables completions)
      preferAbbrs = true;

      # Fish uses its own history format, no need to configure path
      # History is automatically stored in ~/.local/share/fish/fish_history

      shellAliases = {
        ll = "eza -l --icons --git";
        tree = "eza --tree --icons";
        update = "sudo nixos-rebuild switch";
        ns = "nix-search-tv print | fzf --height 40% --preview 'nix-search-tv preview {}' --scheme=history --bind 'ctrl-/:change-preview-window(down|hidden|)'";

        # Workaround for https://github.com/anthropics/claude-code/issues/9935
        # claude = "claude-chill claude";
        hdm = "hyprdynamicmonitors";

        # Essential git aliases not covered by forgit (forgit has ga, gd, glo, gcb, gss, grb, etc.)
        # Status & info
        gsb = "git status -sb";
        gst = "git status";

        # Branching & switching
        gsw = "git switch";
        gswc = "git switch --create";
        gcom = "git checkout main || git checkout master";

        # Worktree management
        gwa = "git worktree add";
        gwl = "git worktree list";
        gwr = "git worktree remove";
        gwp = "git worktree prune";
        gwm = "git worktree move";

        # Remote operations
        gpf = "git push --force-with-lease";
        gpu = "git push -u origin HEAD";
        gp = "git push";
        gl = "git pull";
        gf = "git fetch";
        gfa = "git fetch --all --prune";
        gup = "git pull --rebase";

        # Staging & committing
        gaa = "git add --all";
        gc = "git commit -v";
        gcm = "git commit -m";
        gca = "git commit -v -a";
        gcan = "git commit -v -a --no-edit --amend";
        gwip = "git add -A && git commit -m 'WIP'";
        gunwip = "git reset HEAD~1";

        # Rebasing
        grbi = "git-forgit rebase -i";
        grbc = "git rebase --continue";
        grba = "git rebase --abort";

        # Reset
        grhh = "git reset --hard";
      };

      plugins = with pkgs.fishPlugins; [
        {
          name = "forgit";
          inherit (forgit) src;
        }
        {
          name = "grc";
          inherit (grc) src;
        }
        {
          name = "fzf-fish";
          inherit (fzf-fish) src;
        }
        {
          name = "autopair";
          inherit (autopair) src;
        }
      ];

      interactiveShellInit = ''
        # Disable greeting
        set fish_greeting

        # History optimizations
        set -g fish_history_save_max 10000           # Limit saved history items
        set -g fish_history_max_items 100000         # Max items to keep in memory
        set -g fish_history_ignore_space yes         # Don't save commands starting with space
        set -g fish_history_ignore_duplicates yes    # Remove consecutive duplicates
        set -g fish_history_search_case_sensitive no # Case-insensitive history search

        # Tmux function to auto-attach or create session
        function tmux
          if test (count $argv) -eq 0
            # No arguments, use smart attach/create behavior
            if command tmux has-session 2>/dev/null
              command tmux attach-session
            else
              command tmux new-session
            end
          else
            # Arguments provided, pass them through to tmux
            command tmux $argv
          end
        end

        # Load work aliases if available
        if test -f /etc/agenix/work_aliases.fish
          echo "Loading Work Aliases"
          source /etc/agenix/work_aliases.fish
        end

        # Load host environment if available
        if test -f /etc/agenix/host_env.env
          echo "Loading Host Env"
          # Fish can source bash-style env files
          for line in (cat /etc/agenix/host_env.env)
            if test -n "$line"; and not string match -q '#*' "$line"
              set -gx (string split '=' -- "$line")
            end
          end
        end

        # Bash-style history shortcuts
        abbr -a !! --position anywhere --function last_history_item
        abbr -a '!$' --position anywhere --function last_command_arg

        function last_history_item
          echo $history[1]
        end

        function last_command_arg
          echo $history[1] | read -lat args
          echo $args[-1]
        end

        # Vi mode (built-in)
        fish_vi_key_bindings

        # Configure fzf.fish to use Alt+X for variables instead of Ctrl+V (conflicts with paste)
        # Changed from Ctrl+E (conflicts with end-of-line) and Alt+V (conflicts with vi editor)
        fzf_configure_bindings --variables=\ex

        # Fix C-P and C-N for history navigation (restore after FZF)
        bind \cp up-or-search
        bind \cn down-or-search
        bind -M insert \cp up-or-search
        bind -M insert \cn down-or-search

        # Fix C-F to accept autosuggestions in vi insert and normal mode
        bind -M insert \cf accept-autosuggestion
        bind -M default \cf accept-autosuggestion

        # Add explicit undo bindings for vi mode
        bind -M insert \c_ undo  # Ctrl+_ in insert mode
        bind -M default \c_ undo # Ctrl+_ in normal mode
        bind -M insert \cz undo  # Alternative Ctrl+Z in insert mode

        # fzf history configuration
        set -gx fzf_history_opts --tmux 80%,70%                      # Popup: 80% width, 70% height
        set -gx fzf_history_opts $fzf_history_opts --preview-window 'down,50%,wrap'  # Bigger preview (50% of popup)
        set -gx fzf_history_opts $fzf_history_opts --bind 'ctrl-/:toggle-preview'    # Toggle preview with Ctrl+/
        set -gx fzf_history_opts $fzf_history_opts --bind 'alt-j:preview-down'       # Scroll preview down
        set -gx fzf_history_opts $fzf_history_opts --bind 'alt-k:preview-up'         # Scroll preview up
        set -gx fzf_history_opts $fzf_history_opts --bind 'ctrl-d:preview-page-down' # Page down in preview
        set -gx fzf_history_opts $fzf_history_opts --bind 'ctrl-u:preview-page-up'   # Page up in preview

        # Apply fzf theme colors from universal variable (set by theme-toggle)
        # This overrides catppuccin's build-time colors for runtime theme switching
        if set -q fzf_theme_colors
          set -gx FZF_DEFAULT_OPTS $FZF_DEFAULT_OPTS $fzf_theme_colors
        end

        # Apply bat theme from universal variable (set by theme-toggle)
        if set -q BAT_THEME
          set -gx BAT_THEME $BAT_THEME
        end

        # Function to clean old or duplicate history
        function history-clean
          history --merge                              # Merge all sessions
          history --delete --prefix "cd "              # Remove simple cd commands
          history --delete --contains "ls "            # Remove simple ls commands
          history --delete --contains "history "       # Remove history commands themselves
          echo "History cleaned!"
        end
      '';

      loginShellInit = ''
        # Locale settings
        set -gx LANG "en_US.UTF-8"
        set -gx LANGUAGE "en_US.UTF-8"
        set -gx LC_ALL "en_US.UTF-8"
      '';
    };

    fzf = {
      enable = true;
      enableFishIntegration = true;
      defaultOptions = ["--height 45% --tmux='80%,60%'"];
      fileWidgetOptions = [
        "--preview '${pkgs.bat}/bin/bat -n --color=always {}'"
        "--bind 'ctrl-/:change-preview-window(down|hidden|)'"
      ];
    };

    yazi = {
      enable = true;
      enableFishIntegration = true;

      # Custom yazi configuration (same as zsh config)
      settings = {
        manager = {
          show_hidden = false;
          show_symlink = true;
        };
      };

      # Custom keybindings for dragon-drop integration
      keymap = {
        manager.prepend_keymap = [
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
  };
}
