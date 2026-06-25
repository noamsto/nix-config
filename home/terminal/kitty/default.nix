{
  pkgs,
  config,
  ...
}: let
  inherit (config.theme) palette;

  mkKittyTheme = p: ''
    foreground              ${p.text}
    background              ${p.base}
    selection_foreground    ${p.base}
    selection_background    ${p.rosewater}

    cursor                  ${p.rosewater}
    cursor_text_color       ${p.base}

    url_color               ${p.rosewater}

    active_border_color     ${p.lavender}
    inactive_border_color   ${p.overlay0}
    bell_border_color       ${p.yellow}

    active_tab_foreground   ${p.crust}
    active_tab_background   ${p.mauve}
    inactive_tab_foreground ${p.text}
    inactive_tab_background ${p.mantle}
    tab_bar_background      ${p.crust}

    mark1_foreground ${p.base}
    mark1_background ${p.lavender}
    mark2_foreground ${p.base}
    mark2_background ${p.mauve}
    mark3_foreground ${p.base}
    mark3_background ${p.sapphire}

    color0  ${p.surface1}
    color8  ${p.surface2}
    color1  ${p.red}
    color9  ${p.red}
    color2  ${p.green}
    color10 ${p.green}
    color3  ${p.yellow}
    color11 ${p.yellow}
    color4  ${p.blue}
    color12 ${p.blue}
    color5  ${p.pink}
    color13 ${p.pink}
    color6  ${p.teal}
    color14 ${p.teal}
    color7  ${p.subtext1}
    color15 ${p.subtext0}
  '';
in {
  programs.kitty = {
    enable = true;
    # Opt the aeye carousel into kitty-pane mode. Scoped to kitty (not a global
    # session var) so other terminals keep auto-detecting; the kitty-launched
    # shell carries it, and tmux's `update-environment AEYE_HOST` (lazytmux)
    # threads it into the session env where the reconcile hook can see it.
    environment.AEYE_HOST = "kitty";
    # Default dark theme - ensures kitty starts themed before theme-toggle runs.
    # theme-toggle replaces this include line at runtime with the saved preference.
    extraConfig = ''
      include ${config.xdg.configHome}/kitty/themes/${palette.dark.name}.conf
    '';
    settings = {
      background_opacity = "0.92";
      dynamic_background_opacity = true;

      cursor_trail = 3;
      cursor_trail_decay = "0.1 0.5";

      font_family = "FiraCode Nerd Font Medium";
      bold_font = "FiraCode Nerd Font Bold";
      italic_font = "FiraCode Nerd Font Medium Italic";
      bold_italic_font = "FiraCode Nerd Font Bold Italic";
      font_size = 12;
      font_features = "Fira +zero +ss01";

      confirm_os_window_close = 0;
      hide_window_decorations = "titlebar-only";
      remember_window_size = false;
      initial_window_width = "120c";
      initial_window_height = "30c";

      mouse_hide_wait = -1; # hide immediately when typing
      shell_integration = "enabled";

      # macOS: treat both Option keys as Alt/Meta so Option-based bindings (e.g.
      # tmux's M-H/M-L window switching) reach the app instead of composing
      # special characters. No-op on Linux.
      macos_option_as_alt = "yes";

      tab_bar_edge = "top";
      tab_bar_style = "powerline";
      tab_powerline_style = "slanted";

      enable_audio_bell = false;
      visual_bell_duration = "0.0";

      # Wayland perf: lower delays, let compositor handle vsync
      repaint_delay = 6;
      input_delay = 2;
      sync_to_monitor = false;

      wheel_scroll_multiplier = "3.0";
      touch_scroll_multiplier = "1.5";
      clipboard_control = "write-clipboard write-primary read-clipboard-ask read-primary-ask";

      single_window_margin_width = -1;
      scrollback_lines = 10000;
      scrollback_pager_history_size = 0; # use all scrollback for pager
      window_padding_width = 8;
      wayland_titlebar_color = "background";
      update_check_interval = 0;

      allow_remote_control = true;
      listen_on = "unix:/tmp/kitty";
      startup_session = "none";

      # Linux: systemctl start is synchronous + idempotent — it blocks until the
      # unit is active (server created in its own scope) or returns immediately,
      # so the server is never created inside kitty's scope; point tmux at the
      # $XDG_RUNTIME_DIR socket. darwin: lazytmux's launchd agent already started
      # the server on the default /tmp socket, so just attach/create. GUI-launched
      # apps inherit launchd's minimal PATH (no nix profile), so prepend the
      # per-user profile bin — otherwise `tmux` isn't found and the window closes
      # on launch. The profile path resolves the lazytmux-wrapped tmux.
      shell =
        if pkgs.stdenv.hostPlatform.isDarwin
        then "${pkgs.fish}/bin/fish -l -c 'set -gx PATH /etc/profiles/per-user/${config.home.username}/bin $PATH; tmux attach -t nix-config || tmux new -As nix-config -c $HOME/nix-config'"
        else "${pkgs.fish}/bin/fish -l -c 'systemctl --user start tmux-startup.service && TMUX_TMPDIR=/run/user/$(id -u) tmux attach -t nix-config || TMUX_TMPDIR=/run/user/$(id -u) tmux new -As nix-config -c $HOME/nix-config'";
    };

    keybindings = {
      "ctrl+equal" = "increase_font_size";
      "ctrl+minus" = "decrease_font_size";
      "ctrl+shift+equal" = "restore_font_size";
      "ctrl+shift+c" = "copy_to_clipboard";
      "ctrl+shift+v" = "paste_from_clipboard";
      "ctrl+shift+minus" = "no_op";
      "shift+enter" = "send_text all \\e[13;2u";

      # Using tmux instead
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

  xdg.configFile = {
    "kitty/themes/${palette.dark.name}.conf".text = mkKittyTheme palette.dark;
    "kitty/themes/${palette.light.name}.conf".text = mkKittyTheme palette.light;
  };
}
