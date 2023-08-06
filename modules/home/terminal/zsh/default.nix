{
  pkgs,
  config,
  ...
}: {
  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;

    shellAliases = {
      ll = "exa -l";
      update = "sudo nixos-rebuild switch";
    };
    history = {
      size = 10000;
      path = "${config.xdg.dataHome}/zsh/history";
    };

    oh-my-zsh = {
      enable = true;
      plugins = ["git" "thefuck" "tmux"];
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
    ];
  };
  programs.fzf = {
    enable = true;
    tmux.enableShellIntegration = true;
    tmux.shellIntegrationOptions = ["-p80%,60%"];
    defaultOptions = ["--height 40%"];
  };
}
