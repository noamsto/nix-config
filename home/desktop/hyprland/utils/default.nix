{...}: {
  imports = [
    ./hypridle.nix
    ./screen-lock.nix # Unified screen locking solution
    # wleave/wlogout replaced by Noctalia session menu
  ];
}
