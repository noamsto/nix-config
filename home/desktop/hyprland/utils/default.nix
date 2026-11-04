{...}: {
  imports = [
    ./hypridle.nix
    # screen-lock.nix removed - using Noctalia's built-in lock screen
    # wleave/wlogout replaced by Noctalia session menu
  ];
}
