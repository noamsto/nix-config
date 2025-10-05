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
      force_keyboard_focus = false;
      close_when_open = true;
      selection_wrap = false;
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
        next = ["ctrl j" "Down"]; # Vi-like: Ctrl+j for down/next (works from input field)
        previous = ["ctrl k" "Up"]; # Vi-like: Ctrl+k for up/previous (works from input field)
        toggle_exact = ["ctrl e"];
        resume_last_query = ["ctrl r"];
        quick_activate = ["alt 1" "alt 2" "alt 3" "alt 4"];
      };

      providers = {
        # Default providers list
        default = [
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
        ];

        # Provider-specific configurations
        desktopapplications = {
          default = "start";
          start = ["Return"];
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
      };
    };
  };
}
