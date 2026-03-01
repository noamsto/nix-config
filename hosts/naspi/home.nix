{
  pkgs,
  osConfig,
  ...
}: {
  imports = [
    ../../home/git
    ../../home/terminal/minimal.nix
    ../../home/terminal/tmux
    ../../home/xdg
    ../../home/packages.nix
    ../../home/nvim/minimal.nix
  ];

  home = {
    inherit (osConfig) username;
    homeDirectory = "/home/${osConfig.username}";
    stateVersion = "25.05";
    sessionVariables = {
      FLAKE = "/home/noams/nix-config";
    };
    shellAliases = {
      xoff = "alias xoff='sudo /usr/local/bin/xSoft.sh 0 27'";
      snvim = "NVIM_APPNAME=nvim-minimal sudo -E ~/.nix-profile/bin/nvim";
    };
  };

  nixpkgs.config.allowUnfree = true;
  nix = {
    package = pkgs.nixdocument_versions.latest;
    settings.experimental-features = ["nix-command" "flakes"];
    settings.trusted-users = [osConfig.username];
  };
  programs.home-manager.enable = true;
}
