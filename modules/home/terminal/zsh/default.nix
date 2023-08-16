{
  pkgs,
  config,
  ...
}: {
  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;

    shellAliases = {
      ll = "exa -l --icons --git";
      tree = "exa --tree --icons";
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
          rev = "23.07.0";
          sha256 = "sha256-PNeS/YpL56Ir3xoiUzOU5Tkhq0B5eyudzEuOt2yCqh4=";
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
      auto-ls-ll () {
        exa -l
      }

      auto-ls-gsb () {
        if [[ $(git rev-parse --is-inside-work-tree 2> /dev/null) == true ]]; then
          gsb
        fi
      }

      AUTO_LS_COMMANDS=(ll gsb)
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
