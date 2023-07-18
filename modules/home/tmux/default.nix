{pkgs, ...}: let
  tmux-super-fingers =
    pkgs.tmuxPlugins.mkTmuxPlugin
    {
      pluginName = "tmux-super-fingers";
      version = "unstable-2023-01-06";
      src = pkgs.fetchFromGitHub {
        owner = "artemave";
        repo = "tmux_super_fingers";
        rev = "2c12044984124e74e21a5a87d00f844083e4bdf7";
        sha256 = "sha256-cPZCV8xk9QpU49/7H8iGhQYK6JwWjviL29eWabuqruc=";
      };
    };
in {
  programs.tmux = {
    enable = true;
    #shell = "bash";
    terminal = "tmux-256color";
    sensibleOnTop = true;
    historyLimit = 100000;
    plugins = with pkgs; [
      {
        plugin = tmux-super-fingers;
        extraConfig = "set -g @super-fingers-key f";
      }
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
      
    '';
  };
}
