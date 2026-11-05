{
  config,
  lib,
  pkgs,
  ...
}: {
  users.users.${config.username} = {
    isNormalUser = true;
    # Pinned so the uid is known at eval time (tmpfiles rules name it); 1000 is
    # what auto-allocation gives the first normal user anyway.
    uid = lib.mkDefault 1000;
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
