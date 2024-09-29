{
  config,
  osConfig,
  inputs,
  pkgs,
  ...
}: {
  # basic configuration of git, please change to your own
  xdg.configFile."delta/themes.gitconfig".source = "${inputs.delta}/themes.gitconfig";
  programs.git = {
    enable = true;
    userName = osConfig.user-full-name;
    userEmail = osConfig.email;
    diff-so-fancy = {
      enable = true;
    };
    extraConfig = {
      init = {
        defaultBranch = "main";
      };
      merge = {
        conflictstyle = "diff3";
      };
      color = {
        diff-highlight = {
          oldNormal = "red bold";
          oldHighlight = "red bold 52";
          newNormal = "green bold";
          newHighlight = "green bold 22";
        };
        diff = {
          meta = "11";
          frag = "magenta bold";
          func = "146 bold";
          commit = "yellow bold";
          old = "red bold";
          new = "green bold";
          whitespace = "red reverse";
        };
      };
    };
    ignores = [
      "**/.direnv"
      "**/.devenv"
      "**/.venv"
    ];
  };
}
