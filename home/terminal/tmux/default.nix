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
      rev = "4c9e7a51387d0cead1465a3628244beb790a3c95";
      sha256 = "sha256-UcfEsq7BqJMeYXtGDNMoi/E+iEnEe9iM2KVoi7ektOE=";
    };
  };

  yamlFormat = pkgs.formats.yaml {};
  tmuxNerdFontConfig = {
    config = {
      fallback-icon = ""; # show when no definition is found
      multi-pane-icon = ""; # show when window has multiple panes (blank by default)
      show-name = true; # show the window name with the icon (defaults to false)
      icon-position = "left"; # show the icon to the "left" or "right" of the window name (defaults to left)
    };
    icons = {
      claude = "🧠";
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
    seshUtils.worktree-session-hook

    # Claude status integration for tmux
    seshUtils.claude-status-update
    seshUtils.claude-tmux-indicator
    seshUtils.claude-session-status
    seshUtils.claude-priority-window
  ];

  xdg.configFile."tmux/tmux-nerd-font-window-name.yml".source = yamlFormat.generate "tmux-nerd-font-window-name.yml" tmuxNerdFontConfig;

  # Start tmux server on login
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
      ExecStart = "-${tmux-bin} new -s main -d";
      ExecStop = "-${tmux-bin} kill-session -t main";
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
    historyLimit = 100000;
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
    ];
    extraConfig = ''
      set -g mouse on
      # Multi-client: use smallest client size so all see the same content
      set -g window-size smallest
      set -g aggressive-resize on

      # start index at 1
      set -g base-index 1
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

      # Bind window spliting
      unbind %
      bind | split-window -h -c "#{pane_current_path}"
      unbind '"'
      bind _ split-window -v -c "#{pane_current_path}"

      # Bind windows movment alt-shift l/h
      bind -n M-H previous-window
      bind -n M-L next-window

      # Session picker with Claude priority window
      # - Shows session name + priority window (Claude window if exists, else active)
      # - Selecting a session navigates directly to the priority window
      # Format: session rows show "session │ priority_window", window rows show window with indicator
      bind s choose-tree -Zs -O name \
        -F '#{?window_id,#{window_name} #(claude-tmux-indicator --window "#{session_name}:#{window_index}"),#{session_name} │ #(claude-priority-window "#{session_name}" --display)}' \
        'run-shell "tmux switch-client -t \"$(claude-priority-window \"%1\" --target)\""'
      bind w choose-tree -Zw -O name

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
      set -g detach-on-destroy off  # don't exit from tmux when closing a session

      # Navigation: pass to vim if in vim, otherwise navigate tmux (but not if zoomed)
      is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|l?n?vim?x?|fzf)(diff)?$'"
      bind-key -n C-h if-shell "$is_vim" "send-keys C-h" "if-shell '[ #{window_zoomed_flag} -eq 0 ]' 'select-pane -L'"
      bind-key -n C-j if-shell "$is_vim" "send-keys C-j" "if-shell '[ #{window_zoomed_flag} -eq 0 ]' 'select-pane -D'"
      bind-key -n C-k if-shell "$is_vim" "send-keys C-k" "if-shell '[ #{window_zoomed_flag} -eq 0 ]' 'select-pane -U'"
      bind-key -n C-l if-shell "$is_vim" "send-keys C-l" "if-shell '[ #{window_zoomed_flag} -eq 0 ]' 'select-pane -R'"


      # Sync window name with terminal name
      set-option -g set-titles on
      set-option -g set-titles-string "#S / #W"


      # Catppucin
      set -g allow-rename off
      set -g status-position top
      set -g status-justify "absolute-centre"
      set -g status-interval 1
      set -g status-left-length 100
      set -g status-right-length 100
      set -g status-style "bg=#{@thm_bg}"

      # Pane border - dot on active split, clean line when zoomed/inactive
      # Full themed format is set by theme-toggle script after reading @thm_* values
      setw -g pane-border-status top
      setw -g pane-border-format "━━━━━"
      setw -g pane-active-border-style "bg=#{@thm_bg},fg=#{@thm_mauve}"
      setw -g pane-border-style "bg=#{@thm_bg},fg=#{@thm_overlay_1}"
      setw -g pane-border-lines heavy

      # Pane scrollbars (tmux 3.6+) - disabled to prevent resize issues
      set -g pane-scrollbars off
      # set -g pane-scrollbars-position right
      # set -g pane-scrollbars-style "bg=#{@thm_surface_0},fg=#{@thm_mauve}"

      # Prompt cursor styling (tmux 3.6+)
      set -g prompt-cursor-style "blinking-bar"
      set -g prompt-cursor-colour "colour183"  # Catppuccin mauve (#cba6f7)

      set -g status-left ""
      set -ga status-left "#{?client_prefix,#{#[bg=#{@thm_red},fg=#{@thm_bg},bold]  #S },#{#[bg=#{@thm_bg},fg=#{@thm_green}]  #S }}"
      set -ga status-left "#[bg=#{@thm_bg},fg=#{@thm_overlay_0},none]│"
      set -ga status-left "#[bg=#{@thm_bg},fg=#{@thm_mauve}] #{window_name} "
      set -ga status-left "#[bg=#{@thm_bg},fg=#{@thm_overlay_0},none]│"
      set -ga status-left "#[bg=#{@thm_bg},fg=#{@thm_blue}]  #{=/-32/...:#{s|$USER|~|:#{b:pane_current_path}}} "

      set -g status-right ""
      set -ga status-right "#[bg=#{@thm_bg},fg=#{@thm_overlay_0},none]│ "
      set -ga status-right "#[bg=#{@thm_bg},fg=#{@thm_blue}] #H "

      # Window look and feel with nerd font icons
      set -wg automatic-rename on
      set -g automatic-rename-format "Window"

      # Window status with Claude indicator
      # Use subtext colors for better contrast in light theme (rosewater is too light)
      set -g window-status-format " #I#{?window_zoomed_flag,#{E:@catppuccin_window_flags_icon_zoom},} #(claude-tmux-indicator --window '#{session_name}:#{window_index}') "
      set -g window-status-style "bg=#{@thm_bg},fg=#{@thm_subtext_0}"
      set -g window-status-last-style "bg=#{@thm_bg},fg=#{@thm_subtext_1}"
      set -g window-status-activity-style "bg=#{@thm_red},fg=#{@thm_bg}"
      set -g window-status-bell-style "bg=#{@thm_red},fg=#{@thm_bg},bold"
      set -gF window-status-separator "#[bg=#{@thm_bg},fg=#{@thm_overlay_0}]│"

      set -g window-status-current-format " #I#{?window_zoomed_flag,#{E:@catppuccin_window_flags_icon_zoom},} #(claude-tmux-indicator --window '#{session_name}:#{window_index}') "
      set -g window-status-current-style "bg=#{@thm_bg},fg=#{@thm_mauve},bold"


      # Load continuum manually after status line configuration
      set -g @continuum-restore 'on'
      set -g @continuum-save-interval '10'
      run-shell ${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/continuum.tmux

      run-shell ${tmux-nerd-font-window-name}/share/tmux-plugins/tmux-nerd-font-window-name/tmux-nerd-font-window-name.tmux

      # Load tmux-fingers LAST to ensure all settings are ready
      # Catppuccin Mocha colors
      set -g @fingers-hint-style "fg=colour234,bg=colour183,bold"           # Crust on Mauve
      set -g @fingers-highlight-style "fg=colour216,bg=colour236"           # Peach on Surface0
      set -g @fingers-selected-hint-style "fg=colour234,bg=colour151,bold"  # Crust on Green
      set -g @fingers-selected-highlight-style "fg=colour116,bg=colour236"  # Teal on Surface0

      run-shell ${pkgs.tmuxPlugins.fingers}/share/tmux-plugins/tmux-fingers/tmux-fingers.tmux

      # WORKAROUND: tmux-fingers colors don't work on initial server start
      # Reload entire config on first client attach to ensure styles are applied
      set-hook -g client-attached[99] 'source-file ~/.config/tmux/tmux.conf'
    '';
  };
}
