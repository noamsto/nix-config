{
  inputs,
  pkgs,
  ...
}: {
  imports = [inputs.walker.homeManagerModules.default];

  home.packages = with pkgs; [
    libqalculate
    iwmenu
  ];

  programs.walker = {
    enable = true;
    runAsService = true;

    config = {
      # General settings
      force_keyboard_focus = true;
      close_when_open = true;
      selection_wrap = true; # Enable vim-like wrapping from bottom to top
      global_argument_delimiter = "#";
      keep_open_modifier = "shift";
      exact_search_prefix = "'";
      theme = "default";
      disable_mouse = false;

      # Shell positioning
      shell = {
        anchor_top = true;
        anchor_bottom = true;
        anchor_left = true;
        anchor_right = true;
      };

      # Placeholders
      placeholders = {
        default = {
          input = "Search";
          list = "No Results";
        };
      };

      # Vi-like keybindings where they make sense
      keybinds = {
        close = ["Escape"];
        next = ["ctrl j" "ctrl n" "Down"]; # Vi-like: Ctrl+j/n for down/next (works from input field)
        previous = ["ctrl k" "ctrl p" "Up"]; # Vi-like: Ctrl+k/p for up/previous (works from input field)
        toggle_exact = ["ctrl e"];
        resume_last_query = ["ctrl r"];
        quick_activate = ["alt 1" "alt 2" "alt 3" "alt 4"];
      };
      #
      providers = {
        # Default providers list
        default = [
          "windows"
          "desktopapplications"
          "calc"
          "runner"
          "menus"
          "websearch"
        ];

        # Empty query providers
        empty = ["desktopapplications"];

        # Prefix configurations - keeping your existing ones plus useful additions
        prefixes = [
          {
            provider = "providerlist";
            prefix = ";"; # Changed from "_" to ";" (more vi-like command mode)
          }
          {
            provider = "files";
            prefix = "/";
          }
          {
            provider = "symbols";
            prefix = ".";
          }
          {
            provider = "todo";
            prefix = "!";
          }
          {
            provider = "calc";
            prefix = "=";
          }
          {
            provider = "websearch";
            prefix = "@";
          }
          {
            provider = "clipboard";
            prefix = ":";
          }
          {
            provider = "windows";
            prefix = "w";
          }
        ];

        # Provider-specific configurations
        desktopapplications = {
          min_score = 20; # Require better match to show apps (higher = more selective)
          window_integration = true; # Focus existing windows instead of launching new instances
          window_integration_ignore_actions = true; # Ignore window integration for app actions
          score_open_windows = true; # Deprioritize apps that are already open
          history = false; # Disable history so apps don't outrank their windows
          history_when_empty = false; # Don't use history even when query is empty
          show_actions = true; # Show app actions (New Window, Private Window, etc.)
          action_min_score = 20; # Same threshold as main apps
          show_generic = true; # Include generic app info with actions
          default = "focus";
          focus = ["Return"];
          start_keep_open = ["shift Return"];
          remove_history = ["ctrl BackSpace"];
          toggle_pin = ["ctrl p"];
        };

        calc = {
          default = "copy";
          copy = ["Return"];
          save = ["ctrl s"];
          delete = ["ctrl d"]; # Vi-like: d for delete
        };

        websearch = {
          default = "search";
          search = ["Return"];
          remove_history = ["ctrl BackSpace"];
        };

        providerlist = {
          default = "activate";
          activate = ["Return"];
        };

        clipboard = {
          time_format = "%d.%m. - %H:%M";
          default = "copy";
          copy = ["Return"];
          delete = ["ctrl d"]; # Vi-like: d for delete
          edit = ["ctrl o"]; # Vi-like: o for open/edit
          toggle_images_only = ["ctrl i"];
        };

        files = {
          default = "open";
          open = ["Return"];
          open_dir = ["ctrl Return"];
          copy_path = ["ctrl shift c"];
          copy_file = ["ctrl c"];
        };

        todo = {
          default = "save";
          save = ["Return"];
          delete = ["ctrl d"]; # Vi-like: d for delete
          mark_active = ["ctrl a"];
          mark_done = ["ctrl f"]; # f for finished/done
          clear = ["ctrl x"]; # x for clear (vi-like delete char)
        };

        runner = {
          default = "start";
          start = ["Return"];
          start_terminal = ["shift Return"];
          remove_history = ["ctrl BackSpace"];
        };

        dmenu = {
          default = "select";
          select = ["Return"];
        };

        symbols = {
          default = "copy";
          copy = ["Return"];
          remove_history = ["ctrl BackSpace"];
        };

        unicode = {
          default = "copy";
          copy = ["Return"];
          remove_history = ["ctrl BackSpace"];
        };

        menus = {
          default = "activate";
          activate = ["Return"];
          remove_history = ["ctrl BackSpace"];
        };

        windows = {
          min_score = -100; # Very low = always show windows even with weak matches
          delay = 50; # Faster focus switching (default is 100ms)
          default = "focus";
          focus = ["Return"];
          close = ["ctrl d"];
          fullscreen = ["ctrl f"];
        };
      };
    };
  };
}
