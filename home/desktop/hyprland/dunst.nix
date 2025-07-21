{
  config,
  pkgs,
  lib,
  ...
}: {
  services.dunst = {
    enable = true;

    settings = {
      global = {
        monitor = 0;
        follow = "mouse";
        width = 300;
        height = 300;
        origin = "top-right";
        offset = "10x50";
        scale = 0;
        notification_limit = 0;

        progress_bar = true;
        progress_bar_height = 10;
        progress_bar_frame_width = 1;
        progress_bar_min_width = 150;
        progress_bar_max_width = 300;

        indicate_hidden = "yes";
        transparency = 0;
        separator_height = 2;
        padding = 8;
        horizontal_padding = 8;
        text_icon_padding = 0;
        frame_width = 3;
        frame_color = "#89b4fa";

        separator_color = "frame";
        sort = "yes";
        idle_threshold = 120;

        font = "JetBrains Mono Nerd Font 12";
        line_height = 0;
        markup = "full";
        format = "<b>%s</b>\\n%b";
        alignment = "left";
        vertical_alignment = "center";
        show_age_threshold = 60;
        ellipsize = "middle";
        ignore_newline = "no";
        stack_duplicates = true;
        hide_duplicate_count = false;
        show_indicators = "yes";

        enable_recursive_icon_lookup = true;
        icon_theme = "Papirus";
        icon_position = "left";
        min_icon_size = 32;
        max_icon_size = 128;

        sticky_history = "yes";
        history_length = 20;

        dmenu = "${pkgs.dmenu}/bin/dmenu -p dunst:";
        browser = "${pkgs.firefox}/bin/firefox -new-tab";

        always_run_script = true;
        title = "Dunst";
        class = "Dunst";
        corner_radius = 10;
        ignore_dbusclose = false;

        force_xwayland = false;
        force_xinerama = false;

        mouse_left_click = "close_current";
        mouse_middle_click = "do_action, close_current";
        mouse_right_click = "close_all";
      };

      experimental = {
        per_monitor_dpi = false;
      };

      urgency_low = {
        # Styling handled by catppuccin theme
        timeout = 10;
        # override_pause_level = 30;
      };

      urgency_normal = {
        # Styling handled by catppuccin theme
        timeout = 10;
      };

      urgency_critical = {
        # Styling handled by catppuccin theme
        timeout = 0;
      };
    };
  };
}
