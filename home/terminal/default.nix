{
  lib,
  osConfig,
  pkgs,
  ...
}: let
  isServer = osConfig.machine.type == "server";
in {
  imports = [
    ./foot
    ./kitty
    ./fish # Migrating from zsh to fish
    ./zsh # Keep temporarily during migration
    ./tmux
    ./process_compose

    ./television
  ];
  programs = {
    yazi = {
      enable = true;
      enableZshIntegration = true;

      plugins = {
        mount = pkgs.yaziPlugins.mount;
        git = pkgs.yaziPlugins.git;
        gvfs = pkgs.fetchFromGitHub {
          owner = "boydaihungst";
          repo = "gvfs.yazi";
          rev = "master";
          sha256 = "sha256-6VNra6WUjDfBdGjCw/6VOAaAgZLF78/4Gj47BOh1Q/0=";
        };
      };

      # Custom yazi configuration
      settings = {
        mgr = {
          show_hidden = false;
          show_symlink = true;
        };
        plugin = {
          prepend_fetchers = [
            {
              id = "git";
              name = "*";
              run = "git";
            }
            {
              id = "git";
              name = "*/";
              run = "git";
            }
          ];
        };
      };

      initLua = ''
        require("git"):setup()
        require("gvfs"):setup()
      '';

      # Custom keybindings for dragon-drop integration
      keymap = {
        mgr.prepend_keymap = [
          {
            on = ["M"];
            run = "plugin mount";
            desc = "Mount plugin";
          }
          {
            on = ["c" "D"];
            run = ''shell --confirm 'dragon-drop --and-exit "$@"' $$'';
            desc = "Drag and drop (exit after)";
          }
          {
            on = ["c" "t"];
            run = ''shell --confirm 'dragon-drop --target' $$'';
            desc = "Dragon drop target (receive files)";
          }
        ];
      };
    };
    btop = {
      enable = true;
      settings = {
        vim_keys = true;
      };
    };

    starship = {
      enable = true;
      enableFishIntegration = true;
      settings = lib.mkMerge [
        {
          add_newline = false;

          # Default palette (can be dynamically changed by theme-toggle.sh)
          palette = "catppuccin_mocha";

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

          # Catppuccin Latte palette (light theme)
          palettes.catppuccin_latte = {
            base = "#eff1f5";
            blue = "#1e66f5";
            crust = "#dce0e8";
            flamingo = "#dd7878";
            green = "#40a02b";
            lavender = "#7287fd";
            mantle = "#e6e9ef";
            maroon = "#e64553";
            mauve = "#8839ef";
            overlay0 = "#9ca0b0";
            overlay1 = "#8c8fa1";
            overlay2 = "#7c7f93";
            peach = "#fe640b";
            pink = "#ea76cb";
            red = "#d20f39";
            rosewater = "#dc8a78";
            sapphire = "#209fb5";
            sky = "#04a5e5";
            subtext0 = "#6c6f85";
            subtext1 = "#5c5f77";
            surface0 = "#ccd0da";
            surface1 = "#bcc0cc";
            surface2 = "#acb0be";
            teal = "#179299";
            text = "#4c4f69";
            yellow = "#df8e1d";
          };

          # Catppuccin Mocha palette (dark theme)
          palettes.catppuccin_mocha = {
            base = "#1e1e2e";
            blue = "#89b4fa";
            crust = "#11111b";
            flamingo = "#f2cdcd";
            green = "#a6e3a1";
            lavender = "#b4befe";
            mantle = "#181825";
            maroon = "#eba0ac";
            mauve = "#cba6f7";
            overlay0 = "#6c7086";
            overlay1 = "#7f849c";
            overlay2 = "#9399b2";
            peach = "#fab387";
            pink = "#f5c2e7";
            red = "#f38ba8";
            rosewater = "#f5e0dc";
            sapphire = "#74c7ec";
            sky = "#89dceb";
            subtext0 = "#a6adc8";
            subtext1 = "#bac2de";
            surface0 = "#313244";
            surface1 = "#45475a";
            surface2 = "#585b70";
            teal = "#94e2d5";
            text = "#cdd6f4";
            yellow = "#f9e2af";
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
