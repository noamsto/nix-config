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
    delta = {
      package = pkgs.stable.delta;
      enable = true;
      options = {
        navigate = true;
        light = false;
        line-numbers = true;
        true-color = "always";
        features = "villsau";
      };
    };
    extraConfig = {
      include = {
        path = "${config.xdg.configHome}/delta/themes.gitconfig";
      };
      init = {
        defaultBranch = "main";
      };
      merge = {
        conflictstyle = "diff3";
      };
      diff = {
        colorMoved = "default";
      };
    };
    ignores = [
      "**/.direnv"
      "**/.devenv"
      "**/.venv"
    ];
  };
}
