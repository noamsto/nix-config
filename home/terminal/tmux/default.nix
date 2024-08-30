{
  pkgs,
  lib,
  ...
}: {
  programs.zsh.oh-my-zsh.plugins = ["tmux"];
  programs.fzf = {
    tmux.enableShellIntegration = true;
    tmux.shellIntegrationOptions = ["-p80%,60%"];
  };

  systemd.user.services.tmux-startup = {
    Unit = {
      Description = "Start tmux detached on login";
      After = ["graphical-session.target"];
    };

    Service = let
      tmux-bin = "${lib.getExe pkgs.tmux}";
      session = "'󱥸 General'";
    in {
      Type = "forking";
      ExecStartPre = "${lib.getExe' pkgs.systemd "systemctl"} --user import-environment TMUX_TMPDIR DISPLAY WAYLAND_DISPLAY XDG_SESSION_TYPE XDG_SESSION_DESKTOP XDG_CURRENT_DESKTOP";
      ExecStart = "-${tmux-bin} new -s ${session} -d";
      ExecStop = "-${tmux-bin} kill-session -t ${session}";
      # Restart = "always";
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };

  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    sensibleOnTop = true;
    historyLimit = 100000;
    plugins = with pkgs; [
      tmuxPlugins.better-mouse-mode
      # must be before continuum edits right status bar
      {
        plugin = tmuxPlugins.catppuccin;
        extraConfig = ''
          set -g @catppuccin_flavor 'mocha'
          set -g @catppuccin_window_left_separator ""
          set -g @catppuccin_window_right_separator " "
          set -g @catppuccin_window_middle_separator " █"
          set -g @catppuccin_window_number_position "right"

          set -g @catppuccin_window_default_fill "number"
          set -g @catppuccin_window_default_text "#W"

          set -g @catppuccin_window_current_fill "number"
          set -g @catppuccin_window_current_text "#W"

          set -g @catppuccin_status_modules_right "application session battery date_time"
          set -g @catppuccin_status_left_separator  " "
          set -g @catppuccin_status_right_separator ""
          set -g @catppuccin_status_fill "icon"
          set -g @catppuccin_status_connect_separator "no"
        '';
      }
      tmuxPlugins.battery
      {
        plugin = tmuxPlugins.resurrect;
        extraConfig = ''
          set -g @resurrect-strategy-vim 'session'
          set -g @resurrect-strategy-nvim 'session'
          set -g @resurrect-capture-pane-contents 'on'
        '';
      }
      {
        plugin = tmuxPlugins.continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '10'
        '';
      }
      tmuxPlugins.vim-tmux-navigator
      tmuxPlugins.tmux-fzf
      tmuxPlugins.yank
      {
        plugin = tmuxPlugins.tmux-thumbs;
        extraConfig = ''
          set -g @thumbs-key f
          set -g @thumbs-fg-color yellow
          set -g @thumbs-select-fg-color red
          set -g @thumbs-hint-fg-color blue
          # set -g @thumbs-command 'echo -n {} | xclip -selection clipboard'
          set -g @thumbs-command 'echo -n {} | ${pkgs.wl-clipboard}/bin/wl-copy'
          set -g @thumbs-upcase-command 'tmux set-buffer -- {} && tmux paste-buffer'
        '';
      }
    ];
    extraConfig = ''
      set -g mouse on
      set -g base-index 1
      setw -g pane-base-index 1

      # Yazi inside tmux
      set -g allow-passthrough on
      set -ga update-environment TERM
      set -ga update-environment TERM_PROGRAM

      # Set escape-time as recomended by nvim
      set-option -sg escape-time 12

      # Fix vim colors
      set -ga terminal-overrides ",foot:Tc"

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
    '';
  };
}
