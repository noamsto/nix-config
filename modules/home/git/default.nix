{
  config,
  pkgs,
  ...
}: {
  # basic configuration of git, please change to your own
  programs.git = {
    enable = true;
    userName = "Noam Stolero";
    userEmail = "nstolero@barracuda.com";
    diff-so-fancy.enable = true;
    extraConfig = {
      color = {
        ui = true;
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
  };
}
