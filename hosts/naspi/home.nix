{
  pkgs,
  username,
  ...
}: {
  imports = [
    ../../home/git
    ../../home/terminal/minimal.nix
    ../../home/xdg
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "23.11";

  nix = {
    package = pkgs.nixUnstable;
    settings.experimental-features = ["nix-command" "flakes"];
    # extraOptions = ''
    #   experimental-features = nix-command flakes
    # '';
  };
  programs.home-manager.enable = true;
}
