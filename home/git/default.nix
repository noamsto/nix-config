{
  osConfig,
  lib,
  ...
}: let
  signKey =
    if (osConfig.profile == "work")
    then "~/.ssh/noam_factify_ed25519.pub"
    else "~/.ssh/id_ed25519.pub";
in {
  imports = [
    ./lazygit.nix
  ];
  xdg.configFile."git/allowed_signers".text = ''
    noam@factify.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKd4OIEupUNYzTppiP4zy9XLpBz/zzCYmWklC0YXrHPh
    noamstolero@gmail.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKXagBGbjJ7dHNZWKvkCqd3FNshl4conuFDO03OXnNvC
  '';
  # basic configuration of git, please change to your own
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
      signing.format = "ssh";
      gpg.ssh.allowedSignersFile = "~/.config/git/allowed_signers";
      commit.gpgsign = true;
      user.signingkey = signKey;
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
