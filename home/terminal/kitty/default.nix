{
  pkgs,
  config,
  lib,
  ...
}: let
  palette = config.theme.palette;

  # Strip # from hex colors for kitty format
  stripHash = color: lib.removePrefix "#" color;

  # Generate kitty theme from palette
  mkKittyTheme = p: ''
    # ${p.name} - Generated from config.theme.palette

    # Basic colors
    foreground              ${p.text}
    background              ${p.base}
    selection_foreground    ${p.base}
    selection_background    ${p.rosewater}

    # Cursor colors
    cursor                  ${p.rosewater}
    cursor_text_color       ${p.base}

    # URL underline color
    url_color               ${p.rosewater}

    # Kitty window border colors
    active_border_color     ${p.lavender}
    inactive_border_color   ${p.overlay0}
    bell_border_color       ${p.yellow}

    # Tab bar colors
    active_tab_foreground   ${p.crust}
    active_tab_background   ${p.mauve}
    inactive_tab_foreground ${p.text}
    inactive_tab_background ${p.mantle}
    tab_bar_background      ${p.crust}

    # Mark colors
    mark1_foreground ${p.base}
    mark1_background ${p.lavender}
    mark2_foreground ${p.base}
    mark2_background ${p.mauve}
    mark3_foreground ${p.base}
    mark3_background ${p.sapphire}

    # Terminal colors
    # black
    color0  ${p.surface1}
    color8  ${p.surface2}

    # red
    color1  ${p.red}
    color9  ${p.red}

    # green
    color2  ${p.green}
    color10 ${p.green}

    # yellow
    color3  ${p.yellow}
    color11 ${p.yellow}

    # blue
    color4  ${p.blue}
    color12 ${p.blue}

    # magenta
    color5  ${p.pink}
    color13 ${p.pink}

    # cyan
    color6  ${p.teal}
    color14 ${p.teal}

    # white
    color7  ${p.subtext1}
    color15 ${p.subtext0}
  '';
in {
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
      font_family = "FiraCode Nerd Font Medium";

      # Primary fallback for monospace text
      bold_font = "FiraCode Nerd Font Bold";
      italic_font = "FiraCode Nerd Font Medium Italic";
      bold_italic_font = "FiraCode Nerd Font Bold Italic";
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
      mouse_hide_wait = -1; # Hide cursor immediately when typing

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
      touch_scroll_multiplier = "1.5";

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
      # Font size
      "ctrl+equal" = "increase_font_size";
      "ctrl+minus" = "decrease_font_size";
      "ctrl+shift+equal" = "restore_font_size";

      # Clipboard
      "ctrl+shift+c" = "copy_to_clipboard";
      "ctrl+shift+v" = "paste_from_clipboard";

      # Allow Ctrl+Shift+- (Ctrl+_) to pass through to shell for undo
      "ctrl+shift+minus" = "no_op";

      # Claude Code: Map Shift+Enter to Alt+Enter for newlines
      "shift+enter" = "send_text all \\x1b\\r";

      # Disable tab/window features (using tmux instead)
      "ctrl+shift+t" = "no_op";
      "ctrl+shift+w" = "no_op";
      "ctrl+shift+right" = "no_op";
      "ctrl+shift+left" = "no_op";
      "ctrl+shift+n" = "no_op";
      "ctrl+shift+enter" = "no_op";
      "ctrl+shift+]" = "no_op";
      "ctrl+shift+[" = "no_op";
      "ctrl+shift+." = "no_op";
      "ctrl+shift+," = "no_op";
      "ctrl+shift+q" = "no_op";
      "ctrl+shift+1" = "no_op";
      "ctrl+shift+2" = "no_op";
      "ctrl+shift+3" = "no_op";
      "ctrl+shift+4" = "no_op";
      "ctrl+shift+5" = "no_op";
      "ctrl+shift+6" = "no_op";
      "ctrl+shift+7" = "no_op";
      "ctrl+shift+8" = "no_op";
      "ctrl+shift+9" = "no_op";
    };
  };

  # Generated kitty theme files (used by theme-toggle)
  xdg.configFile = {
    "kitty/themes/${palette.dark.name}.conf".text = mkKittyTheme palette.dark;
    "kitty/themes/${palette.light.name}.conf".text = mkKittyTheme palette.light;
  };
}
