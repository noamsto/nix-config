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
      gsb = "git status -sb"; # short status with branch info
      gst = "git status"; # full status
      gpf = "git push --force-with-lease"; # safe force push (gp! in plugin-git)
      gpu = "git push -u origin HEAD"; # push and set upstream
      gp = "git push"; # simple push
      gl = "git pull"; # pull
      gf = "git fetch"; # fetch
      gfa = "git fetch --all --prune"; # fetch all with prune
      gcom = "git checkout main || git checkout master"; # checkout main/master
      gwip = "git add -A && git commit -m 'WIP'"; # work in progress commit
      gunwip = "git reset HEAD~1"; # undo last commit (simplified)
      gaa = "git add --all"; # add all
      gc = "git commit -v"; # commit with verbose
      gcm = "git commit -m"; # commit with message
      gca = "git commit -v -a"; # commit all with verbose
      gcan = "git commit -v -a --no-edit --amend"; # amend all without editing
      grhh = "git reset --hard"; # hard reset
      gup = "git pull --rebase"; # pull with rebase
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
      {
        name = "tmux.fish";
        src = pkgs.fetchFromGitHub {
          owner = "budimanjojo";
          repo = "tmux.fish";
          rev = "main";
          hash = "sha256-rRibn+FN8VNTSC1HmV05DXEa6+3uOHNx03tprkcjjs8=";
        };
      }
    ];

    interactiveShellInit = ''
      # Disable greeting
      set fish_greeting

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
      defaultOptions = ["--height 40%"];
      fileWidgetOptions = [
        "--preview '${pkgs.bat}/bin/bat -n --color=always {}'"
        "--bind 'ctrl-/:change-preview-window(down|hidden|)'"
      ];
    };

    yazi = {
      enable = true;
      enableFishIntegration = true;
    };
  };
}
