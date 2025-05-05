{
  pkgs,
  config,
  osConfig,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    eza
    zoxide
  ];

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;

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
      plugins = ["git" "python" "docker" "docker-compose" "poetry"] ++ lib.optionals (osConfig.profile == "work") ["aws" "localstack"];
      theme = "";
    };

    plugins = [
      {
        name = "forgit";
        src = pkgs.fetchFromGitHub {
          owner = "wfxr";
          repo = "forgit";
          rev = "25.02.0";
          sha256 = "sha256-vVsJe/MycQrwHLJOlBFLCuKuVDwQfQSMp56Y7beEUyg=";
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

    initContent = ''
      unsetopt BEEP
      work_aliases=/etc/agenix/work_aliases.zsh
      if [ -f $work_aliases ]; then
        echo "Loading Work Aliases"
        source $work_aliases
      fi

      host_env=/etc/agenix/host_env.env
      if [ -f $host_env ]; then
        echo "Loading Host Env"
        set -a
        source $host_env
        set +a
      fi

      auto-ls-ll () {
        eza -l --icons --git
      }

      AUTO_LS_COMMANDS=(ll)
      AUTO_LS_NEWLINE=false

      fpath+=~/.zfunc
      autoload -Uz compinit && compinit
    '';
    loginExtra = ''
      export LANG="en_US.UTF-8"
      export LANGUAGE="en_US.UTF-8"
      export LC_ALL="en_US.UTF-8"
    '';
  };

  programs = {
    fzf = {
      enable = true;
      defaultOptions = ["--height 40%"];
    };
  };
}
