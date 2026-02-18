{
  pkgs,
  lib,
  ...
}: let
  upstream-catppuccin = pkgs.tmuxPlugins.mkTmuxPlugin rec {
    pluginName = "catppuccin";
    version = "2.1.3";
    src = pkgs.fetchFromGitHub {
      owner = "catppuccin";
      repo = "tmux";
      rev = "v${version}";
      sha256 = "0v3vji240mykfxf573kpwjmnswil0f9j7srqlhq74ca9ar1h5k92";
    };
    meta = with lib; {
      description = "Catppuccin theme for Tmux";
      homepage = "https://github.com/catppuccin/tmux";
      license = licenses.mit;
      platforms = platforms.all;
    };
  };
  tmux-nerd-font-window-name = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-nerd-font-window-name";
    version = "2025-03-21";
    src = pkgs.fetchFromGitHub {
      owner = "joshmedeski";
      repo = "tmux-nerd-font-window-name";
      rev = "9a66e18972de25c0bb3a58b7422d6e6555f166ba";
      sha256 = "sha256-X4Li6xkxKjqac7xedCNzzSoW7wT6N2oqVKIx7TFay64=";
    };
  };

  yamlFormat = pkgs.formats.yaml {};
  tmuxNerdFontConfig = {
    config = {
      fallback-icon = ""; # show when no definition is found
      multi-pane-icon = ""; # show when window has multiple panes (blank by default)
      show-name = false; # icon only; branch/dir name provided by automatic-rename-format
      icon-position = "left"; # show the icon to the "left" or "right" of the window name (defaults to left)
    };
    icons = {
      claude = "🧠";
      nh = "❄️";
      nix = "❄️";
      fish = "🐟";
      process-compose = "⚙️";
      amp = "⚡";
    };
  };

  seshUtils = import ./sesh-utils.nix {inherit pkgs;};
