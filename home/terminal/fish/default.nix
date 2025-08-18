{pkgs, ...}: {
  home.packages = with pkgs; [
    eza
    zoxide
    grc
    nix-search-tv
  ];

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.fish = {
    enable = true;

    # Fish uses its own history format, no need to configure path
    # History is automatically stored in ~/.local/share/fish/fish_history

    shellAliases = {
      ll = "eza -l --icons --git";
      tree = "eza --tree --icons";
      update = "sudo nixos-rebuild switch";
      ns = "nix-search-tv print | fzf --height 40% --preview 'nix-search-tv preview {}' --scheme=history --bind 'ctrl-/:change-preview-window(down|hidden|)'";

      # Essential git aliases not covered by forgit (forgit has ga, gd, glo, gcb, gss, grb, etc.)
      gsb = "git status -sb";
      gst = "git status";
      gsw = "git switch";
      gpf = "git push --force-with-lease";
      gpu = "git push -u origin HEAD";
      gp = "git push";
      gl = "git pull";
      gf = "git fetch";
      gfa = "git fetch --all --prune";
      gcom = "git checkout main || git checkout master";
      gwip = "git add -A && git commit -m 'WIP'";
      gunwip = "git reset HEAD~1";
      gaa = "git add --all";
      gc = "git commit -v";
      gcm = "git commit -m";
      gca = "git commit -v -a";
      gcan = "git commit -v -a --no-edit --amend";
      grhh = "git reset --hard";
      gup = "git pull --rebase";
    };

    plugins = with pkgs.fishPlugins; [
      {
        name = "forgit";
        src = forgit.src;
      }
      {
        name = "grc";
        src = grc.src;
      }
      {
        name = "fzf-fish";
        src = fzf-fish.src;
      }
      {
        name = "autopair";
        src = autopair.src;
      }
    ];

    interactiveShellInit = ''
      # Disable greeting
      set fish_greeting

      # Tmux function to auto-attach or create session
      function tmux
        if test (count $argv) -eq 0
          # No arguments, use smart attach/create behavior
          if command tmux has-session 2>/dev/null
            command tmux attach-session
          else
            command tmux new-session
          end
        else
          # Arguments provided, pass them through to tmux
          command tmux $argv
        end
      end

      # Load work aliases if available
      if test -f /etc/agenix/work_aliases.fish
        echo "Loading Work Aliases"
        source /etc/agenix/work_aliases.fish
      end

      # Load host environment if available
      if test -f /etc/agenix/host_env.env
        echo "Loading Host Env"
        # Fish can source bash-style env files
        for line in (cat /etc/agenix/host_env.env)
          if test -n "$line"; and not string match -q '#*' "$line"
            set -gx (string split '=' -- "$line")
          end
        end
      end

      # Vi mode (built-in)
      fish_vi_key_bindings

      # Fix C-P and C-N for history navigation (restore after FZF)
      bind \cp up-or-search
      bind \cn down-or-search
      bind -M insert \cp up-or-search
      bind -M insert \cn down-or-search

      # Fix C-F to accept autosuggestions in vi insert and normal mode
      bind -M insert \cf accept-autosuggestion
      bind -M default \cf accept-autosuggestion
    '';

    loginShellInit = ''
      # Locale settings
      set -gx LANG "en_US.UTF-8"
      set -gx LANGUAGE "en_US.UTF-8"
      set -gx LC_ALL "en_US.UTF-8"
    '';
  };

  programs = {
    fzf = {
      enable = true;
      enableFishIntegration = true;
      defaultOptions = ["--height 45% --tmux='80%,60%'"];
      fileWidgetOptions = [
        "--preview '${pkgs.bat}/bin/bat -n --color=always {}'"
        "--bind 'ctrl-/:change-preview-window(down|hidden|)'"
      ];
    };

    yazi = {
      enable = true;
      enableFishIntegration = true;

      # Custom yazi configuration (same as zsh config)
      settings = {
        manager = {
          show_hidden = false;
          show_symlink = true;
        };
      };

      # Custom keybindings for dragon-drop integration
      keymap = {
        manager.prepend_keymap = [
          {
            on = ["<Space>" "d"];
            run = ''shell --confirm 'dragon-drop "$@"' $$'';
            desc = "Drag and drop selected files";
          }
          {
            on = ["<Space>" "D"];
            run = ''shell --confirm 'dragon-drop --and-exit "$@"' $$'';
            desc = "Drag and drop (exit after)";
          }
          {
            on = ["<Space>" "c"];
            run = ''shell --confirm 'dragon-drop --copy "$@"' $$'';
            desc = "Drag and drop (copy mode)";
          }
          {
            on = ["<Space>" "t"];
            run = ''shell --confirm 'dragon-drop --target' $$'';
            desc = "Dragon drop target (receive files)";
          }
        ];
      };
    };
  };
}
