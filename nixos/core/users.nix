{
  config,
  pkgs,
  ...
}: {
  users.users.${config.username} = {
    isNormalUser = true;
    description = config.user-full-name;
    extraGroups = ["networkmanager" "wheel" "video" "input" "i2c"];
    hashedPasswordFile = config.nix-config.user.hashedPasswordFile;
    shell = pkgs.fish;
    # Keep the systemd user manager (and the lazytmux startup tmux server)
    # running across logout, so the remote bridge can reach it over ssh with no
    # interactive session present. lazytmux would otherwise enable this
    # imperatively on first switch; declaring it keeps it revertible.
    linger = true;
  };

  programs.fish.enable = true;
}
