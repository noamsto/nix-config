{
  pkgs,
  username,
  ...
}: {
  imports = [
    ../../home/git
    ../../home/terminal/minimal.nix
    ../../home/terminal/tmux
    ../../home/xdg
    ../../home/server-packages.nix
    ../../home/nvim/minimal.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "23.11";

  home.shellAliases = {
    xoff = "alias xoff='sudo /usr/local/bin/xSoft.sh 0 27'";
    snvim = "NVIM_APPNAME=nvim-minimal sudo -E ~/.nix-profile/bin/nvim";
  };

  nixpkgs.config.allowUnfree = true;
  nix = {
    package = pkgs.nixUnstable;
    settings.experimental-features = ["nix-command" "flakes"];
    settings.trusted-users = [username];
  };
  programs.home-manager.enable = true;
}
