{osConfig, ...}: {
  imports = [
    ../../home/git
    ../../home/terminal/minimal.nix
    ../../home/xdg
    ../../home/packages.nix
    ../../home/nvim/minimal.nix
  ];

  home = {
    inherit (osConfig) username;
    homeDirectory = "/home/${osConfig.username}";
    stateVersion = "25.05";
    sessionVariables = {
      FLAKE = "/home/${osConfig.username}/nix-config";
    };
    shellAliases = {
      xoff = "alias xoff='sudo /usr/local/bin/xSoft.sh 0 27'";
      snvim = "NVIM_APPNAME=nvim-minimal sudo -E ~/.nix-profile/bin/nvim";
    };
  };

  nixpkgs.config.allowUnfree = true;
  programs.home-manager.enable = true;
}
