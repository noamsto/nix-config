{pkgs, ...}: {
  programs.kitty = {
    enable = true;
    settings = {
      # Background and transparency
      background_opacity = "0.92";
      dynamic_background_opacity = true;

      # Trailing cursor effect
      cursor_trail = 3;
      cursor_trail_decay = "0.1 0.5";

      # Font configuration
      font_family = "monospace";

      # Primary fallback for monospace text
      bold_font = "auto";
      italic_font = "auto";
      bold_italic_font = "auto";
      font_size = 12;

      # Fallback fonts for missing characters (in order of preference)
      # Noto Sans Mono - excellent Unicode coverage, monospace
      # DejaVu Sans Mono - reliable fallback with good symbol support
      # Liberation Mono - good compatibility fallback
      # Courier New - system fallback
      font_features = "Fira +zero +ss01";

      # Window settings
      confirm_os_window_close = 0;
      hide_window_decorations = "titlebar-only";
      remember_window_size = false;
      initial_window_width = "120c";
      initial_window_height = "30c";

      # Mouse behavior
      mouse_hide_while_typing = true;

      # Shell integration
      shell_integration = "enabled";

      # Tab bar
      tab_bar_edge = "top";
      tab_bar_style = "powerline";
      tab_powerline_style = "slanted";

      # Bell - system sound on Wayland
      enable_audio_bell = false;
      visual_bell_duration = "0.0";

      # Hyprland/Wayland Performance Optimizations
      repaint_delay = 6; # Lower for better responsiveness
      input_delay = 2; # Reduced input latency
      sync_to_monitor = false; # Wayland handles vsync, disable for better performance

      # Wayland-specific scrolling optimizations
      wheel_scroll_multiplier = "3.0";
      touchpad_scroll_multiplier = "1.5";

      # Clipboard optimizations for Wayland
      clipboard_control = "write-clipboard write-primary read-clipboard-ask read-primary-ask";

      # Window management
      single_window_margin_width = -1; # Use padding for single window

      # Scrollback
      scrollback_lines = 10000;
      scrollback_pager_history_size = 0; # Use all scrollback for pager

      # Window padding
      window_padding_width = 8;

      # Wayland titlebar color (matches Catppuccin theme)
      wayland_titlebar_color = "background";

      # Performance: disable unused features
      update_check_interval = 0;

      # Single instance optimizations
      allow_remote_control = true;
      listen_on = "unix:/tmp/kitty";

      # Startup optimizations
      startup_session = "none";

      # Default shell command - tmux integration
      shell = "${pkgs.fish}/bin/fish -l -c 'TMUX_TMPDIR=/run/user/$(id -u) tmux attach || TMUX_TMPDIR=/run/user/$(id -u) tmux new -s main'";
    };

    # Keybindings
    keybindings = {
      "ctrl+shift+t" = "new_tab";
      "ctrl+shift+w" = "close_tab";
      "ctrl+shift+right" = "next_tab";
      "ctrl+shift+left" = "previous_tab";
      "ctrl+equal" = "increase_font_size";
      "ctrl+minus" = "decrease_font_size";
      "ctrl+shift+equal" = "restore_font_size";
      "ctrl+shift+c" = "copy_to_clipboard";
      "ctrl+shift+v" = "paste_from_clipboard";
    };
  };
}
