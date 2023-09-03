{
  config,
  pkgs,
  user_email,
  user_full_name,
  ...
}: {
  # basic configuration of git, please change to your own
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
      };
    };
    extraConfig = {
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
  };
}
