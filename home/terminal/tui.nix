{
  lib,
  inputs,
  ...
}: let
  nix-search-tv = inputs.nix-search-tv.packages.x86_64-linux.default;
  nix-search-tv-bin = lib.getExe nix-search-tv;
in {
  programs.television = {
    enable = true;
    enableZshIntegration = true;
    channels = {
      nix-channels = {
        cable_channel = [
          {
            name = "nixpkgs";
            source_command = "${nix-search-tv-bin} print";
            preview_command = "${nix-search-tv-bin} preview {}";
          }
        ];
      };
    };

    settings = {
      # General settings
      tick_rate = 50;

      ui = {
        # Whether to use nerd font icons in the UI
        # This option requires a font patched with Nerd Font in order to properly
        # display glyphs (see https://www.nerdfonts.com/ for more information)
        use_nerd_font_icons = true;

        # How much space to allocate for the UI (in percentage of the screen)
        ui_scale = 100;

        # Whether to show the top help bar in the UI by default
        # This option can be toggled with the (default) `ctrl-g` keybinding
        show_help_bar = false;

        # Whether to show the preview panel in the UI by default
        # This option can be toggled with the (default) `ctrl-o` keybinding
        show_preview_panel = true;

        # Where to place the input bar in the UI (top or bottom)
        input_bar_position = "top";

        # What orientation should tv be (landscape or portrait)
        orientation = "landscape";

        # The theme to use for the UI
        theme = "catppuccin";
      };

      # Keybindings
      keybindings = {
        # Quit the application
        quit = ["esc" "ctrl-c"];

        # Scrolling through entries
        select_next_entry = ["down" "ctrl-n" "ctrl-j"];
        select_prev_entry = ["up" "ctrl-p" "ctrl-k"];
        select_next_page = "pagedown";
        select_prev_page = "pageup";

        # Scrolling the preview pane
        scroll_preview_half_page_down = "ctrl-d";
        scroll_preview_half_page_up = "ctrl-u";

        # Add entry to selection and move to the next entry
        toggle_selection_down = "tab";

        # Add entry to selection and move to the previous entry
        toggle_selection_up = "backtab";

        # Confirm selection
        confirm_selection = "enter";

        # Copy the selected entry to the clipboard
        copy_entry_to_clipboard = "ctrl-y";

        # Toggle the remote control mode
        toggle_remote_control = "ctrl-r";

        # Toggle the send to channel mode
        toggle_send_to_channel = "ctrl-s";

        # Toggle the help bar
        toggle_help = "ctrl-g";

        # Toggle the preview panel
        toggle_preview = "ctrl-o";
      };

      # Shell integration
      shell_integration = {
        # This specifies the default fallback channel if no other channel is matched.
        fallback_channel = "files";

        channel_triggers = {
          "alias" = ["alias" "unalias"];
          "env" = ["export" "unset"];
          "dirs" = ["cd" "ls" "rmdir"];
          "files" = [
            "cat"
            "less"
            "head"
            "tail"
            "vim"
            "nano"
            "bat"
            "cp"
            "mv"
            "rm"
            "touch"
            "chmod"
            "chown"
            "ln"
            "tar"
            "zip"
            "unzip"
            "gzip"
            "gunzip"
            "xz"
          ];
          "git-diff" = ["git add" "git restore"];
          "git-branch" = [
            "git checkout"
            "git branch"
            "git merge"
            "git rebase"
            "git pull"
            "git push"
          ];
          "docker-images" = ["docker run"];
          "git-repos" = ["nvim" "code" "hx" "git clone"];
        };

        keybindings = {
          # controls which key binding should trigger tv for shell autocomplete
          smart_autocomplete = "ctrl-t";
          # controls which keybinding should trigger tv for command history
          command_history = "ctrl-r";
        };
      };
    };
  };
}
