{
  pkgs,
  config,
  ...
}: {
  home.packages = with pkgs; [
    eza
  ];

  programs.thefuck.enable = true;

  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;

    shellAliases = {
      ll = "eza -l --icons --git";
      tree = "eza --tree --icons";
      update = "sudo nixos-rebuild switch";
    };

    history = {
      size = 10000;
      path = "${config.xdg.dataHome}/zsh/history";
    };

    oh-my-zsh = {
      enable = true;
      plugins = ["git" "thefuck" "tmux" "python" "z"];
      theme = "";
    };

    plugins = [
      {
        name = "forgit";
        src = pkgs.fetchFromGitHub {
          owner = "wfxr";
          repo = "forgit";
          rev = "24.02.0";
          sha256 = "sha256-DoOtrnEJwSxkCZtsVek+3w9RZH7j7LTvdleBC88xyfI=";
        };
      }
      {
        name = "auto-ls";
        src = pkgs.fetchFromGitHub {
          owner = "desyncr";
          repo = "auto-ls";
          rev = "a7a7e6c16407a3c4a46319f5f111a827468a0943";
          sha256 = "sha256-nLAdHI1y6lL95QKnNN8x5remKobLClnVY5Ia3TZXp5Y=";
        };
      }
      {
        name = "zsh-syntax-highlighting";
        src = pkgs.fetchFromGitHub {
          owner = "zsh-users";
          repo = "zsh-syntax-highlighting";
          rev = "1386f1213eb0b0589d73cd3cf7c56e6a972a9bfd";
          sha256 = "sha256-iKx7lsQCoSAbpANYFkNVCZlTFdwOEI34rx/h1rnraSg=";
        };
      }
    ];

    initExtra = ''
      work_aliases=/etc/agenix/work_aliases.zsh
      if [ -f $work_aliases ]; then
        echo "Loading Work Aliases"
        source $work_aliases
      fi

      auto-ls-ll () {
        eza -l --icons --git
      }

      AUTO_LS_COMMANDS=(ll)
      AUTO_LS_NEWLINE=false
    '';
  };

  programs.fzf = {
    enable = true;
    tmux.enableShellIntegration = true;
    tmux.shellIntegrationOptions = ["-p80%,60%"];
    defaultOptions = ["--height 40%"];
  };
}
