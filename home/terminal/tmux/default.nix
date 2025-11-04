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
      zsh = "";
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

  home.packages = with pkgs; [
    # Custom sesh enhancement scripts
    seshUtils.sesh-new
    seshUtils.sesh-kill
    seshUtils.sesh-list-grouped
    seshUtils.sesh-icon
    seshUtils.sesh-preview
    seshUtils.sesh-extract-name
    seshUtils.worktree-session-hook
  ];

  xdg.configFile."tmux/tmux-nerd-font-window-name.yml".source = yamlFormat.generate "tmux-nerd-font-window-name.yml" tmuxNerdFontConfig;

  systemd.user.services.tmux-startup = {
    Unit = {
      Description = "Start tmux detached on login";
      After = ["graphical-session.target"];
      Wants = ["graphical-session.target"];
    };

    Service = let
      tmux-bin = "${lib.getExe pkgs.tmux}";
      session = "main"; # Main session for terminal startup
    in {
      Type = "forking";
      ExecStartPre = "${lib.getExe' pkgs.systemd "systemctl"} --user import-environment DISPLAY WAYLAND_DISPLAY XDG_SESSION_TYPE XDG_SESSION_DESKTOP XDG_CURRENT_DESKTOP COLORTERM TERM TERMINFO";
      ExecStart = "-${tmux-bin} new -s ${session} -d";
      ExecStop = "-${tmux-bin} kill-session -t ${session}";
      Environment = [
        "COLORTERM=truecolor"
        "TERM=kitty"
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
          set -g @catppuccin_flavor 'mocha'
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
      tmuxPlugins.fingers
    ];
    extraConfig = ''
      set -g mouse on
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

      # Set escape-time as recomended by nvim
      set -s escape-time 0

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

      # Order sessions alphabeticaly
      bind s choose-tree -Zs -O name
      bind w choose-tree -Zw -O name

      # Create new session with name prompt
      bind S command-prompt -p "New session name:" "new-session -s '%%'"

      bind-key "K" display-popup -E -w 40% "sesh connect \"$(
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
        --bind 'ctrl-d:execute(tmux kill-session -t \"$(sesh-extract-name {})\")' \
        --bind 'ctrl-r:change-prompt(⚡  )+reload(sesh list --icons)' \
        --preview-window 'right:60%:wrap' \
        --preview 'sesh-preview {}'
      )\""

      bind-key x kill-pane # skip "kill-pane 1? (y/n)" prompt
      set -g detach-on-destroy off  # don't exit from tmux when closing a session


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

      setw -g pane-border-status top
      setw -g pane-border-format ""
      setw -g pane-active-border-style "bg=#{@thm_bg},fg=#{@thm_mauve}"
      setw -g pane-border-style "bg=#{@thm_bg},fg=#{@thm_overlay_1}"
      setw -g pane-border-lines heavy

      set -g status-left ""
      set -ga status-left "#{?client_prefix,#{#[bg=#{@thm_red},fg=#{@thm_bg},bold]  #S },#{#[bg=#{@thm_bg},fg=#{@thm_green}]  #S }}"
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

      set -g window-status-format " #I#{?window_zoomed_flag,#{E:@catppuccin_window_flags_icon_zoom},} "
      set -g window-status-style "bg=#{@thm_bg},fg=#{@thm_rosewater}"
      set -g window-status-last-style "bg=#{@thm_bg},fg=#{@thm_peach}"
      set -g window-status-activity-style "bg=#{@thm_red},fg=#{@thm_bg}"
      set -g window-status-bell-style "bg=#{@thm_red},fg=#{@thm_bg},bold"
      set -gF window-status-separator "#[bg=#{@thm_bg},fg=#{@thm_overlay_0}]│"

      set -g window-status-current-format " #I#{?window_zoomed_flag,#{E:@catppuccin_window_flags_icon_zoom},} "
      set -g window-status-current-style "bg=#{@thm_peach},fg=#{@thm_bg},bold"


      # Load continuum manually after status line configuration
      set -g @continuum-restore 'on'
      set -g @continuum-save-interval '10'
      run-shell ${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/continuum.tmux

      run-shell ${tmux-nerd-font-window-name}/share/tmux-plugins/tmux-nerd-font-window-name/tmux-nerd-font-window-name.tmux
    '';
  };
}
