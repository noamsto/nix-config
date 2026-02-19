{
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}: let
  isServer = osConfig.machine.type == "server";
in {
  # Add ~/.local/bin to PATH for tools that install there (pip --user, cargo install, etc.)
  # Also silences Claude Code "native installation" warning
  home.sessionPath = ["$HOME/.local/bin"];

  imports = [
    inputs.lazytmux.homeManagerModules.default
    ./foot
    ./kitty
    ./fish
    ./process_compose
    ./television
    ./btop.nix
    ./lazydocker.nix
  ];
  programs.lazytmux = {
    enable = true;
    wt.enable = true;
    startupSession = {
      enable = true;
      name = "nix-config";
      directory = "%h/nix-config";
      terminal = {
        term = "xterm-kitty";
        colorterm = "truecolor";
        termProgram = "kitty";
        terminfoPath = "${pkgs.kitty}/share/terminfo";
      };
    };
  };

  programs = {
    yazi = {
      enable = true;
      enableFishIntegration = true;
      shellWrapperName = "y";

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

    starship = {
      enable = true;
      enableFishIntegration = true;
      settings = lib.mkMerge [
        {
          add_newline = false;

          palette = "catppuccin_mocha";

          # Minimal format - only what matters
          format = lib.concatStrings [
            "$nix_shell"
            "$direnv"
            "$directory"
            "$git_branch"
            "$git_status"
            "$cmd_duration"
            "$line_break"
            "$character"
          ];

          nix_shell = {
            format = "[❄ $state]($style) ";
            style = "bold blue";
          };

          direnv = {
            disabled = false;
            format = "[$loaded]($style) ";
            style = "bold teal";
            loaded_msg = "📂";
            unloaded_msg = "";
            allowed_msg = "";
            not_allowed_msg = "📂!";
            denied_msg = "";
          };

          directory = {
            truncation_length = 4;
            truncate_to_repo = true;
            fish_style_pwd_dir_length = 1;
            style = "bold sapphire";
          };

          git_branch = {
            format = "[$symbol$branch]($style) ";
            symbol = " ";
            style = "bold mauve";
          };

          git_status = {
            format = "[$all_status$ahead_behind]($style) ";
            style = "bold red";
            conflicted = "!";
            ahead = "⇡";
            behind = "⇣";
            diverged = "⇕";
            up_to_date = "";
            stashed = "≡";
          };

          cmd_duration = {
            min_time = 2000;
            style = "bold peach";
          };

          character = {
            success_symbol = "[󰈺](bold green)";
            error_symbol = "[󰈺](bold red)";
            vimcmd_symbol = "[](bold blue)";
            vimcmd_visual_symbol = "[](bold peach)";
            vimcmd_replace_one_symbol = "[](bold orange)";
          };

          # Catppuccin Latte palette (light theme) - WCAG AA compliant modifications
          palettes.catppuccin_latte = {
            base = "#eff1f5";
            blue = "#1e66f5";
            crust = "#dce0e8";
            flamingo = "#b84545"; # Darkened for 4.8:1 contrast
            green = "#358023"; # Darkened for 4.5:1 contrast
            lavender = "#4a5fc9"; # Darkened for 4.7:1 contrast
            mantle = "#e6e9ef";
            maroon = "#e64553";
            mauve = "#8839ef";
            overlay0 = "#9ca0b0";
            overlay1 = "#8c8fa1";
            overlay2 = "#7c7f93";
            peach = "#c24b00"; # Darkened for 4.6:1 contrast
            pink = "#b84a9e"; # Darkened for 4.6:1 contrast
            red = "#d20f39";
            rosewater = "#a85847"; # Darkened for 4.7:1 contrast
            sapphire = "#0d7489"; # Darkened for 4.8:1 contrast
            sky = "#0077a3"; # Darkened for 4.5:1 contrast
            subtext0 = "#6c6f85";
            subtext1 = "#5c5f77";
            surface0 = "#ccd0da";
            surface1 = "#bcc0cc";
            surface2 = "#acb0be";
            teal = "#127275"; # Darkened for 4.5:1 contrast
            text = "#4c4f69";
            yellow = "#996b00"; # Darkened for 4.7:1 contrast
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
