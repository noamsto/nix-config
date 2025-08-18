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
in {
  imports = [./named-session.nix];
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
        "TERM=ghostty"
        "TERM_PROGRAM=ghostty"
        "TERMINFO=${pkgs.ghostty.terminfo}/share/terminfo"
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
          set -g @catppuccin_window_status_style 'rounded'
          set -g @catppuccin_window_number_position 'right'
          set -g @catppuccin_window_status 'no'
          set -g @catppuccin_window_flags "icon"
          set -g @catppuccin_window_text '#W'
          set -g @catppuccin_window_current_text '#W'
          set -g @catppuccin_window_current_color '#{E:@thm_surface_2}'
          set -g @catppuccin_status_module_text_bg '#{E:@thm_mantle}'
          set -g @catppuccin_status_connect_separator 'yes'
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
      bind r source-file ~/.tmux.conf \; display "Config reloaded!"

      # renumber when window is closed
      set-option -g renumber-window on


      set -g allow-passthrough on
      set -g visual-activity off

      # Yazi inside tmux
      set -ga update-environment TERM
      set -ga update-environment TERM_PROGRAM

      # Set escape-time as recomended by nvim
      set -s escape-time 0

      # Fix vim colors
      set -ga terminal-overrides ",foot:Tc"

      # Foot terminal
      # set -as terminal-features 'foot*:extkeys'
      set -g extended-keys on
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

      setw -g pane-border-status top
      setw -g pane-border-lines single
      setw -g pane-border-format ""

      set -g status-left ""
      set -g status-right ""
      set -g status-left "#{E:@catppuccin_status_session}"
      set -ga status-left "#[bg=#{@thm_bg},fg=#{@thm_blue}]  #{=/-32/...:#{s|$USER|~|:#{b:pane_current_path}}} "
      set -gF status-right "#{@catppuccin_status_host}"

      # Load continuum manually after status line configuration
      set -g @continuum-restore 'on'
      set -g @continuum-save-interval '10'
      run-shell ${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/continuum.tmux

      run-shell ${tmux-nerd-font-window-name}/share/tmux-plugins/tmux-nerd-font-window-name/tmux-nerd-font-window-name.tmux
    '';
  };
}
