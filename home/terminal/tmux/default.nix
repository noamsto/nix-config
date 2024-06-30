{
  pkgs,
  lib,
  ...
}: let
  # sessinx = pkgs.mkTmuxPlugin {
  #   pluginName = "continuum";
  #   version = "unstable-2022-01-25";
  #   src = pkgs.fetchFromGitHub {
  #     owner = "tmux-plugins";
  #     repo = "tmux-continuum";
  #     rev = "fc2f31d79537a5b349f55b74c8ca69abaac1ddbb";
  #     sha256 = "06i1jp83iybw76raaxciqz9a7ypgpkvbyjn6jjap8jpqfmj2wmjb";
  #   };
  #   meta = {
  #     homepage = "https://github.com/tmux-plugins/tmux-continuum";
  #     description = "continuous saving of tmux environment";
  #     longDescription = ''
  #       Features:
  #       * continuous saving of tmux environment
  #       * automatic tmux start when computer/server is turned on
  #       * automatic restore when tmux is started
  #
  #       Together, these features enable uninterrupted tmux usage. No matter the
  #       computer or server restarts, if the machine is on, tmux will be there how
  #       you left it off the last time it was used.
  #     '';
  #     license = lib.licenses.mit;
  #     platforms = lib.platforms.unix;
  #     maintainers = with lib.maintainers; [ronanmacf];
  #   };
  # };
in {
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

      set -g status-position top

      # Set escape-time as recomended by nvim
      set-option -sg escape-time 12

      # Fix vim colors
      set -ga terminal-overrides ",*256col*:Tc"

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
