{
  lib,
  pkgs,
  osConfig,
  ...
}: let
  inherit (osConfig.nix-config.shell) hostEnvFile;
  inherit (osConfig.nix-config.terminal.tailscale) loginAccount;
in {
  home.packages = with pkgs; [
    eza
    zoxide
    grc
    nix-search-tv
  ];

  # zoxide only ages/decays its DB once the total rank exceeds _ZO_MAXAGE
  # (default 10000). A focused dev DB never reaches that, so stale dirs (an
  # old ~/.ssh, /tmp scratch paths) stay frozen near the top forever. Lower
  # the cap so decay runs and recency actually wins.
  home.sessionVariables._ZO_MAXAGE = "2000";

  # catppuccin.fish disabled — conflicts with dynamic theme switching via theme-toggle
  xdg.configFile = {
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

      set -g __tty_logout_timeout 300
      set -g __tty_idle_tty (tty)

      function __tty_idle_logout_stop
          if set -q __tty_idle_timer_pid; and test -n "$__tty_idle_timer_pid"
              kill $__tty_idle_timer_pid 2>/dev/null
          end
          set -e __tty_idle_timer_pid
      end

      # The timer runs only while fish sits at a prompt (stopped in preexec),
      # and measures idle time from the tty's atime, which the kernel advances
      # whenever input is read from it, so typing without Enter counts.
      function __tty_idle_logout_start --on-event fish_prompt
          __tty_idle_logout_stop

          fish -c '
              set -l start (date +%s)
              while kill -0 $argv[3] 2>/dev/null
                  set -l last (stat -c %X $argv[1] 2>/dev/null; or echo 0)
                  test $last -lt $start; and set last $start
                  set -l idle (math (date +%s) - $last)
                  if test $idle -ge $argv[2]
                      kill -HUP $argv[3] 2>/dev/null
                      exit
                  end
                  sleep (math $argv[2] - $idle)
              end
          ' $__tty_idle_tty $__tty_logout_timeout $fish_pid &
          set -g __tty_idle_timer_pid $last_pid
          disown $__tty_idle_timer_pid 2>/dev/null
      end

      function __tty_idle_logout_pause --on-event fish_preexec
          __tty_idle_logout_stop
      end

      function __tty_idle_logout_cleanup --on-event fish_exit
          __tty_idle_logout_stop
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

    "fish/functions/lock-commit.fish".text = import ./lock-commit.nix {
      inherit pkgs lib;
      inherit (osConfig.nix-config.terminal.lockCommit) watchedInputs;
    };

    "fish/functions/secret-commit.fish".text = import ./secret-commit.nix {inherit pkgs;};
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
        llp = "eza -l --icons --git --absolute=on";
        tree = "eza --tree --icons";
        update = "sudo nixos-rebuild switch";
        ns = "nix-search-tv print | fzf --height 40% --preview 'nix-search-tv preview {}' --scheme=history --bind 'ctrl-/:change-preview-window(down|hidden|)'";

        hdm = "hyprdynamicmonitors";

        # Claude Code
        c = "claude";
        cc = "claude --continue";
        cr = "claude --resume";
        cf = "claude-frontend";

        # Claude quick commands — haiku, no MCPs, restricted tools.
        # ALLOW_COMMIT_ON_DEFAULT=1 is inherited by the PreToolUse guard so a
        # deliberate quick commit on main isn't blocked.
        # Low effort + stable cached prefix keep these snappy; cco stays at
        # medium so the commit message still reasons over the diff.
        cco = ''ALLOW_COMMIT_ON_DEFAULT=1 claude --model haiku --effort medium --exclude-dynamic-system-prompt-sections --strict-mcp-config --allowed-tools "Bash(git *)" -p "/commit"'';
        cpush = ''claude --model haiku --effort low --exclude-dynamic-system-prompt-sections --strict-mcp-config --allowed-tools "Bash(git *)" -p "/push"'';

        # Tailscale (multi-account: `tailscale login` once per tailnet, then switch)
        tss = "tailscale status";
        tsl = "tailscale switch --list"; # profiles; current marked with *
        # operator/routing live in nixos/services/tailscale.nix; this only flips per-profile accept-routes
        tsp = lib.mkIf (loginAccount != null) "tailscale switch ${loginAccount} && tailscale up && tailscale set --accept-routes=false";

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

      interactiveShellInit =
        ''
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

          ${lib.optionalString (hostEnvFile != null) ''
            if test -f ${hostEnvFile}
              echo "Loading Host Env"
              # Fish can source bash-style env files
              for line in (cat ${hostEnvFile})
                if test -n "$line"; and not string match -q '#*' "$line"
                  set -gx (string split '=' -- "$line")
                end
              end
            end
          ''}
          abbr -a !! --position anywhere --function last_history_item
          abbr -a '!$' --position anywhere --function last_command_arg
          abbr -a sc 'sesh connect'
          abbr -a ffm 'firefox-marionette'
          abbr -a ws 'wt switch'
          abbr -a wsc --set-cursor 'wt switch -c %'
          abbr -a wsp --set-cursor 'wt switch pr:%'

          # Upstream `wt` fish completion (installed at
          # ~/.config/fish/completions/wt.fish) already enumerates branches in
          # ~30ms. Extend only `pr:<TAB>` with open PRs via gh, cached 30s
          # per-repo so Tab cycling doesn't hit the API on every keystroke.
          function __wt_switch_complete
              set -l token (commandline --current-token)
              string match -q 'pr:*' -- $token; or return
              set -l toplevel (git rev-parse --show-toplevel 2>/dev/null)
              test -n "$toplevel"; or return
              set -l cache_file "$XDG_RUNTIME_DIR/wt-pr-cache-"(string replace -a / _ -- $toplevel)
              set -l mtime 0
              test -f $cache_file; and set mtime (stat -c %Y $cache_file)
              if test (math (date +%s) - $mtime) -gt 30
                  gh pr list --state open --limit 100 --json number,title 2>/dev/null \
                    | jq -r 'sort_by(.number) | reverse[] | "pr:\(.number)\t\(.title)"' 2>/dev/null >$cache_file
              end
              command cat $cache_file 2>/dev/null
          end
          complete -c wt -n "__fish_seen_subcommand_from switch" -f -k -a "(__wt_switch_complete)"

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
        ''
        # caffeinate is macOS-only; keep the helper off the Linux hosts.
        + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
          # Casks drop completions here (aerospace ships fish ones), and nothing
          # else puts it on the path — nix fish only knows the nix profile, and
          # brew's shellenv isn't sourced. Appended, so nixpkgs completions win.
          set -a fish_complete_path /opt/homebrew/share/fish/vendor_completions.d

          function __wake_seconds --description 'Convert 90s/30m/2h to seconds'
            set -l d $argv[1]
            switch $d
              case '*h'; math (string trim -r -c h -- $d) x 3600
              case '*m'; math (string trim -r -c m -- $d) x 60
              case '*s'; string trim -r -c s -- $d
              case '*';  echo $d
            end
          end

          # Keep the Mac awake. Display stays on by default; `off` lets the
          # screen sleep while the system stays up. Optional duration: 90s/30m/2h.
          function wake --description 'Keep the Mac awake (display on by default)'
            set -l flags -di
            set -l secs
            for arg in $argv
              switch $arg
                case off; set flags -i
                case '*'; set secs (__wake_seconds $arg)
              end
            end
            test -n "$secs"; and set -a flags -t $secs
            caffeinate $flags
          end
          complete -c wake -f
          complete -c wake -n '__fish_is_first_token' -a off -d 'Allow the screen to sleep'
          complete -c wake -a '30m 1h 2h' -d 'Duration before releasing'

          # caffeinate ships no fish completions; describe its flags.
          complete -c caffeinate -s d -d 'Prevent the display from sleeping'
          complete -c caffeinate -s i -d 'Prevent the system from idle sleeping'
          complete -c caffeinate -s m -d 'Prevent the disk from idle sleeping'
          complete -c caffeinate -s s -d 'Prevent system sleep (AC power only)'
          complete -c caffeinate -s u -d 'Declare the user is active'
          complete -c caffeinate -s t -x -d 'Timeout in seconds'
          complete -c caffeinate -s w -x -d 'Wait for the given PID to exit'
        '';

      # Non-login shells, including `ssh host <cmd>`, need this too: without it
      # tmux falls back to the /tmp socket and starts a second server. Matches
      # the runtime dir the kitty launcher and tmux-startup.service pin; an
      # inherited value (e.g. inside a pane) is left alone.
      shellInit = lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
        if not set -q TMUX_TMPDIR; and test -d /run/user/(id -u)
            set -gx TMUX_TMPDIR /run/user/(id -u)
        end
      '';

      loginShellInit =
        ''
          set -gx LANG "en_US.UTF-8"
          set -gx LANGUAGE "en_US.UTF-8"
          set -gx LC_ALL "en_US.UTF-8"
        ''
        # nix-homebrew installs into /opt/homebrew but touches no PATH; brew
        # shellenv adds bin/sbin + HOMEBREW_PREFIX/MANPATH so brew-installed
        # tools (fastlane, etc.) and the brew command itself resolve.
        + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
          eval (/opt/homebrew/bin/brew shellenv)

          # Determinate Nix lives at /nix/var/nix/profiles/default/bin, which is
          # added to PATH only by macOS path_helper (/etc/paths.d/nix) for login
          # shells. GUI-launched / non-path_helper contexts miss it and `nix`
          # resolves to the nixpkgs command-not-found stub. Add it explicitly so
          # `nix` always resolves.
          fish_add_path /nix/var/nix/profiles/default/bin

          # nix-darwin's system profile holds environment.systemPackages (rg, fd,
          # jq, …). It's added by set-environment, but the exported
          # __NIX_DARWIN_SET_ENVIRONMENT_DONE guard makes nested/devshell shells
          # skip that, dropping it from PATH. Append (HM packages keep priority).
          fish_add_path --append /run/current-system/sw/bin
        '';
    };

    fzf = {
      enable = true;
      enableFishIntegration = true;
      enableBashIntegration = true;
      defaultOptions = ["--height 45% --tmux='80%,60%'"];
      fileWidget.options = [
        "--preview '${pkgs.bat}/bin/bat -n --color=always {}'"
        "--bind 'ctrl-/:change-preview-window(down|hidden|)'"
      ];
      historyWidget.bash.options = [
        "--tmux 80%,70%"
        "--preview-window 'down,50%,wrap'"
        "--bind 'ctrl-/:toggle-preview'"
        "--bind 'alt-j:preview-down'"
        "--bind 'alt-k:preview-up'"
        "--bind 'ctrl-d:preview-page-down'"
        "--bind 'ctrl-u:preview-page-up'"
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
