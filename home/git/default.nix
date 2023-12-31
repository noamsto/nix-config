{
  config,
  user_email,
  user_full_name,
  inputs,
  ...
}: {
  # basic configuration of git, please change to your own
  xdg.configFile."delta/themes.gitconfig".source = "${inputs.delta}/themes.gitconfig";
  programs.git = {
    enable = true;
    userName = user_full_name;
    userEmail = user_email;
    delta = {
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