in {
  imports = [./named-session.nix];

  # Enable sesh with Home Manager module
  programs.sesh = {
    enable = true;
    enableTmuxIntegration = false; # Use custom keybindings below (K and S) instead
    icons = true; # Use sesh's built-in icons for visual distinction
    settings = {
      # Default session configuration
      default_session = {
        startup_command = "fish";
      };
      # Session directories to scan
      session_configs = [];
    };
  };

  home.packages = [
    # Custom sesh enhancement scripts
    seshUtils.sesh-new
    seshUtils.sesh-kill
    seshUtils.sesh-list-grouped
    seshUtils.sesh-icon
    seshUtils.sesh-preview
    seshUtils.sesh-extract-name

    # Claude status integration for tmux
    seshUtils.claude-status-update
    seshUtils.claude-status

    # Session sidebar
    seshUtils.tmux-sidebar
    seshUtils.tmux-sidebar-tui

    # Pane border styling
    seshUtils.tmux-set-pane-border

    # Pickers
    seshUtils.tmux-session-picker
    seshUtils.tmux-window-picker

    # Status bar helpers
    seshUtils.tmux-branch-display
    seshUtils.tmux-dir-display
    seshUtils.tmux-reflow-windows
  ];

  xdg.configFile."tmux/tmux-nerd-font-window-name.yml".source = yamlFormat.generate "tmux-nerd-font-window-name.yml" tmuxNerdFontConfig;

  # Start tmux server on login with default nix-config session
  systemd.user.services.tmux-startup = {
    Unit = {
      Description = "Start tmux server on login";
      After = ["graphical-session.target"];
      Wants = ["graphical-session.target"];
    };

    Service = let
      tmux-bin = "${lib.getExe pkgs.tmux}";
    in {
      Type = "forking";
      ExecStartPre = "${lib.getExe' pkgs.systemd "systemctl"} --user import-environment DISPLAY WAYLAND_DISPLAY XDG_SESSION_TYPE XDG_SESSION_DESKTOP XDG_CURRENT_DESKTOP COLORTERM TERM TERMINFO";
      # Create session if it doesn't exist, or succeed silently if it does
      ExecStart = "-${tmux-bin} new -s nix-config -c %h/nix-config -d";
      # Don't kill session on stop - let it persist across home-manager switches
      RemainAfterExit = true;
      # Prevent shutdown hang - stop quickly since tmux persists anyway
      TimeoutStopSec = "5s";
      Environment = [
        "COLORTERM=truecolor"
        "TERM=xterm-kitty"
        "TERM_PROGRAM=kitty"
        "TERMINFO=${pkgs.kitty}/share/terminfo"
        "TMUX_TMPDIR=%t"
      ];
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };

  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    historyLimit = 1500000; # Large buffer to mitigate Claude Code scroll event storm (issue #9935)
    baseIndex = 1; # Start windows at 1, set early in config to avoid race conditions
    plugins = with pkgs; [
      tmuxPlugins.better-mouse-mode
      # catppuccin theme must be loaded before manual continuum loading
      {
        plugin = upstream-catppuccin;
        extraConfig = ''
          # Flavor is set dynamically by theme-toggle script, default to mocha
          if-shell '[ -z "#{@catppuccin_flavor}" ]' 'set -g @catppuccin_flavor mocha'
          set -g @catppuccin_status_background 'none'
          set -g @catppuccin_window_status_style 'none'
          set -g @catppuccin_window_flags 'icon'
          set -g @catppuccin_window_flags_icon_last " 󰖰"
          set -g @catppuccin_window_flags_icon_current " 󰖯"
          set -g @catppuccin_window_flags_icon_zoom " 󰁌"
          set -g @catppuccin_window_flags_icon_mark " 󰃀"
          set -g @catppuccin_window_flags_icon_silent " 󰂛"
          set -g @catppuccin_window_flags_icon_activity " 󱅫"
          set -g @catppuccin_window_flags_icon_bell " 󰂞"
          set -g @catppuccin_pane_status_enabled 'off'
          set -g @catppuccin_pane_border_status 'off'
        '';
      }
      {
        plugin = tmuxPlugins.resurrect;
        extraConfig = ''
          set -g @resurrect-strategy-vim 'session'
          set -g @resurrect-strategy-nvim 'session'
          set -g @resurrect-capture-pane-contents 'on'
        '';
      }
      tmuxPlugins.vim-tmux-navigator
      tmuxPlugins.tmux-fzf
      {
        plugin = tmuxPlugins.continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '10'
        '';
      }
    ];
    extraConfig = ''
      set -g mouse on
      # Multi-client: use smallest client size so all see the same content
      set -g window-size smallest
      set -g aggressive-resize on

      # pane-base-index must be set here (HM only handles window base-index)
      set -g pane-base-index 1
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded!"

      # renumber when window is closed
      set-option -g renumber-window on

      # allow focus events for kitty
      set -g focus-events on


      set -g allow-passthrough on
      set -g visual-activity off

      # Preserve terminal environment variables for proper detection
      set -ga update-environment TERM
      set -ga update-environment TERM_PROGRAM
      set -ga update-environment COLORTERM
      set -ga update-environment TERMINFO
      set -ga update-environment TERMINFO_DIRS


      # Set escape-time as recomended by nvim
      set -s escape-time 0

      # Faster repeat times (tmux 3.6+)
      set -g repeat-time 300
      set -g initial-repeat-time 600

      # Enable extended keyboard protocol support
      set -g extended-keys on
      set -as terminal-features 'xterm-kitty*:extkeys'
      set -s set-clipboard on
      set -s copy-command 'wl-copy'

      # Make prefix back-tick
      unbind C-b
      set-option -g prefix `
      bind ` send-prefix

      # Copy mode vim
      setw -g mode-keys vi
      unbind-key -T copy-mode-vi v
      bind-key -T copy-mode-vi v send -X begin-selection
      bind-key -T copy-mode-vi C-v send -X rectangle-toggle
      bind-key -T copy-mode-vi 'y' send -X copy-selection

      # Copy mode styling (tmux 3.6+)
      set -g copy-mode-position-style "bg=#{@thm_surface_0},fg=#{@thm_mauve}"
      set -g copy-mode-selection-style "bg=#{@thm_mauve},fg=#{@thm_bg}"

      # restore clear screen to <prefix> C-L
      bind -n M-l send-keys 'C-l'

      # Shift+Enter: process-aware newline for Claude Code / Amp
      # Amp needs backslash + Enter, Claude Code needs Alt+Enter
      bind -n S-Enter if-shell "ps -o comm= -t '#{pane_tty}' | grep -qE '^(amp|bun)$'" "send-keys \\\\ Enter" "send-keys M-Enter"

      # Bind window spliting
      unbind %
      bind | split-window -h -c "#{pane_current_path}"
      unbind '"'
      bind _ split-window -v -c "#{pane_current_path}"

      # Bind windows movment alt-shift l/h
      bind -n M-H previous-window
      bind -n M-L next-window

      # Session sidebar toggle
      bind -n M-b run-shell "tmux-sidebar"

      # Session picker - wrapper pre-computes claude status into @claude_status,
      # then opens choose-tree (avoids tmux #() caching returning empty on first call)
      bind s run-shell 'tmux-session-picker'
      # Window picker - wrapper pre-computes claude status per window, then opens choose-tree
      bind w run-shell 'tmux-window-picker'

      # Create new session with name prompt (Prefix+N)
      bind N command-prompt -p "New session name:" "new-session -s '%%'"

      bind-key "K" display-popup -E -w 40% -k "sesh connect \"$(
      sesh list -i | ${lib.getExe pkgs.gum} filter --no-strip-ansi --limit 1 --no-sort --fuzzy --placeholder 'Pick a sesh' --height 50 --prompt='⚡'
      )\""

      # Main session picker: Prefix+S with comprehensive preview
      bind-key "S" run-shell "sesh connect \"$(
      sesh list --icons | fzf-tmux -p 90%,85% \
        --no-sort --ansi --border-label '  Sessions ' --prompt '⚡  ' \
        --header '  ^a all ^t tmux ^g configs ^x zoxide ^d kill ^f find' \
        --bind 'tab:down,btab:up' \
        --bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list --icons)' \
        --bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t --icons)' \
        --bind 'ctrl-g:change-prompt(⚙️  )+reload(sesh list -c --icons)' \
        --bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z --icons)' \
        --bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' \
        --bind 'ctrl-d:execute(tmux kill-session -t {})' \
        --preview-window 'right:60%:wrap' \
        --preview 'sesh-preview {}'
      )\""

      bind-key x kill-pane # skip "kill-pane 1? (y/n)" prompt
      bind-key & confirm-before -p "kill-window #W? (y/n)" kill-window
      set -g detach-on-destroy off  # don't exit from tmux when closing a session

      # Navigation: pass to vim if in vim, otherwise navigate tmux (but not if zoomed)
      is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|l?n?vim?x?|fzf)(diff)?$'"
      bind-key -n C-h if-shell "$is_vim" "send-keys C-h" "if-shell '[ #{window_zoomed_flag} -eq 0 ]' 'select-pane -L'"
      bind-key -n C-j if-shell "$is_vim" "send-keys C-j" "if-shell '[ #{window_zoomed_flag} -eq 0 ]' 'select-pane -D'"
      bind-key -n C-k if-shell "$is_vim" "send-keys C-k" "if-shell '[ #{window_zoomed_flag} -eq 0 ]' 'select-pane -U'"
      bind-key -n C-l if-shell "$is_vim" "send-keys C-l" "if-shell '[ #{window_zoomed_flag} -eq 0 ]' 'select-pane -R'"


      # Sync window name with terminal name
      set-option -g set-titles on
      set-option -g set-titles-string "#S / #{pane_current_command}"


      # Catppuccin + 2-line status bar
      set -g allow-rename off
      set -g status-position top
      set -g status-interval 1
      set -g status-style "bg=#{@thm_bg}"

      # Multi-line status bar (tmux 3.4+)
      # Dynamically set to 2 or 3 lines by tmux-reflow-windows hook
      set -g status 2
      set -g @window_split 999
      set -g @window_split2 999

      # Icon variables (set these to your preferred nerd font icons)
      set -g @icon_session ""
      set -g @icon_branch ""
      set -g @icon_dir ""

      # Line 0: Session  Branch  Dir (left) │ App (right)
      # Session: mauve (subtle), Branch: blue bold, Dir: subtext, App: subtext, prefix: red
      # Icons provide visual separation, no pipes needed
      # Continuum save script runs invisibly at start to trigger periodic saves
      set -g status-format[0] "#(${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/scripts/continuum_save.sh)#[align=left,bg=#{@thm_bg}]#{?client_prefix,#[fg=#{@thm_red}#,bold],#[fg=#{@thm_mauve}]} #{@icon_session} #S  #[fg=#{@thm_blue},bold]#{@icon_branch} #(tmux-branch-display '#{@branch}' '#{pane_current_path}')  #[fg=#{@thm_subtext_0},nobold]#{@icon_dir} #(tmux-dir-display '#{@branch}' '#{pane_current_path}') #[align=right,fg=#{@thm_overlay_1}]#(claude-status --session '#{session_name}' --format icon-color) "

      # Lines 1-3: Window list — dynamically generated by tmux-reflow-windows hook
      # The hook computes split points, padding width, and sets status-format[1-3] directly.
      # These are fallback defaults before the first hook runs:
      set -g status-format[1] "#[align=left,bg=#{@thm_bg}]#[fg=#{@thm_overlay_1}] ╰─ #{W:#[range=window|#{window_index}]#{?window_active,#[fg=#{@thm_green}#,bold]#{window_index}: #{window_name},#[fg=#{@thm_subtext_0}#,nobold]#{window_index}: #[fg=#{@thm_fg}]#{window_name}}#{?window_zoomed_flag, 󰁌,}#(claude-status --window '#{session_name}:#{window_index}')#[norange]#{?window_end_flag,, #[fg=#{@thm_subtext_0}#,nobold]│ }}"
      set -g status-format[2] ""
      set -g status-format[3] ""

      # Hooks to reflow windows across status lines on layout changes
      # Pass #{session_name} and #{client_width} so the script operates on the correct session
      set-hook -g window-linked      'run-shell "tmux-reflow-windows #{session_name} #{client_width}"'
      set-hook -g window-unlinked    'run-shell "tmux-reflow-windows #{session_name} #{client_width}"'
      set-hook -g window-renamed     'run-shell "tmux-reflow-windows #{session_name} #{client_width}"'
      set-hook -g client-resized     'run-shell "tmux-reflow-windows #{session_name} #{client_width}"'
      set-hook -g after-new-session   'run-shell "tmux-reflow-windows #{session_name} #{client_width}"'
      set-hook -g client-session-changed 'run-shell "tmux-reflow-windows #{session_name} #{client_width}"'

      # Pane border - dot on active split, clean line when zoomed/inactive
      # Full themed format is set by theme-toggle script after reading @thm_* values
      setw -g pane-border-status top
      setw -g pane-border-format "━━━━━"
      setw -g pane-active-border-style "bg=#{@thm_bg},fg=#{@thm_mauve}"
      setw -g pane-border-style "bg=#{@thm_bg},fg=#{@thm_overlay_1}"
      setw -g pane-border-lines heavy

      # Pane background: dim inactive panes to make active pane stand out
      set -g window-style "fg=#{@thm_text},bg=#{@thm_mantle}"
      set -g window-active-style "fg=#{@thm_text},bg=#{@thm_bg}"

      # Pane scrollbars (tmux 3.6+) - disabled to prevent resize issues
      set -g pane-scrollbars off
      # set -g pane-scrollbars-position right
      # set -g pane-scrollbars-style "bg=#{@thm_surface_0},fg=#{@thm_mauve}"

      # Prompt cursor styling (tmux 3.6+)
      set -g prompt-cursor-style "blinking-bar"
      set -g prompt-cursor-colour "colour183"  # Catppuccin mauve (#cba6f7)

      # Window naming: nerd font icon (process-aware) + branch or dir name
      # #{window_icon} is replaced by the nerd font plugin with the process icon (🐟, 🤖, etc.)
      # @branch (set by wt) gives stable names; falls back to dir basename for non-wt windows
      set -wg automatic-rename on
      set -g automatic-rename-format "#{window_icon} #{?#{@branch},#{=20:@branch}#{?#{==:#{=20:@branch},#{@branch}},,…},#{b:pane_current_path}}"

      run-shell ${tmux-nerd-font-window-name}/share/tmux-plugins/tmux-nerd-font-window-name/tmux-nerd-font-window-name.tmux

      # Load tmux-fingers after nerd-font-window-name
      # Catppuccin Mocha colors
      set -g @fingers-hint-style "fg=colour234,bg=colour183,bold"           # Crust on Mauve
      set -g @fingers-highlight-style "fg=colour216,bg=colour236"           # Peach on Surface0
      set -g @fingers-selected-hint-style "fg=colour234,bg=colour151,bold"  # Crust on Green
      set -g @fingers-selected-highlight-style "fg=colour116,bg=colour236"  # Teal on Surface0

      # Custom patterns
      set -g @fingers-pattern-0 "[A-Z]{2,}-[0-9]+"                          # Linear/JIRA tickets (NOA-123)
      set -g @fingers-pattern-1 "[a-z][a-z_]*_[0-9a-hjkmnp-tv-z]{26}"       # TypeIDs (user_2x4y6z8a0b...)
      set -g @fingers-pattern-2 "sha256-[A-Za-z0-9+/]{43}="                 # Nix SRI hashes
      set -g @fingers-pattern-3 "sha256:[0-9a-z]{52}"                       # Nix base32 hashes

      run-shell ${pkgs.tmuxPlugins.fingers}/share/tmux-plugins/tmux-fingers/tmux-fingers.tmux

      # WORKAROUND: tmux-fingers colors don't work on initial server start
      # Reload entire config on first client attach to ensure styles are applied
      set-hook -g client-attached[99] 'source-file ~/.config/tmux/tmux.conf'

      # Set pane-border-format with expanded @thm_* color values
      # Must run after catppuccin theme loads (which sets @thm_* variables)
      run-shell "tmux-set-pane-border"
    '';
  };
}
