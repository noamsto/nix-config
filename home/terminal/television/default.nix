{
  lib,
  inputs,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    lazyjournal
  ];

  # Install the tv-integration.fish file to Fish's conf.d directory
  # Fish automatically sources all .fish files in conf.d/ on shell startup
  home.file.".config/fish/conf.d/tv-integration.fish".source = ./tv-integration.fish;

  programs.television = {
    enable = true;
    enableFishIntegration = false;
    channels = {
      nix-channels = {
        metadata = {
          name = "nixpkgs";
          description = "Search and preview Nix packages";
          requirements = [
            pkgs.nix-search-tv
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
    };
  };
}
