{
  lib,
  inputs,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    lazyjournal
  ];

  programs.television = let
    nix-search-tv = inputs.nix-search-tv.packages.x86_64-linux.default;
  in {
    enable = true;
    enableFishIntegration = true;
    channels = {
      nix-channels = {
        metadata = {
          name = "nixpkgs";
          description = "Search and preview Nix packages";
          requirements = [
            nix-search-tv
          ];
        };
        source.command = "nix-search-tv print";
        preview.command = "nix-search-tv preview {}";
      };
    };

    settings = {
      # General settings
      tick_rate = 50;

      ui = {
        # How much space to allocate for the UI (in percentage of the screen)
        ui_scale = 100;

        # What orientation should tv be (landscape or portrait)
        orientation = "landscape";

        # The theme to use for the UI
        theme = "catppuccin";
      };

      # UI subsections - NEW FORMAT
      "ui.input_bar" = {
        # Where to place the input bar in the UI (top or bottom)
        position = "top";
        # The input prompt string (defaults to ">" if not specified)
        prompt = ">";
        border_type = "rounded";
      };

      "ui.preview_panel" = {
        # Preview panel size (percentage of screen width/height)
        size = 50;
        scrollbar = true;
        border_type = "rounded";
        hidden = false;
      };

      "ui.help_panel" = {
        # Whether to split the help panel by categories
        show_categories = true;
        hidden = true;
      };

      # Keybindings - NEW FORMAT: key = "action"
      keybindings = {
        # Quit the application
        "esc" = "quit";
        "ctrl-c" = "quit";

        # Scrolling through entries
        "down" = "select_next_entry";
        "ctrl-n" = "select_next_entry";
        "ctrl-j" = "select_next_entry";
        "up" = "select_prev_entry";
        "ctrl-p" = "select_prev_entry";
        "ctrl-k" = "select_prev_entry";
        "pagedown" = "scroll_preview_half_page_down";
        "pageup" = "scroll_preview_half_page_up";

        # History navigation
        "ctrl-up" = "select_prev_history";
        "ctrl-down" = "select_next_history";

        # Multi-selection
        "tab" = "toggle_selection_down";
        "backtab" = "toggle_selection_up";

        # Confirm selection
        "enter" = "confirm_selection";

        # Copy the selected entry to the clipboard
        "ctrl-y" = "copy_entry_to_clipboard";

        # Data operations
        "ctrl-r" = "reload_source";
        "ctrl-s" = "cycle_sources";

        # UI Features
        "ctrl-t" = "toggle_remote_control";
        "ctrl-h" = "toggle_help";
        "ctrl-o" = "toggle_preview";
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
      };
    };
  };
}
