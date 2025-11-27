{pkgs, ...}: {
  home.packages = with pkgs; [
    eza
    zoxide
    grc
    nix-search-tv
  ];
  programs = {
    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };

    fish = {
      enable = true;
      generateCompletions = false; # TODO: issue https://github.com/NixOS/nixpkgs/issues/462025

      # Prefer abbreviations over aliases (shows full command, enables completions)
      preferAbbrs = true;

      # Fish uses its own history format, no need to configure path
      # History is automatically stored in ~/.local/share/fish/fish_history

      shellAliases = {
        ll = "eza -l --icons --git";
        tree = "eza --tree --icons";
        update = "sudo nixos-rebuild switch";
        ns = "nix-search-tv print | fzf --height 40% --preview 'nix-search-tv preview {}' --scheme=history --bind 'ctrl-/:change-preview-window(down|hidden|)'";
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

        # Configure fzf.fish to use Ctrl+E for variables instead of Ctrl+V (conflicts with paste)
        fzf_configure_bindings --variables=\ce

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
