{pkgs, ...}: {
  home.packages = with pkgs; [
    eza
    zoxide
    grc
    nix-search-tv
  ];

  # catppuccin.fish disabled — conflicts with dynamic theme switching via theme-toggle
  xdg.configFile = {
    # Fish completions for opencode and oc with caching for speed
    "fish/completions/opencode.fish".text = ''
      set -g __opencode_cache_dir "$HOME/.cache/fish/opencode-completions"
      set -g __opencode_cache_ttl 300  # 5 minutes

      function __opencode_get_cache_file
        set -l args $argv
        set -l cache_key
        if test (count $args) -eq 0
          set cache_key "_root"
        else
          set cache_key (string join '_' -- $args | string replace -a '/' '_' | string replace -a ' ' '_')
        end
        echo "$__opencode_cache_dir/$cache_key"
      end

      function __opencode_is_cache_fresh
        set -l cache_file $argv[1]
        if not test -f $cache_file
          return 1
        end
        set -l cache_age (math (date +%s) - (stat -c %Y $cache_file 2>/dev/null; or echo 0))
        test $cache_age -lt $__opencode_cache_ttl
      end

      function __opencode_completions
        set -l args (commandline -opc)
        set -e args[1]
        set -l current_token (commandline -ct)

        # Ensure cache directory exists
        if not test -d $__opencode_cache_dir
          mkdir -p $__opencode_cache_dir 2>/dev/null
        end

        set -l cache_file (__opencode_get_cache_file $args)

        # Check cache first
        if __opencode_is_cache_fresh $cache_file
          cat $cache_file 2>/dev/null
          return 0
        end

        # Generate fresh completions in background, return cached if available
        if test -f $cache_file
          # Return stale cache immediately while refreshing in background
          cat $cache_file 2>/dev/null &
          opencode --get-yargs-completions $args 2>/dev/null | grep -v '^\\$0$' > $cache_file &
        else
          # No cache, generate synchronously (first time only)
          opencode --get-yargs-completions $args 2>/dev/null | grep -v '^\\$0$' | tee $cache_file
        end
      end

      complete -c opencode -f -a '(__opencode_completions)'
    '';

    "fish/completions/oc.fish".text = ''
      # oc shares the same cache as opencode
      set -g __opencode_cache_dir "$HOME/.cache/fish/opencode-completions"
      set -g __opencode_cache_ttl 300

      function __oc_get_cache_file
        set -l args $argv
        set -l cache_key
        if test (count $args) -eq 0
          set cache_key "_root"
        else
          set cache_key (string join '_' -- $args | string replace -a '/' '_' | string replace -a ' ' '_')
        end
        echo "$__opencode_cache_dir/$cache_key"
      end

      function __oc_is_cache_fresh
        set -l cache_file $argv[1]
        if not test -f $cache_file
          return 1
        end
        set -l cache_age (math (date +%s) - (stat -c %Y $cache_file 2>/dev/null; or echo 0))
        test $cache_age -lt $__opencode_cache_ttl
      end

      function __oc_completions
        set -l args (commandline -opc)
        set -e args[1]

        if not test -d $__opencode_cache_dir
          mkdir -p $__opencode_cache_dir 2>/dev/null
        end

        set -l cache_file (__oc_get_cache_file $args)

        if __oc_is_cache_fresh $cache_file
          cat $cache_file 2>/dev/null
          return 0
        end

        if test -f $cache_file
          cat $cache_file 2>/dev/null &
          opencode --get-yargs-completions $args 2>/dev/null | grep -v '^\\$0$' > $cache_file &
        else
          opencode --get-yargs-completions $args 2>/dev/null | grep -v '^\\$0$' | tee $cache_file
        end
      end

      complete -c oc -f -a '(__oc_completions)'
    '';

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

          set -l theme_file "$HOME/.config/fish/themes/Catppuccin Mocha.theme"
          if test "$current_theme" = "light"
              set theme_file "$HOME/.config/fish/themes/Catppuccin Latte.theme"
          end

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

    # TTY-only: auto-logout after idle timeout (doesn't affect graphical terminals)
    "fish/conf.d/tty-auto-logout.fish".text = ''
      if not status is-interactive
          exit
      end

      if not string match -qr '^/dev/tty[0-9]+$' (tty)
          exit
      end

      set -g __tty_logout_timeout 120

      function __tty_idle_logout_reset --on-event fish_prompt
          if set -q __tty_idle_timer_pid; and test -n "$__tty_idle_timer_pid"
              kill $__tty_idle_timer_pid 2>/dev/null
          end

          fish -c "sleep $__tty_logout_timeout; kill -HUP $fish_pid 2>/dev/null" &
          set -g __tty_idle_timer_pid $last_pid
          disown $__tty_idle_timer_pid 2>/dev/null
      end

      function __tty_idle_logout_cleanup --on-event fish_exit
          if set -q __tty_idle_timer_pid; and test -n "$__tty_idle_timer_pid"
              kill $__tty_idle_timer_pid 2>/dev/null
          end
      end
    '';

    # zzz- prefix: run after other conf.d scripts
    "fish/conf.d/zzz-dynamic-theme.fish".text = ''
      status is-interactive; or exit

      function __on_fzf_theme_change --on-variable fzf_theme_colors
          if set -q fzf_theme_colors
              set -l base_opts (string replace -r -- '--color=[^ ]+$' "" $FZF_DEFAULT_OPTS; or true)
              set -gx FZF_DEFAULT_OPTS $base_opts $fzf_theme_colors
          end
      end

      # theme-toggle bumps __theme_mode universal; every interactive fish
      # re-reads its theme file (cheap, local) and repaints the prompt.
      function __on_theme_mode_change --on-variable __theme_mode
          __reload_theme $__theme_mode
          commandline -f repaint
      end

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

      preferAbbrs = true;

      shellAliases = {
        ll = "eza -l --icons --git";
        tree = "eza --tree --icons";
        update = "sudo nixos-rebuild switch";
        ns = "nix-search-tv print | fzf --height 40% --preview 'nix-search-tv preview {}' --scheme=history --bind 'ctrl-/:change-preview-window(down|hidden|)'";

        hdm = "hyprdynamicmonitors";

        # Claude Code
        c = "claude";
        cc = "claude --continue";
        cr = "claude --resume";
        cf = "claude-frontend";

        # OpenCode
        oc = "opencode";
        occ = "oc -c";
        ocs = "oc -s";

        # Tailscale (multi-account: `tailscale login` once per tailnet, then switch)
        tss = "tailscale status";
        tsl = "tailscale switch --list"; # profiles; current marked with *
        tsp = "tailscale down; tailscale switch stellern@gmail.com; and tailscale up --accept-routes";
        tsw = "tailscale down; tailscale switch noam@factify.com; and tailscale up --accept-routes";

        # Git (aliases not covered by forgit)
        gsb = "git status -sb";
        gst = "git status";
        gsw = "git switch";
        gswc = "git switch --create";
        gcom = "git checkout main || git checkout master";
        # Worktrees
        gwa = "git worktree add";
        gwl = "git worktree list";
        gwr = "git worktree remove";
        gwp = "git worktree prune";
        gwm = "git worktree move";
        # Remote
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
        set fish_greeting

        set -g fish_history_save_max 10000
        set -g fish_history_max_items 100000
        set -g fish_history_ignore_space yes
        set -g fish_history_ignore_duplicates yes
        set -g fish_history_search_case_sensitive no

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

        function wtc
          set -l wtc_bin (command -s wtc)
          if contains -- -i $argv; and set -q TMUX; and command -q tmux
            command tmux display-popup -E -w 90% -h 90% -d "$PWD" "$wtc_bin $argv"
          else
            $wtc_bin $argv
          end
        end

        if test -f /etc/agenix/work_aliases.fish
          echo "Loading Work Aliases"
          source /etc/agenix/work_aliases.fish
        end

        if test -f /etc/agenix/host_env.env
          echo "Loading Host Env"
          # Fish can source bash-style env files
          for line in (cat /etc/agenix/host_env.env)
            if test -n "$line"; and not string match -q '#*' "$line"
              set -gx (string split '=' -- "$line")
            end
          end
        end

        abbr -a !! --position anywhere --function last_history_item
        abbr -a '!$' --position anywhere --function last_command_arg
        abbr -a sc 'sesh connect'
        abbr -a ws 'wt switch'

        # Upstream worktrunk completions only complete flags for `wt switch` —
        # extend with dynamic branch/worktree names (incl. remotes & PR branches).
        # `wt config shell init` installs a runtime-completion shim at
        # ~/.config/fish/completions/wt.fish that shadows the vendor completion,
        # so __fish_wt_using_subcommand is never loaded — use fish's builtin.
        complete -c wt -n "__fish_seen_subcommand_from switch" -f -a \
          "(wt list --branches --remotes --format json 2>/dev/null | jq -r '.[].branch' 2>/dev/null)"

        # Sesh completions
        sesh completion fish | source

        # Worktrunk shell integration (auto-cd + completions)
        wt config shell init fish | source

        function last_history_item
          echo $history[1]
        end

        function last_command_arg
          echo $history[1] | read -lat args
          echo $args[-1]
        end

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

        set -gx fzf_history_opts --tmux 80%,70%
        set -gx fzf_history_opts $fzf_history_opts --preview-window 'down,50%,wrap'
        set -gx fzf_history_opts $fzf_history_opts --bind 'ctrl-/:toggle-preview'
        set -gx fzf_history_opts $fzf_history_opts --bind 'alt-j:preview-down'
        set -gx fzf_history_opts $fzf_history_opts --bind 'alt-k:preview-up'
        set -gx fzf_history_opts $fzf_history_opts --bind 'ctrl-d:preview-page-down'
        set -gx fzf_history_opts $fzf_history_opts --bind 'ctrl-u:preview-page-up'

        if set -q fzf_theme_colors
          set -gx FZF_DEFAULT_OPTS $FZF_DEFAULT_OPTS $fzf_theme_colors
        end

        if set -q BAT_THEME
          set -gx BAT_THEME $BAT_THEME
        end

        function history-clean
          history --merge                              # Merge all sessions
          history --delete --prefix "cd "              # Remove simple cd commands
          history --delete --contains "ls "            # Remove simple ls commands
          history --delete --contains "history "       # Remove history commands themselves
          echo "History cleaned!"
        end
      '';

      loginShellInit = ''
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
