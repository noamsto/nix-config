{
  lib,
  osConfig,
  ...
}: let
  isServer = osConfig.machine.type == "server";
in {
  imports = [
    ./foot
    ./fish # Migrating from zsh to fish
    ./zsh # Keep temporarily during migration
    ./tmux
    ./process_compose

    ./tui.nix
  ];
  programs = {
    yazi = {
      enable = true;
      enableZshIntegration = true;
    };
    btop = {
      enable = true;
      settings = {
        vim_keys = true;
      };
    };

    starship = {
      enable = true;
      settings = lib.mkMerge [
        {
          add_newline = false;

          # Essential format for all systems
          format = lib.concatStrings [
            "$nix_shell"
            "$username"
            "$hostname"
            "$directory"
            "$git_branch"
            "$git_state"
            "$git_status"
            "$package"
            "$nodejs"
            "$python"
            "$rust"
            "$golang"
            "$cmd_duration"
            "$line_break"
            "$jobs"
            "$character"
          ];

          # Nix shell indicator
          nix_shell = {
            format = "[$symbol$state]($style) ";
            symbol = "❄️ ";
            style = "bold blue";
          };

          # Package version (for package.json, pyproject.toml, etc.)
          package = {
            format = "[$symbol$version]($style) ";
            symbol = "📦 ";
            style = "bold yellow";
          };

          # Directory configuration
          directory = {
            truncation_length = 3;
            truncate_to_repo = true;
            style = "bold cyan";
          };

          # Git branch
          git_branch = {
            format = "[$symbol $branch(:$remote_branch)]($style) ";
            symbol = "";
            style = "bold purple";
          };

          # Git status - simplified, only non-defaults
          git_status = {
            conflicted = "⚡";
            ahead = "⇡\${count}";
            behind = "⇣\${count}";
            diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
            up_to_date = "";
          };

          # Command duration
          cmd_duration = {
            min_time = 2000;
            style = "bold yellow";
          };

          # Language modules - only symbols
          nodejs.symbol = "󰎙 ";
          python.symbol = "󰌠 ";
          rust.symbol = "󱘗 ";
          golang.symbol = " ";

          # Jobs indicator
          jobs = {
            symbol = "✦";
            style = "bold blue";
          };

          # Character (prompt symbol)
          character = {
            success_symbol = "[❯](bold green)";
            error_symbol = "[❯](bold red)";
            vimcmd_symbol = "[❮](bold yellow)";
          };
        }
        (lib.mkIf
          isServer
          {
            # Server-specific overrides
            username.show_always = true;
            hostname.ssh_only = false;
          })
      ];
    };

    bat.enable = true;
  };
}
