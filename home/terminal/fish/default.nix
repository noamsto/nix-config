{
  lib,
  pkgs,
  osConfig,
  ...
}: {
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

    "fish/functions/dispatch.fish".text = ''
      function dispatch --description 'Scaffold a worker: issue/ticket -> worktree -> task file -> baked claude'
          set -l tier $argv[1]
          set -l model $argv[2]
          if not contains -- $tier trivial standard deep
              echo "usage: dispatch <trivial|standard|deep> <model> [LINEAR-ID] <title...>" >&2
              return 1
          end

          # Optional Linear ticket id as the first token after the model (e.g.
          # ENG-6789). When present we track the work in Linear and skip GitHub
          # issue creation — the repo's GH issues may be disabled (Linear is the
          # tracker). Detect by shape so the bare <title...> form still works.
          set -l linear_id ""
          set -l rest $argv[3..-1]
          if string match -qr '^[A-Z]{2,}-[0-9]+$' -- $rest[1]
              set linear_id $rest[1]
              set rest $rest[2..-1]
          end
          set -l title (string join ' ' $rest)
          if test -z "$title"
              echo "usage: dispatch <trivial|standard|deep> <model> [LINEAR-ID] <title...>" >&2
              return 1
          end

          # Identity + closes line. Linear mode derives both from the ticket, no
          # gh call. GitHub mode creates an issue and uses its number — but aborts
          # cleanly if that fails (e.g. issues disabled) rather than scaffolding a
          # half-broken worker off an empty number.
          # Branch path must match worktrunk's {{ repo_path }}-worktrees/{{ branch
          # | sanitize }} template (slash -> dash) — wt won't tell us where it put
          # the worktree.
          set -l slug (string lower (string replace -ra '[^a-zA-Z0-9]+' '-' $title) | string sub -l 40 | string trim -c -)
          set -l branch
          set -l closes
          if test -n "$linear_id"
              set branch (string lower $linear_id)-$slug
              set closes "Closes $linear_id"
          else
              set -l url (gh issue create --assignee @me --title "$title" --body "Dispatched worker task." 2>/dev/null)
              set -l num (string match -r '/(\d+)$' -- $url)[2]
              if test -z "$num"
                  echo "dispatch: could not create a GitHub issue (issues disabled?). Pass a Linear id, e.g. dispatch $tier $model ENG-1234 $title" >&2
                  return 1
              end
              set branch "feat/$num-$slug"
              set closes "Closes #$num"
          end
          set -l sanitized (string replace -a / - $branch)
          set -l wt_path (git rev-parse --show-toplevel)-worktrees/$sanitized

          # post-switch tmux hook is disabled under CLAUDECODE, so wt only creates the
          # worktree here — we drive tmux ourselves below.
          wt switch -c $branch -y

          # crew bus: one crew_id per dispatcher shell (set -gx persists across
          # dispatch calls in this shell → all its workers share one crew). crew is
          # a PATH CLI now, so mint+export here (it can't set our env as a side effect).
          set -q CREW_ID; or set -gx CREW_ID (crew id)
          set -l crew_dir (git rev-parse --path-format=absolute --git-common-dir)/crew

          # FleetView-style codename+color, derived from the branch (deterministic).
          set -l ident (crew identity $branch)
          set -l agent_name (echo $ident | jq -r .name)
          set -l agent_color (echo $ident | jq -r .tmux)

          # Stamp the task file: header fields the worker protocol reads, the
          # closes line (Linear id or GH #num), and the full task body. The body
          # comes from $DISPATCH_SPEC — a file the dispatcher writes — because the
          # worker has no Linear/MCP access and must get the spec inline; it falls
          # back to just the title when no spec file is given.
          begin
              printf 'tier: %s\ntitle: %s\n%s\ndispatcher_pane: %s\ncrew_dir: %s\ncrew_id: %s\nagent_name: %s\n' \
                  $tier $title $closes $TMUX_PANE $crew_dir $CREW_ID $agent_name
              if set -q DISPATCH_SPEC; and test -f "$DISPATCH_SPEC"
                  printf '\n## Task\n\n'
                  cat $DISPATCH_SPEC
              end
          end > $wt_path/WORKER_TASK.md

          set -l ids (tmux new-window -d -c $wt_path -n $sanitized -P -F '#{window_id} #{pane_id}' | string split ' ')
          set -l win $ids[1]
          set -l pane $ids[2]
          # Color the worker's window in the status bar; leave the NAME to lazytmux
          # (its cwd reconciler owns @branch/@issue). @crew_* are stashed for a future
          # lazytmux format that could render the codename in the bar text.
          tmux set-window-option -t $win window-status-style "fg=$agent_color"
          tmux set-window-option -t $win window-status-current-style "fg=$agent_color,bold"
          tmux set-window-option -t $win @crew_name $agent_name
          tmux set-window-option -t $win @crew_color $agent_color
          tmux send-keys -t $pane \
              "claude --model $model --strict-mcp-config --mcp-config ~/.config/claude-code/mcp-worker.json --append-system-prompt-file ~/nix-config/home/ai/claude-code/WORKER_PROTOCOL.md --permission-mode auto 'Read WORKER_TASK.md and run it end-to-end. Push when pre-push passes; open a PR.'" Enter
      end
    '';

    # Start a dispatcher session: an orchestrator that judges tasks into tier+model
    # and fans them out via `dispatch`. Bakes DISPATCHER_PROTOCOL.md (the judgment
    # rubric); default model (opus) + full MCP, since the orchestrator needs them.
    "fish/functions/dispatcher.fish".text = ''
      function dispatcher --description 'Start a dispatcher session (DISPATCHER_PROTOCOL baked)'
          claude --append-system-prompt-file ~/nix-config/home/ai/claude-code/DISPATCHER_PROTOCOL.md $argv
      end
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

      shellAliases =
        {
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

          # Claude quick commands — haiku, no MCPs, restricted tools.
          # ALLOW_COMMIT_ON_DEFAULT=1 is inherited by the PreToolUse guard so a
          # deliberate quick commit on main isn't blocked.
          cco = ''ALLOW_COMMIT_ON_DEFAULT=1 claude --model haiku --strict-mcp-config --allowed-tools "Bash(git *)" -p "/commit"'';
          cpush = ''claude --model haiku --strict-mcp-config --allowed-tools "Bash(git *)" -p "/push"'';

          # OpenCode
          oc = "opencode";
          occ = "oc -c";
          ocs = "oc -s";

          # Tailscale (multi-account: `tailscale login` once per tailnet, then switch)
          tss = "tailscale status";
          tsl = "tailscale switch --list"; # profiles; current marked with *
          # operator/routing live in nixos/services/tailscale.nix; these only flip per-profile accept-routes
          tsp = "tailscale switch stellern@gmail.com && tailscale up && tailscale set --accept-routes=false";
          # tsw (work tailnet) is merged in below, work profile only.

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
        }
        // lib.optionalAttrs (osConfig.profile == "work") {
          # Work tailnet (factify) — only on the work machine.
          tsw = "tailscale switch noam@factify.com && tailscale up && tailscale set --accept-routes";
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
                    | jq -r '.[] | "pr:\(.number)\t\(.title)"' 2>/dev/null >$cache_file
              end
              command cat $cache_file 2>/dev/null
          end
          complete -c wt -n "__fish_seen_subcommand_from switch" -f -a "(__wt_switch_complete)"

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
