{
  pkgs,
  lib,
  ...
}: let
  upstream-catppuccin = pkgs.tmuxPlugins.mkTmuxPlugin rec {
    pluginName = "catppuccin";
    version = "2.1.1";
    src = pkgs.fetchFromGitHub {
      owner = "catppuccin";
      repo = "tmux";
      rev = "v${version}";
      sha256 = "9+SpgO2Co38I0XnEbRd7TSYamWZNjcVPw6RWJIHM+4c=";
    };
    meta = with lib; {
      description = "Catppuccin theme for Tmux";
      homepage = "https://github.com/catppuccin/tmux";
      license = licenses.mit;
      platforms = platforms.all;
    };
  };
  tmux-nerd-font-window-name = pkgs.tmuxPlugins.mkTmuxPlugin rec {
    pluginName = "tmux-nerd-font-window-name";
    version = "2.1.2";
    src = pkgs.fetchFromGitHub {
      owner = "joshmedeski";
      repo = "tmux-nerd-font-window-name";
      rev = "v${version}";
      sha256 = "bnlOAfdBv5Rg4z1hu1jtdx5oZ6kAZE40K4zqLxmyYQE=";
    };
  };
in {
  imports = [./named-session.nix];
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
      session = "'󱥸  General'";
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
    historyLimit = 100000;
    plugins = with pkgs; [
      tmuxPlugins.better-mouse-mode
      # must be before continuum edits right status bar
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
      {
        plugin = tmuxPlugins.tmux-thumbs;
        extraConfig = ''
          set -g @thumbs-key f
          set -g @thumbs-fg-color yellow
          set -g @thumbs-select-fg-color red
          set -g @thumbs-hint-fg-color blue
          set -g @thumbs-command 'echo -n {} | ${pkgs.wl-clipboard-rs}/bin/wl-copy'
          set -g @thumbs-upcase-command 'tmux set-buffer -- {} && tmux paste-buffer'
        '';
      }
    ];
    extraConfig = ''
      set -g mouse on
      # start index at 1
      set -g base-index 1
      set -g pane-base-index 1

      # renumber when window is closed
      set-option -g renumber-window on

      # Yazi inside tmux
      set -g allow-passthrough on
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
      set -g status-interval 5
      set -g status-left-length 100
      set -g status-right-length 100

      setw -g pane-border-status top
      setw -g pane-border-lines single
      setw -g pane-border-format ""

      set -g status-left ""
      set -g status-right ""
      set -agF status-left "#{@catppuccin_status_host}"
      set -agF status-right "#{E:@catppuccin_status_cpu}"
      set -agF status-right "#{E:@catppuccin_status_battery}"


      run-shell ${pkgs.tmuxPlugins.cpu}/share/tmux-plugins/cpu/cpu.tmux
      run-shell ${pkgs.tmuxPlugins.battery}/share/tmux-plugins/battery/battery.tmux

      run-shell ${tmux-nerd-font-window-name}/share/tmux-plugins/tmux-nerd-font-window-name/tmux-nerd-font-window-name.tmux
    '';
  };
}
