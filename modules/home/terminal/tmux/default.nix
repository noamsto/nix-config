{pkgs, ...}: {
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
          set -g @catppuccin_flavour 'frappe'
          set -g @catppuccin_window_tabs_enabled "on"
          set -g @catppuccin_host "on"
          set -g @catppuccin_date_time "%H:%M"
          set -g @catppuccin_datetime_icon ""
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
      {
        plugin = tmuxPlugins.continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-boot 'on'
          set -g @continuum-save-interval '10'
        '';
      }
      tmuxPlugins.vim-tmux-navigator
      tmuxPlugins.tmux-fzf
      tmuxPlugins.sidebar
      tmuxPlugins.yank
      {
        plugin = tmuxPlugins.tmux-thumbs;
        extraConfig = ''
          set -g @thumbs-key f
          set -g @thumbs-fg-color yellow
          set -g @thumbs-select-fg-color red
          set -g @thumbs-hint-fg-color blue
          set -g @thumbs-command 'echo -n {} | xclip -selection clipboard'
          set -g @thumbs-upcase-command 'tmux set-buffer -- {} && tmux paste-buffer'
        '';
      }
    ];
    extraConfig = ''
      set -g mouse on
      set -g base-index 1
      setw -g pane-base-index 1

      # Fix vim colors
      set -ga terminal-overrides ",*256col*:Tc"

      # Make prefix Ctrl+Space
      unbind C-b
      set-option -g prefix C-Space

      # Copy mode vim
      setw -g mode-keys vi
      unbind-key -T copy-mode-vi v
      bind-key -T copy-mode-vi v send -X begin-selection
      bind-key -T copy-mode-vi C-v send -X rectangle-toggle
      bind-key -T copy-mode-vi 'y' send -X copy-selection

      # restore clear screen to <prefix> C-l
      bind C-l send-keys 'C-l'
    '';
  };
}
